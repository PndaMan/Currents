# /// script
# requires-python = ">=3.11"
# dependencies = ["cairosvg>=2.7", "pillow>=10.4"]
# ///
"""Write the Game Center achievements and render every Game Center image.

The badges in ios/Currents/Features/Catch/FishingLogStreak.swift are the
source: each visible badge becomes an achievement folder under
ios/AppStore/game-center/achievements/<id>/ holding achievement.json (id,
points, name and the two descriptions) and image.png. The secret Bass Daddy
and Patron badges stay in the app and get no achievement.

Leaderboard and challenge folders are written by hand; this script only
renders their image.png from the icon and colour named in their json.

Images are rarity-coloured medallions in the style of the app's BadgeMedal,
on the app's black background, with Phosphor icons (MIT licence, see
docs/CONTENT_RIGHTS.md) standing in for the SF Symbols, which Apple does not
license outside its platforms.

    uv run scripts/render_achievement_art.py
"""

from __future__ import annotations

import io
import json
import re
import sys
import urllib.request
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SWIFT = ROOT / "ios/Currents/Features/Catch/FishingLogStreak.swift"
OUT = ROOT / "ios/AppStore/game-center"
CACHE = Path.home() / ".cache" / "currents-phosphor"
PHOSPHOR = "https://cdn.jsdelivr.net/npm/@phosphor-icons/core@2.1.1/assets/fill/{name}-fill.svg"

# Apple's sizes: achievements and leaderboards 1024x1024 (or 512x512),
# challenges 1920x1080. Opaque RGB, no transparency.
SQUARE = 1024
WIDE = (1920, 1080)
BACKGROUND = "#000000"

# BadgeRarity.color on the dark theme.
RARITY_COLOR = {
    "common": "#929298",
    "uncommon": "#30D158",
    "rare": "#64D2FF",
    "epic": "#BF5AF2",
    "legendary": "#FFD60A",
    "mythic": "#FF375F",
}
# Scaled by rarity; the total must stay at or under Apple's 1000 (970 now).
RARITY_POINTS = {"common": 5, "uncommon": 10, "rare": 15, "epic": 20, "legendary": 30, "mythic": 50}
MAX_TOTAL_POINTS = 1000

# SF Symbol -> the Phosphor icon with the same meaning.
ICONS = {
    "fish.fill": "fish",
    "camera.fill": "camera",
    "mappin.circle.fill": "map-pin",
    "arrow.uturn.backward": "arrow-u-up-left",
    "arrow.uturn.backward.circle.fill": "arrow-u-up-left",
    "scalemass": "scales",
    "tent.fill": "tent",
    "trophy.fill": "trophy",
    "star.leadinghalf.filled": "star-half",
    "leaf.fill": "leaf",
    "globe.americas.fill": "globe-hemisphere-west",
    "flame.fill": "flame",
    "calendar": "calendar",
    "calendar.badge.checkmark": "calendar-check",
    "star.fill": "star",
    "star.circle.fill": "star",
    "moon.fill": "moon",
    "sun.max.fill": "sun",
    "ruler": "ruler",
    "map.fill": "map-trifold",
    "gauge.medium": "gauge",
    "crown.fill": "crown",
    "rosette": "seal-check",
    "medal.fill": "medal",
}

HIDDEN_METRICS = {"secret", "supporter"}

SPEC_RE = re.compile(
    r'\.init\(title: "([^"]+)", icon: "([^"]+)", rarity: \.(\w+), metric: \.(\w+), target: ([\d.]+)\)')
EXPLANATION_RE = re.compile(r'case "([^"]+)":\s+return "([^"\\]+)"')


def achievement_id(title: str) -> str:
    """Matches GameCenterProgress.achievementID(for:) in the app."""
    return "badge." + "_".join(re.findall(r"[a-z0-9]+", title.lower()))


def after_earned(metric: str, target: float) -> str:
    """What the angler did, in the past tense, for the earned description."""
    n = int(target)
    lb = round(target * 2.20462, 1)
    lb_text = f"{lb:g}"
    inches = round(target / 2.54)
    plural = "" if n == 1 else "es"
    texts = {
        "catches": "Logged your first catch." if n == 1 else f"Logged {n:,} catches.",
        "photos": f"Added photos to {n} catches.",
        "spots": "Logged a catch at a saved spot." if n == 1 else f"Logged catches at {n} different saved spots.",
        "released": f"Released {n} catch{plural}.",
        "weightKg": f"Landed a fish of {n} kg ({lb_text} lb) or more.",
        "lengthCm": f"Landed a fish of {n} cm ({inches} in) or longer.",
        "bestDay": f"Logged {n} catches in a single day.",
        "weekend": "Logged a catch on a weekend.",
        "species": f"Caught {n} different species.",
        "streakWeeks": f"Fished {n} weeks in a row.",
        "months": f"Logged catches in {n} different months of the year.",
        "night": "Logged a catch late at night.",
        "dawn": "Logged a catch at first light.",
        "biteScore": f"Landed a catch at a bite score of {n} or higher.",
    }
    return texts[metric]


