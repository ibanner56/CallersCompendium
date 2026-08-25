#!/usr/bin/env python3
"""Regression tests for the in-app user-documentation sync checker."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("sync_user_docs.py")
SPEC = importlib.util.spec_from_file_location("sync_user_docs", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
sync_user_docs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync_user_docs)


class RelativeFilesTest(unittest.TestCase):
    def test_ignores_finder_metadata_but_keeps_real_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "user").mkdir()
            (root / "user" / "settings.md").write_text(
                "# Settings\n", encoding="utf-8"
            )
            (root / "user" / ".DS_Store").write_bytes(b"finder metadata")

            self.assertEqual(sync_user_docs._relative_files(root), {"user/settings.md"})


if __name__ == "__main__":
    unittest.main()
