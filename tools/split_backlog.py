#!/usr/bin/env python3
"""Generate a slim work-picking index from _backlog.json.

WHY THIS EXISTS
---------------
`CLAUDE.md` tells every agent to "Pick work from `_backlog.json`". That file is
~331,000 characters (~83,000 tokens), but the fields actually needed to *choose*
a card (id / owner_agent / status / depends_on / title) are only ~5% of it. The
other ~95% is accumulated prose — `notes`, `note`, `handoff`, `parked`,
`qa_verdict`, `human_test_result`, and ~30 other free-text keys that agents
invented over time — plus the full history of 48 already-`done` cards.

A single card moving through the mandatory `owner -> code-reviewer ->
qa-engineer` chain therefore costs three full reads of the whole backlog just to
answer "which card is mine and is it unblocked?".

This script emits `_backlog_index.json`: the same 82 cards with only the
decision fields, plus a computed `ready` flag. Agents read the index to pick
work, then pull the one card they need with `--card`.

DESIGN RULE: `_backlog.json` stays the single source of truth. The index is a
*derived artifact* — never hand-edit it. `--check` fails CI when it drifts.

USAGE
    python3 tools/split_backlog.py                 # regenerate the index
    python3 tools/split_backlog.py --check         # CI: fail if index is stale
    python3 tools/split_backlog.py --card TK-P2-05 # full JSON for one card
    python3 tools/split_backlog.py --agent qa-engineer   # that agent's queue
    python3 tools/split_backlog.py --stats         # size/token breakdown

Stdlib only (this repo installs no Python deps). Reuses tools/validate_backlog.py
so a corrupt backlog can never produce a plausible-looking index. Does NOT touch
the Godot project or the game build.
"""
import argparse
import importlib.util
import io
import json
import sys
from contextlib import redirect_stdout
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BACKLOG = REPO_ROOT / "_backlog.json"
INDEX = REPO_ROOT / "_backlog_index.json"
VALIDATOR = Path(__file__).resolve().parent / "validate_backlog.py"

# Fields an agent needs to decide "is this card mine, and can I start it?".
# Everything else is detail, fetched per-card via --card.
INDEX_FIELDS = (
    "id",
    "phase",
    "milestone",
    "title",
    "type",
    "priority",
    "owner_agent",
    "status",
    "depends_on",
    "labels",
)

# Rough chars-per-token used only for the human-readable --stats output.
CHARS_PER_TOKEN = 4


def fail(msg: str) -> None:
    """Match validate_backlog.py: GitHub-Actions annotation + non-zero exit."""
    print(f"::error::{msg}")
    sys.exit(1)


def load_validator():
    """Import tools/validate_backlog.py by path (works from any cwd)."""
    spec = importlib.util.spec_from_file_location("validate_backlog", VALIDATOR)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_validator(backlog_path: Path) -> None:
    """Run the existing integrity guard; abort if the backlog is unsound.

    validate_backlog.main() exits non-zero and prints its own ::error:: line on
    failure, so we let that propagate rather than reformatting the message.
    Its success chatter is swallowed to keep this script's output clean.
    """
    if not VALIDATOR.exists():
        fail(f"validator not found at {VALIDATOR}")

    vb = load_validator()
    original = vb.BACKLOG
    vb.BACKLOG = backlog_path
    try:
        with redirect_stdout(io.StringIO()):
            vb.main()
    except SystemExit as e:
        if e.code:
            sys.exit(e.code)
    finally:
        vb.BACKLOG = original