def read_badges() -> list[dict]:
    source = SWIFT.read_text(encoding="utf-8")
    explanations = dict(EXPLANATION_RE.findall(source))
    badges = []
    for title, icon, rarity, metric, target in SPEC_RE.findall(source):
        if metric in HIDDEN_METRICS:
            continue
        if title not in explanations:
            sys.exit(f"{title}: no explanation in {SWIFT.name}")
        if icon not in ICONS:
            sys.exit(f"{title}: no Phosphor icon for SF Symbol {icon}; add it to ICONS")
        badges.append({"title": title, "icon": icon, "rarity": rarity, "metric": metric,
                       "target": float(target), "explanation": explanations[title]})
    if not badges:
        sys.exit(f"no badges found in {SWIFT}")
    return badges


def phosphor(name: str) -> str:
    """The inner markup of a Phosphor fill icon (256x256 viewBox), cached."""
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / f"{name}-fill.svg"
    if not path.exists():
        with urllib.request.urlopen(PHOSPHOR.format(name=name), timeout=30) as resp:
            path.write_bytes(resp.read())
    svg = path.read_text(encoding="utf-8")
    inner = re.search(r"<svg[^>]*>(.*)</svg>", svg, re.S)
    if not inner:
        sys.exit(f"unexpected Phosphor file {path}")
    return inner.group(1)


def medallion(cx: float, cy: float, size: float, color: str, icon: str) -> str:
    """BadgeMedal's earned face: a faint fill, a rim and a fine inner ring,
    with the symbol at 40 percent of the medal in the rarity colour."""
    r = size / 2
    rim = size * 0.05
    inner_r = r - size * 0.12
    glyph = size * 0.42
    scale = glyph / 256
    return f"""
  <circle cx="{cx}" cy="{cy}" r="{r - rim / 2}" fill="{color}" fill-opacity="0.24"
          stroke="{color}" stroke-width="{rim}"/>
  <circle cx="{cx}" cy="{cy}" r="{inner_r}" fill="none" stroke="{color}" stroke-opacity="0.4"
          stroke-width="{size * 0.008}"/>
  <g transform="translate({cx - glyph / 2} {cy - glyph / 2}) scale({scale})" fill="{color}">
    {phosphor(icon)}
  </g>"""


def render(path: Path, width: int, height: int, color: str, icon: str, medal_fraction: float) -> None:
    size = min(width, height) * medal_fraction
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
  <rect width="{width}" height="{height}" fill="{BACKGROUND}"/>{medallion(width / 2, height / 2, size, color, icon)}
</svg>"""
    png = cairosvg.svg2png(bytestring=svg.encode(), output_width=width, output_height=height)
    image = Image.open(io.BytesIO(png)).convert("RGB")
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)


def write_achievements() -> None:
    badges = read_badges()
    total = sum(RARITY_POINTS[b["rarity"]] for b in badges)
    if total > MAX_TOTAL_POINTS:
        sys.exit(f"achievement points total {total}; Apple allows {MAX_TOTAL_POINTS}")
    folder = OUT / "achievements"
    wanted = set()
    for badge in badges:
        ident = achievement_id(badge["title"])
        wanted.add(ident)
        spec = {
            "reference_name": badge["title"],
            "vendor_identifier": ident,
            "points": RARITY_POINTS[badge["rarity"]],
            "show_before_earned": True,
            "repeatable": False,
            "rarity": badge["rarity"],
            "name": badge["title"],
            "before_earned_description": badge["explanation"],
            "after_earned_description": after_earned(badge["metric"], badge["target"]),
        }
        (folder / ident).mkdir(parents=True, exist_ok=True)
        (folder / ident / "achievement.json").write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                                                         encoding="utf-8")
        render(folder / ident / "image.png", SQUARE, SQUARE, RARITY_COLOR[badge["rarity"]],
               ICONS[badge["icon"]], 0.86)
    stale = sorted(p.name for p in folder.iterdir() if p.is_dir() and p.name not in wanted)
    for name in stale:
        print(f"warning: achievements/{name} no longer matches a badge; remove it by hand")
    print(f"{len(badges)} achievements, {total} points")


def render_others() -> None:
    for kind, filename, size in (("leaderboards", "leaderboard.json", (SQUARE, SQUARE)),
                                 ("challenges", "challenge.json", WIDE)):
        for spec_path in sorted((OUT / kind).glob(f"*/{filename}")):
            spec = json.loads(spec_path.read_text(encoding="utf-8"))
            art = spec["art"]
            render(spec_path.parent / "image.png", *size, art["color"], art["icon"],
                   0.86 if size[0] == size[1] else 0.7)
            print(f"{kind}/{spec_path.parent.name}/image.png")


def main() -> int:
    write_achievements()
    render_others()
    return 0


if __name__ == "__main__":
    sys.exit(main())
