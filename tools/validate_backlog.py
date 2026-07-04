#!/usr/bin/env python3
"""Integrity guard for _backlog.json (the machine backlog agents pick work from).

Catches the failure modes that silently break the AI-agent workflow:
  * file truncated / not valid JSON   (has happened during concurrent writes)
  * duplicate card ids
  * depends_on pointing at ids that don't exist
  * cards missing required fields (id / status)
  * unknown status values

Exits non-zero (fails CI) on any problem. Safe to run locally:
    python3 tools/validate_backlog.py
Does NOT touch the Godot project or the game build.
"""
import json
import sys
from pathlib import Path

BACKLOG = Path(__file__).resolve().parent.parent / "_backlog.json"
REQUIRED_FIELDS = ("id", "status")
ALLOWED_STATUS = {"backlog", "todo", "doing", "review", "done"}


def fail(msg: str) -> None:
    print(f"::error::{msg}")
    sys.exit(1)


def main() -> None:
    if not BACKLOG.exists():
        fail(f"{BACKLOG.name} not found at {BACKLOG}")

    try:
        cards = json.loads(BACKLOG.read_text(encoding="utf-8"))
    except json.JSONDecodeError as e:
        fail(f"{BACKLOG.name} is not valid JSON (truncated/corrupt?): {e}")

    if not isinstance(cards, list):
        fail(f"{BACKLOG.name} must be a JSON array of cards")

    ids = [c.get("id") for c in cards]

    for c in cards:
        for field in REQUIRED_FIELDS:
            if not c.get(field):
                fail(f"card missing '{field}': {c.get('id') or c}")
        status = c.get("status")
        if status not in ALLOWED_STATUS:
            fail(f"card {c.get('id')} has unknown status '{status}' "
                 f"(allowed: {sorted(ALLOWED_STATUS)})")

    dups = sorted({i for i in ids if ids.count(i) > 1})
    if dups:
        fail(f"duplicate card ids: {dups}")

    idset = set(ids)
    bad_deps = [(c.get("id"), dep)
                for c in cards
                for dep in c.get("depends_on", [])
                if dep not in idset]
    if bad_deps:
        fail(f"depends_on pointing to unknown ids: {bad_deps}")

    print(f"backlog OK: {len(cards)} cards, unique ids, all depends_on resolve")


if __name__ == "__main__":
    main()
