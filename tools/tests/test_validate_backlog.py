#!/usr/bin/env python3
"""Regression tests for tools/validate_backlog.py.

Plain-stdlib unittest (this repo has no Python test framework/deps installed;
the project's other tests are GUT/.gd under tests/). Run directly:

    python3 tools/tests/test_validate_backlog.py

Covers two real bugs found by code review on TK-P3-08 (fixed alongside these
tests):
  1. _backlog.json is saved with a UTF-8 BOM. The script used to read it with
     encoding="utf-8", which does not strip a BOM, so json.loads() raised a
     decode error on the real file. Fixed by reading with "utf-8-sig".
  2. ALLOWED_STATUS omitted "review-pending-human", a live status already
     used by real cards (e.g. TK-P2-14/TK-P2-15) for cards awaiting a human
     2-instance verification pass. Fixed by adding it to ALLOWED_STATUS.
"""
import importlib.util
import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve().parent.parent / "validate_backlog.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("validate_backlog", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _run_main_against(vb_module, fixture_bytes: bytes):
    """Point the module's BACKLOG at a temp fixture file and run main().

    Returns (exit_code, stdout_text). exit_code is None if main() returned
    normally (success path never calls sys.exit()).
    """
    with tempfile.TemporaryDirectory() as tmp:
        fixture_path = Path(tmp) / "_backlog.json"
        fixture_path.write_bytes(fixture_bytes)

        original_backlog = vb_module.BACKLOG
        vb_module.BACKLOG = fixture_path
        try:
            buf = io.StringIO()
            try:
                with redirect_stdout(buf):
                    vb_module.main()
                exit_code = None
            except SystemExit as e:
                exit_code = e.code
            return exit_code, buf.getvalue()
        finally:
            vb_module.BACKLOG = original_backlog


VALID_CARD = {"id": "TK-TEST-01", "status": "todo"}


class ValidateBacklogTests(unittest.TestCase):
    def setUp(self):
        self.vb = _load_module()

    def test_bom_prefixed_file_parses_ok(self):
        # This is the exact failure mode found in the real _backlog.json:
        # a UTF-8 BOM prefix that plain encoding="utf-8" does not strip.
        payload = json.dumps([VALID_CARD]).encode("utf-8")
        bom_prefixed = b"\xef\xbb\xbf" + payload
        exit_code, stdout = _run_main_against(self.vb, bom_prefixed)
        self.assertIsNone(exit_code, f"expected success, got exit={exit_code!r}, stdout={stdout!r}")
        self.assertIn("backlog OK", stdout)

    def test_review_pending_human_status_is_allowed(self):
        card = {"id": "TK-TEST-02", "status": "review-pending-human"}
        payload = json.dumps([card]).encode("utf-8")
        exit_code, stdout = _run_main_against(self.vb, payload)
        self.assertIsNone(exit_code, f"expected success, got exit={exit_code!r}, stdout={stdout!r}")
        self.assertIn("backlog OK", stdout)

    def test_normal_non_bom_file_with_normal_status_still_passes(self):
        cards = [
            {"id": "TK-TEST-03", "status": "backlog"},
            {"id": "TK-TEST-04", "status": "doing", "depends_on": ["TK-TEST-03"]},
            {"id": "TK-TEST-05", "status": "done"},
        ]
        payload = json.dumps(cards).encode("utf-8")
        exit_code, stdout = _run_main_against(self.vb, payload)
        self.assertIsNone(exit_code, f"expected success, got exit={exit_code!r}, stdout={stdout!r}")
        self.assertIn("backlog OK", stdout)

    def test_unknown_status_is_still_rejected(self):
        # Guard against over-loosening ALLOWED_STATUS while fixing bug #2.
        card = {"id": "TK-TEST-06", "status": "totally-not-a-real-status"}
        payload = json.dumps([card]).encode("utf-8")
        exit_code, _stdout = _run_main_against(self.vb, payload)
        self.assertEqual(exit_code, 1)


if __name__ == "__main__":
    unittest.main()
