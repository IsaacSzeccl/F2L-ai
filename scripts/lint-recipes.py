#!/usr/bin/env python3
"""Freshness lint for the recipe library.

Warns about every recipe that nobody has followed on a real account yet, and every verified recipe whose check is
older than 21 days, because an interface may have moved on since. Exits 1 only with --strict, so it can run as a
warning now and as a gate once the demo recipes are verified (see docs/plans/KNOWLEDGE_BASE_PLAN.md, Phase 5).

    scripts/lint-recipes.py              # report
    scripts/lint-recipes.py --strict     # fail when anything needs checking
    scripts/lint-recipes.py --demo-only  # only the recipes the demo depends on
"""
import argparse
import datetime
import json
import pathlib
import sys

STALE_AFTER_DAYS = 21  # Recipe.staleAfterDays on Mac, Recipe.StaleAfterDays on Windows
ROOT = pathlib.Path(__file__).resolve().parent.parent
RECIPES = ROOT / "Windows/F2L.Windows/Assets/Knowledge/recipes.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--strict", action="store_true", help="exit 1 when any recipe needs checking")
    parser.add_argument("--demo-only", action="store_true", help="only recipes tagged for the demo flow")
    parser.add_argument("--today", default=None, help="the date to measure against, as yyyy-mm-dd")
    args = parser.parse_args()

    today = datetime.date.fromisoformat(args.today) if args.today else datetime.date.today()
    data = json.loads(RECIPES.read_text(encoding="utf-8"))
    recipes = data["recipes"]
    if args.demo_only:
        recipes = [r for r in recipes if "demo" in r.get("tags", [])]

    drafted, stale = [], []
    for recipe in recipes:
        if recipe.get("status") != "verified":
            drafted.append(recipe["id"])
            continue
        checked = datetime.date.fromisoformat(recipe["verifiedOn"])
        age = (today - checked).days
        if age > STALE_AFTER_DAYS:
            stale.append((recipe["id"], age))

    print(f"{len(recipes)} recipes, checked {data.get('checked', 'unknown')}, measured against {today}")
    if drafted:
        print(f"\nNot yet followed on a real account ({len(drafted)}) — section 4.5 of the plan:")
        for name in drafted:
            print(f"  · {name}")
    for name, age in stale:
        print(f"  ! {name} was checked {age} days ago (limit {STALE_AFTER_DAYS})")
    if not drafted and not stale:
        print("\nEvery recipe has been followed on a real account within the last "
              f"{STALE_AFTER_DAYS} days.")
        return 0
    return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
