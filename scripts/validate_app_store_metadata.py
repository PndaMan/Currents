#!/usr/bin/env python3
"""Check App Store metadata files against App Store Connect limits.

Run before pasting anything into App Store Connect:

    python3 scripts/validate_app_store_metadata.py docs/app-store/metadata

For every locale folder it checks the field limits Apple enforces, the
keyword-field rules that cost ranking when broken (spaces after commas,
duplicates, words already in the title or subtitle), and the house style
rules for public copy (no em or en dashes, straight quotes). Exit status is
non-zero when anything fails, so it can run in CI.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Apple's limits. Name, subtitle, promotional text and description are counted
# in characters; the keyword field is 100 bytes, which only differs from
# characters when non-ASCII letters are used.
CHAR_LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
}
KEYWORD_BYTE_LIMIT = 100

# Words Apple already indexes for every app, or that it tells developers not
# to spend keyword bytes on.
WASTED_KEYWORDS = {"app", "apps", "free", "ios", "iphone", "best", "new", "top"}

DASHES = {"—": "em dash", "–": "en dash"}
CURLY = {"“", "”", "‘", "’"}


def words(text: str) -> set[str]:
    return {w.lower() for w in re.findall(r"[a-z0-9']+", text, flags=re.I)}


def check_locale(folder: Path) -> list[str]:
    problems: list[str] = []

    def read(name: str) -> str | None:
        p = folder / name
        return p.read_text(encoding="utf-8").strip() if p.exists() else None

    for name, limit in CHAR_LIMITS.items():
        text = read(name)
        if text is None:
            continue
        if len(text) > limit:
            problems.append(f"{name}: {len(text)} characters, limit {limit}")
        for ch, label in DASHES.items():
            if ch in text:
                problems.append(f"{name}: contains an {label}; use a comma, colon or full stop instead")
        if name != "description.txt" and any(c in text for c in CURLY):
            problems.append(f"{name}: contains curly quotes; use straight quotes")

    keywords = read("keywords.txt")
    if keywords is not None:
        size = len(keywords.encode("utf-8"))
        if size > KEYWORD_BYTE_LIMIT:
            problems.append(f"keywords.txt: {size} bytes, limit {KEYWORD_BYTE_LIMIT}")
        if ", " in keywords or " ," in keywords:
            problems.append("keywords.txt: spaces around commas waste bytes; separate with commas only")
        items = [k.strip().lower() for k in keywords.split(",") if k.strip()]
        seen: set[str] = set()
        for k in items:
            if k in seen:
                problems.append(f"keywords.txt: '{k}' is repeated")
            seen.add(k)
            if k in WASTED_KEYWORDS:
                problems.append(f"keywords.txt: '{k}' is ignored or redundant in the keyword field")
        title_words = words(read("name.txt") or "") | words(read("subtitle.txt") or "")
        for k in items:
            if k in title_words:
                problems.append(f"keywords.txt: '{k}' already appears in the name or subtitle, so it is wasted here")

    return problems


def main(argv: list[str]) -> int:
    root = Path(argv[1]) if len(argv) > 1 else Path("docs/app-store/metadata")
    locales = sorted(p for p in root.iterdir() if p.is_dir())
    if not locales:
        print(f"no locale folders under {root}", file=sys.stderr)
        return 2

    failed = False
    for folder in locales:
        problems = check_locale(folder)
        status = "FAIL" if problems else "ok"
        failed |= bool(problems)
        print(f"{folder.name}: {status}")
        for p in problems:
            print(f"  - {p}")
        for name in ("name.txt", "subtitle.txt", "keywords.txt", "promotional_text.txt", "description.txt", "release_notes.txt"):
            p = folder / name
            if p.exists():
                text = p.read_text(encoding="utf-8").strip()
                unit = "bytes" if name == "keywords.txt" else "chars"
                n = len(text.encode("utf-8")) if name == "keywords.txt" else len(text)
                print(f"    {name:<22} {n:>5} {unit}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
