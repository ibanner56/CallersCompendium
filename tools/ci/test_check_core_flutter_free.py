#!/usr/bin/env python3
"""Offline tests for the compendium_core Flutter-free guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from check_core_flutter_free import (  # noqa: E402
    comment_free,
    reachable_packages,
    source_failures,
)


def test_dependency_closure_reaches_transitive_flutter() -> None:
    graph = {
        "packages": [
            {"name": "compendium_core", "dependencies": ["middle"]},
            {"name": "middle", "dependencies": ["flutter"]},
            {"name": "flutter", "dependencies": []},
        ],
    }
    assert reachable_packages(graph) == {"middle", "flutter"}


def test_comments_do_not_become_directives() -> None:
    source = (
        "// import 'package:flutter/widgets.dart';\n"
        "/* export 'package:flutter/services.dart'; */\n"
        "import 'package:collection/collection.dart';\n"
    )
    assert "package:flutter" not in comment_free(source)


def test_actual_directive_fails_after_comment_stripping() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        core = Path(temporary)
        library = core / "lib"
        library.mkdir()
        (library / "core.dart").write_text(
            "// import 'package:flutter/widgets.dart';\n"
            "export 'package:flutter/widgets.dart';\n",
            encoding="utf-8",
        )
        failures, scanned = source_failures(core)
    assert scanned == 1
    assert len(failures) == 1
    assert "package:flutter" in failures[0]


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_")]
    for test in tests:
        test()
    print(f"OK: {len(tests)} core-flutter-free tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
