# /// script
# requires-python = ">=3.11"
# dependencies = ["pyarrow>=17"]
# ///
"""Set species habitat from FishBase, and add the fish the size limits name.

build_species_dataset.py gives every species it adds from iNaturalist the
habitat "freshwater" as a stand-in, so reef fish and sea fish read as
freshwater in the guide, the Fishdex and the species pages. This script
replaces the stand-in with FishBase's own Fresh, Brack and Saltwater flags:

    Saltwater only                  marine
    Fresh only                      freshwater
    Brack alone, or with both       brackish
    Fresh and Saltwater, no Brack   brackish (it moves between them)
    Brack with one other            that other (a sea fish that also
                                    enters estuaries is still a sea fish)

Records 1 to 194 are the hand-curated list from generate_species.py. Their
habitat was set by hand (rainbow trout is freshwater, though FishBase flags it
fresh, brackish and marine) and is kept unless --all is given. A species
FishBase does not know keeps its current value and is printed.

With --add-limit-species it also adds the fish in fishing_regulations.json
that the seed lacks, when FishBase gives their family and temperatures. They
keep the scientific name the size limits use, which is how the size limits
page finds them. New species get ids after the current highest; existing ids
never change.

FishBase tables come from the rOpenSci snapshot on Hugging Face
(cboettig/fishbase, CC BY-NC 4.0). Download one release into an empty folder
outside the repo:

    mkdir -p /tmp/fishbase/v25.04 && cd /tmp/fishbase/v25.04
    for t in species synonyms families stocks estimate; do
      curl -fLO https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb/v25.04/parquet/$t.parquet
    done

Then, from the repo root:

    uv run scripts/fishbase_species.py --fishbase /tmp/fishbase/v25.04 --dry-run
    uv run scripts/fishbase_species.py --fishbase /tmp/fishbase/v25.04 --add-limit-species

Existing installs pick the changes up on the next launch: SpeciesRepository
re-upserts every row when the bundled list grows or its seedDataVersion is
bumped. Catches keep pointing at the same ids.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pyarrow.parquet as pq

REPO = Path(__file__).resolve().parents[1]
DATA = REPO / "ios/Currents/Resources/Data"
SEED_JSON = DATA / "species_seed.json"
LIMITS_JSON = DATA / "fishing_regulations.json"

# The hand-curated records (generate_species.py, and the inline copy in
# SpeciesSeedData.swift).
CURATED_MAX_ID = 194

# Synonym rows that name the species itself. Misapplied and ambiguous names
# point at other fish.
SYNONYM_STATUS = {"accepted name", "provisionally accepted name", "synonym"}

# iNaturalist splits FishBase has not adopted: the FishBase species each one
# was split from, whose habitat it shares.
SPLIT_FROM = {
    "Micropterus nigricans": "Micropterus salmoides",       # largemouth bass
    "Lepomis aquilensis": "Lepomis megalotis",              # longear sunfish
    "Lepomis solis": "Lepomis megalotis",
    "Acanthurus sandvicensis": "Acanthurus triostegus",     # convict surgeonfish
    "Pseudanthias cheirospilos": "Pseudanthias squamipinnis",
    "Gomphosus klunzingeri": "Gomphosus caeruleus",
    "Coris melanura": "Coris julis",
    "Halichoeres annularis": "Halichoeres marginatus",
    "Pteropterus antennatus": "Pterois antennata",
    "Pteropterus cinctus": "Pterois cincta",
    "Rutilus lacustris": "Rutilus rutilus",
    "Fundulus cryptocatenatus": "Fundulus catenatus",
}


def norm(name: str) -> str:
    return " ".join(name.strip().lower().split())


def stem(epithet: str) -> str:
    """The epithet without its Latin gender ending: picus and pica match."""
    for end in ("ii", "ae", "us", "um", "is", "a", "e", "i"):
        if epithet.endswith(end) and len(epithet) > len(end) + 2:
            return epithet[: -len(end)]
    return epithet


def habitat(fresh: int | None, brack: int | None, salt: int | None) -> str | None:
    f, b, s = bool(fresh), bool(brack), bool(salt)
    if f and s:
        return "brackish"
    if f:
        return "freshwater"
    if s:
        return "marine"
    return "brackish" if b else None


class FishBase:
    def __init__(self, folder: Path, extra: bool) -> None:
        cols = ["SpecCode", "Genus", "Species", "FBname", "FamCode", "Fresh", "Brack", "Saltwater"]
        self.species = {r["SpecCode"]: r for r in pq.read_table(folder / "species.parquet", columns=cols).to_pylist()}
        self.by_name = {norm(f'{r["Genus"]} {r["Species"]}'): c for c, r in self.species.items()}

        self.by_synonym: dict[str, set[int]] = defaultdict(set)
        for r in pq.read_table(folder / "synonyms.parquet", columns=["SpecCode", "SynGenus", "SynSpecies", "Status"]).to_pylist():
            if r["SynGenus"] and r["SynSpecies"] and r["Status"] in SYNONYM_STATUS and r["SpecCode"] in self.species:
                self.by_synonym[norm(f'{r["SynGenus"]} {r["SynSpecies"]}')].add(r["SpecCode"])

        # Every known name, keyed by genus and epithet stem, for spelling
        # variants; and by epithet stem alone, for genus moves.
        self.by_stem: dict[tuple[str, str], set[int]] = defaultdict(set)
        self.by_epithet: dict[str, set[int]] = defaultdict(set)
        for name, codes in [(n, {c}) for n, c in self.by_name.items()] + list(self.by_synonym.items()):
            parts = name.split()
            if len(parts) == 2:
                self.by_stem[(parts[0], stem(parts[1]))] |= codes
                self.by_epithet[stem(parts[1])] |= codes

        # Water temperatures as (min, preferred, max). The stocks table's
        # recorded range and preferred value come first; otherwise the
        # preferred range FishBase estimates from AquaMaps (its mean as the
        # preferred value).
        self.families: dict[int, str] = {}
        self.temps: dict[int, tuple[float, float, float]] = {}
        if extra:
            fam = pq.read_table(folder / "families.parquet", columns=["FamCode", "Family"]).to_pylist()
            self.families = {r["FamCode"]: r["Family"] for r in fam}
            est = pq.read_table(folder / "estimate.parquet", columns=["SpecCode", "TempPrefMin", "TempPrefMean", "TempPrefMax"])
            for r in est.to_pylist():
                t = (r["TempPrefMin"], r["TempPrefMean"], r["TempPrefMax"])
                if None not in t:
                    self.temps[r["SpecCode"]] = t
            stocks = pq.read_table(folder / "stocks.parquet", columns=["SpecCode", "TempMin", "TempPreferred", "TempMax"])
            for r in stocks.to_pylist():
                t = (r["TempMin"], r["TempPreferred"], r["TempMax"])
                if None not in t and t[0] <= t[1] <= t[2]:
                    self.temps[r["SpecCode"]] = t

    def match(self, scientific: str, common: str | None) -> tuple[int, str] | None:
        """The FishBase SpecCode for a name, and how it matched."""
        full = norm(scientific)
        binomial = " ".join(full.split()[:2])
        for key, how in ((full, "name"), (binomial, "species of subspecies")):
            if key in self.by_name:
                return self.by_name[key], how
            codes = self.by_synonym.get(key, set())
            if len(codes) == 1:
                return next(iter(codes)), "synonym"
        genus, _, epithet = binomial.partition(" ")
        codes = self.by_stem.get((genus, stem(epithet)), set())
        if len(codes) == 1:
            return next(iter(codes)), "spelling"
        if common:
            named = {c for c in self.by_epithet.get(stem(epithet), set())
                     if norm(self.species[c]["FBname"] or "") == norm(common)}
            if len(named) == 1:
                return next(iter(named)), "genus move"
        donor = SPLIT_FROM.get(" ".join(scientific.split()[:2]))
        if donor and norm(donor) in self.by_name:
            return self.by_name[norm(donor)], f"split from {donor}"
        return None

    def habitat(self, code: int) -> str | None:
        r = self.species[code]
        return habitat(r["Fresh"], r["Brack"], r["Saltwater"])


def angling_name(limit_name: str) -> str:
    """'Black Musselcracker (Poenskop)' and 'Geelbek / Cape Salmon' to the
    first name an angler uses."""
    first = limit_name.split("/")[0]
    return re.sub(r"\s*\(.*?\)", "", first).strip()


def counts(seed: list[dict]) -> str:
    c = Counter(e.get("habitat") for e in seed)
    return ", ".join(f"{k} {v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1]))


def set_habitats(seed: list[dict], fb: FishBase, everything: bool) -> dict[int, int]:
    """Set habitat on every eligible record; return each record's SpecCode."""
    codes: dict[int, int] = {}
    changed: list[str] = []
    unmatched: list[str] = []
    loose: list[str] = []
    for e in seed:
        hit = fb.match(e["scientificName"], e.get("commonName"))
        if not hit:
            unmatched.append(f'  {e["id"]:>5} {e["scientificName"]} ({e["commonName"]}), keeps {e.get("habitat")}')
            continue
        code, how = hit
        codes[e["id"]] = code
        r = fb.species[code]
        if how != "name":
            loose.append(f'  {e["id"]:>5} {e["scientificName"]} -> {r["Genus"]} {r["Species"]} ({how})')
        if e["id"] <= CURATED_MAX_ID and not everything:
            continue
        value = fb.habitat(code)
        if value and value != e.get("habitat"):
            changed.append(f'  {e["id"]:>5} {e["commonName"]}: {e.get("habitat")} to {value}')
            e["habitat"] = value
    print(f"Matched {len(codes)} of {len(seed)} species to FishBase.")
    print(f"Matched other than by exact name ({len(loose)}):")
    print("\n".join(loose))
    print(f"Not in FishBase ({len(unmatched)}):")
    print("\n".join(unmatched))
    print(f"Habitat changed ({len(changed)}):")
    print("\n".join(changed))
    return codes


