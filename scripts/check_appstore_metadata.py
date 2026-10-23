# /// script
# requires-python = ">=3.11"
# ///
"""Check App Store Connect metadata against Apple's character limits.

    uv run scripts/check_appstore_metadata.py [ios/AppStore/metadata]

Exits non-zero when any file is over its limit, a URL is malformed, or the
keywords contain spaces around commas.
"""

from __future__ import annotations

import sys
from pathlib import Path

LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "keywords.txt": 100,
    "release_notes.txt": 4000,
    "support_url.txt": 255,
    "privacy_url.txt": 255,
}


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "ios/AppStore/metadata")
    locales = [p for p in sorted(root.iterdir()) if p.is_dir()]
    if not locales:
        print(f"No locales in {root}", file=sys.stderr)
        return 1

    failed = False
    for locale in locales:
        for name, limit in LIMITS.items():
            path = locale / name
            if not path.exists():
                print(f"{locale.name}/{name}: missing")
                failed = True
                continue
            text = path.read_text(encoding="utf-8").strip()
            count = len(text)
            problems = []
            if count == 0:
                problems.append("empty")
            if count > limit:
                problems.append(f"over by {count - limit}")
            if name == "keywords.txt" and (", " in text or " ," in text):
                problems.append("space next to a comma")
            if name.endswith("_url.txt") and not text.startswith("https://"):
                problems.append("not an https URL")
            status = "; ".join(problems) if problems else "ok"
            print(f"{locale.name}/{name}: {count}/{limit} {status}")
            failed = failed or bool(problems)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