def read_cards(path: Path) -> list:
    """Read the backlog. utf-8-sig because the real file carries a UTF-8 BOM."""
    if not path.exists():
        fail(f"{path.name} not found at {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError as e:
        fail(f"{path.name} is not valid JSON: {e}")


def build_index(cards: list) -> dict:
    """Project cards down to the decision fields and compute readiness.

    `ready` encodes the rule from CLAUDE.md: a card is takeable when its status
    is "todo" and every id in depends_on is already "done". Computing it here
    means an agent does not have to cross-reference dependency cards itself.

    `detail_fields` lists which prose keys exist on the full card, so an agent
    can tell at a glance whether opening the full card is worth it.
    """
    status_by_id = {c.get("id"): c.get("status") for c in cards}

    entries = []
    for card in cards:
        entry = {f: card[f] for f in INDEX_FIELDS if f in card}

        deps = card.get("depends_on") or []
        unmet = [d for d in deps if status_by_id.get(d) != "done"]

        entry["ready"] = card.get("status") == "todo" and not unmet
        if unmet:
            entry["blocked_by"] = unmet

        detail = sorted(k for k in card if k not in INDEX_FIELDS)
        if detail:
            entry["detail_fields"] = detail

        entries.append(entry)

    return {
        "_comment": (
            "GENERATED FILE - do not edit by hand. Source of truth is "
            "_backlog.json. Regenerate with: python3 tools/split_backlog.py"
        ),
        "card_count": len(entries),
        "ready_count": sum(1 for e in entries if e["ready"]),
        "cards": entries,
    }


def serialize(index: dict) -> str:
    return json.dumps(index, ensure_ascii=False, indent=2) + "\n"


def cmd_write(cards: list) -> None:
    index = build_index(cards)
    INDEX.write_text(serialize(index), encoding="utf-8")
    full = len(BACKLOG.read_text(encoding="utf-8-sig"))
    slim = len(serialize(index))
    print(
        f"wrote {INDEX.name}: {index['card_count']} cards "
        f"({index['ready_count']} ready), "
        f"{slim:,d} chars vs {full:,d} in {BACKLOG.name} "
        f"({100 * slim / full:.1f}%)"
    )


def cmd_check(cards: list) -> None:
    """CI guard: the committed index must match what the backlog would produce."""
    if not INDEX.exists():
        fail(
            f"{INDEX.name} is missing. Run: python3 tools/split_backlog.py"
        )

    expected = serialize(build_index(cards))
    actual = INDEX.read_text(encoding="utf-8-sig")
    if expected != actual:
        fail(
            f"{INDEX.name} is stale (does not match {BACKLOG.name}). "
            f"Regenerate with: python3 tools/split_backlog.py"
        )
    print(f"{INDEX.name} is in sync with {BACKLOG.name} ({len(cards)} cards)")


def cmd_card(cards: list, card_id: str) -> None:
    """Print one full card. This is the cheap replacement for reading the
    whole backlog when an agent already knows which card it is working on."""
    for card in cards:
        if card.get("id") == card_id:
            print(json.dumps(card, ensure_ascii=False, indent=2))
            return
    fail(f"no card with id {card_id!r}")


def cmd_agent(cards: list, agent: str) -> None:
    """Print one agent's queue, ready cards first."""
    index = build_index(cards)
    mine = [c for c in index["cards"] if c.get("owner_agent") == agent]
    if not mine:
        owners = sorted({c.get("owner_agent") for c in index["cards"] if c.get("owner_agent")})
        fail(f"no cards owned by {agent!r}. Known owners: {owners}")

    ready = [c for c in mine if c["ready"]]
    print(f"{agent}: {len(mine)} cards, {len(ready)} ready to start\n")
    for card in sorted(mine, key=lambda c: (not c["ready"], c.get("id", ""))):
        mark = "READY" if card["ready"] else card.get("status", "?")
        line = f"  [{mark:>20s}] {card.get('id')}  {card.get('title', '')}"
        if card.get("blocked_by"):
            line += f"   <- waiting on {', '.join(card['blocked_by'])}"
        print(line)


def cmd_stats(cards: list) -> None:
    """Show where the bytes go, so the cost of prose sprawl stays visible."""
    full_text = BACKLOG.read_text(encoding="utf-8-sig")
    slim_text = serialize(build_index(cards))

    print(f"{BACKLOG.name:22s} {len(full_text):>9,d} chars  "
          f"~{len(full_text) // CHARS_PER_TOKEN:>7,d} tokens")
    print(f"{INDEX.name:22s} {len(slim_text):>9,d} chars  "
          f"~{len(slim_text) // CHARS_PER_TOKEN:>7,d} tokens")
    saved = len(full_text) - len(slim_text)
    print(f"{'saved per read':22s} {saved:>9,d} chars  "
          f"~{saved // CHARS_PER_TOKEN:>7,d} tokens  "
          f"({100 * saved / len(full_text):.1f}%)")

    by_field = {}
    for card in cards:
        for key, value in card.items():
            by_field[key] = by_field.get(key, 0) + len(
                json.dumps(value, ensure_ascii=False)
            )
    grand = sum(by_field.values()) or 1

    print("\nlargest fields in _backlog.json (prose sprawl shows up here):")
    for key, size in sorted(by_field.items(), key=lambda kv: -kv[1])[:12]:
        kept = "index" if key in INDEX_FIELDS else "detail"
        print(f"  {key:24s} {size:>8,d}  {100 * size / grand:5.1f}%  [{kept}]")


def main(argv=None) -> None:
    parser = argparse.ArgumentParser(
        description="Generate/verify the slim backlog index agents pick work from."
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--check", action="store_true",
                       help="fail if the committed index is stale (use in CI)")
    group.add_argument("--card", metavar="ID",
                       help="print the full JSON of one card")
    group.add_argument("--agent", metavar="NAME",
                       help="print that agent's queue, ready cards first")
    group.add_argument("--stats", action="store_true",
                       help="show size/token breakdown by field")
    args = parser.parse_args(argv)

    run_validator(BACKLOG)
    cards = read_cards(BACKLOG)

    if args.check:
        cmd_check(cards)
    elif args.card:
        cmd_card(cards, args.card)
    elif args.agent:
        cmd_agent(cards, args.agent)
    elif args.stats:
        cmd_stats(cards)
    else:
        cmd_write(cards)


if __name__ == "__main__":
    main()