def add_limit_species(seed: list[dict], limits: list[dict], fb: FishBase, codes: dict[int, int]) -> None:
    """Append the size-limit fish the seed lacks."""
    by_code = {code: sid for sid, code in codes.items()}
    names = {norm(e["scientificName"]) for e in seed}
    commons = {norm(e["commonName"]) for e in seed}
    next_id = max(int(e["id"]) for e in seed) + 1
    added, skipped = [], []
    for limit in limits:
        sci = limit["scientificName"]
        if norm(sci) in names:
            continue
        hit = fb.match(sci, None)
        if not hit:
            skipped.append(f"  {sci} ({limit['commonName']}): not in FishBase")
            continue
        code, how = hit
        if code in by_code:
            skipped.append(f"  {sci} ({limit['commonName']}): already in the seed as id {by_code[code]}")
            continue
        r = fb.species[code]
        family = fb.families.get(r["FamCode"])
        temps = fb.temps.get(code)
        if not family or not temps:
            skipped.append(f"  {sci} ({limit['commonName']}): FishBase has no "
                           + ("family" if not family else "water temperatures"))
            continue
        lo, preferred, hi = (round(float(t), 1) for t in temps)
        common = angling_name(limit["commonName"])
        if norm(common) in commons:
            common = (r["FBname"] or sci).title()
        seed.append({
            "id": next_id,
            "scientificName": sci,
            "commonName": common,
            "family": family,
            "habitat": fb.habitat(code),
            "minTempC": lo,
            "maxTempC": hi,
            "optimalTempC": preferred,
            "fishbaseId": code,
            "imageUrl": None,
        })
        added.append(f'  {next_id:>5} {common} ({sci}, FishBase {r["Genus"]} {r["Species"]} by {how}, {family}), '
                     f'{fb.habitat(code)}, {lo} to {hi} °C, preferred {preferred}')
        by_code[code] = next_id
        names.add(norm(sci))
        commons.add(norm(common))
        next_id += 1
    print(f"Added {len(added)} size-limit species:")
    print("\n".join(added))
    print(f"Not added ({len(skipped)}):")
    print("\n".join(skipped))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--fishbase", type=Path, required=True,
                    help="folder holding the FishBase species, synonyms, families, stocks and estimate parquet files")
    ap.add_argument("--seed", type=Path, default=SEED_JSON)
    ap.add_argument("--limits", type=Path, default=LIMITS_JSON)
    ap.add_argument("--all", action="store_true", help="also replace the curated records' habitat")
    ap.add_argument("--add-limit-species", action="store_true")
    ap.add_argument("--dry-run", action="store_true", help="print the changes, write nothing")
    args = ap.parse_args()

    seed = json.loads(args.seed.read_text(encoding="utf-8"))
    limits = json.loads(args.limits.read_text(encoding="utf-8"))
    fb = FishBase(args.fishbase, extra=args.add_limit_species)

    print(f"Before: {len(seed)} species; {counts(seed)}.")
    codes = set_habitats(seed, fb, args.all)
    if args.add_limit_species:
        add_limit_species(seed, limits, fb, codes)
    print(f"After: {len(seed)} species; {counts(seed)}.")

    ids = [int(e["id"]) for e in seed]
    if len(ids) != len(set(ids)) or len({norm(e["scientificName"]) for e in seed}) != len(seed):
        sys.exit("Duplicate id or scientific name; nothing written.")
    if args.dry_run:
        print("Dry run; nothing written.")
        return
    args.seed.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"Wrote {args.seed}")


if __name__ == "__main__":
    main()
