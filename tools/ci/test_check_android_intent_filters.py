#!/usr/bin/env python3
"""Unit tests for the Android BROWSABLE local-scheme intent-filter guard."""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_android_intent_filters as check  # noqa: E402

_MANIFEST = """\
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application>
    <activity android:name=".MainActivity" android:exported="true">
{filters}
    </activity>
  </application>
</manifest>
"""

_VIEW = '<action android:name="android.intent.action.VIEW"/>'
_SEND = '<action android:name="android.intent.action.SEND"/>'
_DEFAULT = '<category android:name="android.intent.category.DEFAULT"/>'
_BROWSABLE = '<category android:name="android.intent.category.BROWSABLE"/>'


def _manifest(*filters: str) -> str:
    return _MANIFEST.format(
        filters="\n".join(f"<intent-filter>{f}</intent-filter>" for f in filters)
    )


def _cases() -> None:
    json_data = (
        '<data android:scheme="content"/><data android:scheme="file"/>'
        '<data android:mimeType="application/json"/>'
    )
    # The shape that shipped before security-6: flagged.
    bad = _manifest(_VIEW + _DEFAULT + _BROWSABLE + json_data)
    assert len(check.offending_filters(bad)) == 1, check.offending_filters(bad)
    assert "content, file" in check.offending_filters(bad)[0]

    # The same filter without BROWSABLE: allowed ("Open with" still works).
    assert check.offending_filters(_manifest(_VIEW + _DEFAULT + json_data)) == []

    # Either local scheme alone is enough, in any case.
    for scheme in ("file", "content", "FILE"):
        one = _manifest(
            _VIEW + _BROWSABLE + f'<data android:scheme="{scheme}"/>'
        )
        assert len(check.offending_filters(one)) == 1, scheme

    # A typed filter with no scheme implicitly accepts content:/file:.
    typed = _manifest(
        _VIEW + _BROWSABLE + '<data android:mimeType="application/json"/>'
    )
    assert len(check.offending_filters(typed)) == 1

    # A browsable https deep link is not this guard's concern.
    https = _manifest(
        _VIEW + _DEFAULT + _BROWSABLE
        + '<data android:scheme="https" android:host="example.org"/>'
    )
    assert check.offending_filters(https) == []

    # BROWSABLE on a non-VIEW filter is not flagged.
    send = _manifest(_SEND + _BROWSABLE + json_data)
    assert check.offending_filters(send) == []

    # A second, offending filter is found next to a clean one, and on an
    # activity-alias as well as an activity.
    alias = _manifest(_VIEW + _DEFAULT + json_data).replace(
        "</application>",
        '<activity-alias android:name=".Alias"><intent-filter>'
        + _VIEW + _BROWSABLE + '<data android:scheme="file"/>'
        + "</intent-filter></activity-alias></application>",
    )
    found = check.offending_filters(alias)
    assert len(found) == 1 and found[0].startswith(".Alias"), found


def _mutated_repo_manifest() -> None:
    # Re-adding BROWSABLE to the real manifest's VIEW filter must fail check().
    rel = check.ANDROID_ROOT / "app/src/main/AndroidManifest.xml"
    text = (check.REPO_ROOT / rel).read_text(encoding="utf-8")
    needle = '<action android:name="android.intent.action.VIEW"/>'
    assert text.count(needle) == 1, "expected one VIEW filter in the manifest"
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / rel
        dest.parent.mkdir(parents=True)
        dest.write_text(
            text.replace(needle, needle + "\n" + _BROWSABLE), encoding="utf-8"
        )
        errors = check.check(Path(tmp))
        assert errors and str(rel) in errors[0], errors
        # A tree with no manifest at all is an error, not a silent pass.
        dest.unlink()
        assert check.check(Path(tmp)) != []


def _repo() -> None:
    # The real manifests: this is the assertion that fails while a VIEW filter
    # on file:/content: is BROWSABLE.
    errors = check.check()
    assert errors == [], "\n".join(errors)


def main() -> int:
    _cases()
    _mutated_repo_manifest()
    _repo()
    print("OK: all Android intent-filter guard tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
