#!/usr/bin/env python3
"""Collect every player-visible string (the English text is the key) into data/i18n/en.json.

    python3 tools/i18n/extract_strings.py [--list]

Sources (exact, no guessing):
* data/levels.json (played levels): every level `name`, `tagline`, `royal_message` and every tier `name`, `intro`, `reveal` (PoC 4 cards);
* game/**/*.gd: every string literal passed straight to Loc.t("...").
Rule for code: show text only through Loc.t("..."), translate a FORMAT and fill it afterwards (Loc.t("CHAIN x%d") % n),
never glue translated pieces together.
New language: copy en.json to <code>.json (ISO 639-1, e.g. pl.json, de.json) and translate the VALUES only; keep the keys,
%d / %s / %.1f placeholders (same count and order) and \\n. Re-running rewrites en.json only and reports, per language,
untranslated keys, unused keys and placeholder mismatches (`--list` prints them).
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "i18n"
LOC_CALL = re.compile(r'Loc\.t\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
PLACEHOLDER = re.compile(r"%[-+ 0#]*\d*(?:\.\d+)?[dsfx%]")


def collect():
    found = set()
    levels = json.loads((ROOT / "data" / "levels.json").read_text(encoding="utf-8"))["levels"]
    for lv in levels:
        found.add(lv["name"])
        for k in ("tagline", "royal_message"):
            if lv.get(k):
                found.add(lv[k])
        for t in lv["tiers"]:
            found.add(t["name"])
            for k in ("intro", "reveal"):
                if t.get(k):
                    found.add(t[k])
    for p in sorted((ROOT / "game").rglob("*.gd")):
        for m in LOC_CALL.finditer(p.read_text(encoding="utf-8")):
            found.add(m.group(1).replace("\\n", "\n").replace('\\"', '"'))
    return found


def main():
    en = {k: k for k in sorted(collect())}
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "en.json").write_text(json.dumps(en, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"{len(en)} strings -> data/i18n/en.json")
    bad = 0
    for p in sorted(OUT.glob("*.json")):
        if p.stem == "en":
            continue
        have = json.loads(p.read_text(encoding="utf-8"))
        miss = [k for k in en if k not in have]
        extra = [k for k in have if k not in en]
        fmt = [k for k in en if k in have and PLACEHOLDER.findall(k) != PLACEHOLDER.findall(have[k])]
        bad += len(fmt)
        print(f"{p.name}: {len(miss)} untranslated, {len(extra)} unused keys, {len(fmt)} placeholder mismatches")
        if "--list" in sys.argv:
            for k in miss:
                print("  missing:", k)
            for k in fmt:
                print("  PLACEHOLDERS DIFFER:", k, "->", have[k])
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
