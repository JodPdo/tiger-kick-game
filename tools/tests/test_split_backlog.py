#!/usr/bin/env python3
"""Regression tests for tools/split_backlog.py.

Plain-stdlib unittest, same style as test_validate_backlog.py (this repo has no
Python test framework/deps installed; the project's other tests are GUT/.gd
under tests/). Run directly:

    python3 tools/tests/test_split_backlog.py

What these lock down:
  1. The real _backlog.json carries a UTF-8 BOM. Anything reading it must use
     "utf-8-sig" or json.loads() raises. This bit validate_backlog.py once
     already (see test_validate_backlog.py) — the index generator must not
     repeat it.
  2. `ready` implements the rule in CLAUDE.md: status == "todo" AND every id in
     depends_on is "done". A card blocked by an unfinished dependency must not
     be advertised as ready, or agents will start work out of order.
  3. --check must fail on a stale or missing index. That guard is the only
     thing stopping a hand-edited/forgotten index from silently disagreeing
     with the backlog, which would route agents to the wrong cards.
  4. A corrupt backlog must abort before an index is written, so a plausible
     but wrong index is never produced.
"""
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "split_backlog.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("split_backlog", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run(sb_module, argv, backlog_bytes, index_text=None):
    """Point the module at a temp repo and run main(argv).

    Returns (exit_code, stdout_text, index_text_after). exit_code is None when
    main() returned normally — the success paths never call sys.exit().
    """
    with tempfile.TemporaryDirectory() as tmp:
        backlog = Path(tmp) / "_backlog.json"
        index = Path(tmp) / "_backlog_index.json"
        backlog.write_bytes(backlog_bytes)
        if index_text is not None:
            index.write_text(index_text, encoding="utf-8")

        orig_backlog, orig_index = sb_module.BACKLOG, sb_module.INDEX
        sb_module.BACKLOG, sb_module.INDEX = backlog, index
        try:
            buf = io.StringIO()
            try:
                with redirect_stdout(buf):
                    sb_module.main(argv)
                exit_code = None
            except SystemExit as e:
                exit_code = e.code
            after = index.read_text(encoding="utf-8-sig") if index.exists() else None
            return exit_code, buf.getvalue(), after
        finally:
            sb_module.BACKLOG, sb_module.INDEX = orig_backlog, orig_index


CARDS = [
    {"id": "TK-A", "status": "done", "owner_agent": "tools-devops", "title": "base"},
    {"id": "TK-B", "status": "todo", "owner_agent": "gameplay-engineer",
     "title": "unblocked", "depends_on": ["TK-A"]},
    {"id": "TK-C", "status": "todo", "owner_agent": "gameplay-engineer",
     "title": "blocked", "depends_on": ["TK-B"],
     "notes": "a long prose field that should stay out of the index"},
]


def _payload(cards=None, bom=False):
    raw = json.dumps(cards if cards is not None else CARDS).encode("utf-8")
    return (b"\xef\xbb\xbf" + raw) if bom else raw


class BuildIndexTests(unittest.TestCase):
    def setUp(self):
        self.sb = _load_module()

    def test_ready_only_when_todo_and_deps_done(self):
        index = self.sb.build_index(CARDS)
        by_id = {c["id"]: c for c in index["cards"]}

        # depends on a done card -> takeable
        self.assertTrue(by_id["TK-B"]["ready"])
        # depends on a todo card -> must not be advertised as ready
        self.assertFalse(by_id["TK-C"]["ready"])
        self.assertEqual(by_id["TK-C"]["blocked_by"], ["TK-B"])
        # already finished -> not "ready" work
        self.assertFalse(by_id["TK-A"]["ready"])
        self.assertEqual(index["ready_count"], 1)

    def test_prose_fields_are_excluded_but_advertised(self):
        index = self.sb.build_index(CARDS)
        card_c = next(c for c in index["cards"] if c["id"] == "TK-C")
        # the whole point: bulky prose must not ride along in the index...
        self.assertNotIn("notes", card_c)
        # ...but an agent should still know it exists before fetching the card
        self.assertIn("notes", card_c["detail_fields"])

    def test_missing_dependency_target_is_treated_as_unmet(self):
        # validate_backlog.py rejects dangling depends_on, but build_index must
        # not optimistically call a card ready if it ever sees one.
        cards = [{"id": "TK-X", "status": "todo", "depends_on": ["TK-NOPE"]}]
        card = self.sb.build_index(cards)["cards"][0]
        self.assertFalse(card["ready"])
        self.assertEqual(card["blocked_by"], ["TK-NOPE"])


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.sb = _load_module()

    def test_bom_prefixed_backlog_is_read(self):
        exit_code, stdout, index = _run(self.sb, [], _payload(bom=True))
        self.assertIsNone(exit_code, f"expected success, got {exit_code!r}: {stdout!r}")
        self.assertIsNotNone(index)
        self.assertEqual(json.loads(index)["card_count"], 3)

    def test_check_passes_when_index_matches(self):
        _, _, fresh = _run(self.sb, [], _payload())
        exit_code, stdout, _ = _run(self.sb, ["--check"], _payload(), index_text=fresh)
        self.assertIsNone(exit_code, f"expected success, got {exit_code!r}: {stdout!r}")
        self.assertIn("in sync", stdout)

    def test_check_fails_when_index_is_stale(self):
        _, _, fresh = _run(self.sb, [], _payload())
        # backlog moves on; committed index does not
        moved = CARDS + [{"id": "TK-D", "status": "todo"}]
        exit_code, _stdout, _ = _run(
            self.sb, ["--check"], _payload(moved), index_text=fresh
        )
        self.assertEqual(exit_code, 1)

    def test_check_fails_when_index_missing(self):
        exit_code, _stdout, _ = _run(self.sb, ["--check"], _payload())
        self.assertEqual(exit_code, 1)

    def test_corrupt_backlog_writes_no_index(self):
        exit_code, _stdout, index = _run(self.sb, [], b"{ truncated")
        self.assertEqual(exit_code, 1)
        self.assertIsNone(index, "an index must never be written from a bad backlog")

    def test_card_prints_full_card_including_prose(self):
        exit_code, stdout, _ = _run(self.sb, ["--card", "TK-C"], _payload())
        self.assertIsNone(exit_code)
        self.assertEqual(json.loads(stdout)["notes"],
                         "a long prose field that should stay out of the index")

    def test_card_unknown_id_fails(self):
        exit_code, _stdout, _ = _run(self.sb, ["--card", "TK-NOPE"], _payload())
        self.assertEqual(exit_code, 1)

    def test_agent_lists_only_that_agents_cards(self):
        exit_code, stdout, _ = _run(
            self.sb, ["--agent", "gameplay-engineer"], _payload()
        )
        self.assertIsNone(exit_code)
        self.assertIn("TK-B", stdout)
        self.assertIn("TK-C", stdout)
        self.assertNotIn("TK-A", stdout)      # owned by tools-devops
        self.assertIn("2 cards, 1 ready", stdout)

    def test_agent_unknown_name_fails(self):
        exit_code, _stdout, _ = _run(self.sb, ["--agent", "nobody"], _payload())
        self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()
