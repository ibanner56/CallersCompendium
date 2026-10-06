"""Read the pdfium pin in ``packaging/pdfium/pdfium.cmake``.

The CMake file is the single source of truth: the Linux and Windows app builds
include it, and the release tooling (``gen_sbom.py``) and its guard
(``test_pdfium_pin.py``) read it here. Only plain ``set(NAME "value")`` lines
whose name starts with ``COMPENDIUM_PDFIUM_`` are read.

Pure stdlib, like the rest of ``tools/release``.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

_SET = re.compile(r'^set\((COMPENDIUM_PDFIUM_[A-Za-z0-9_]+)\s+"([^"]*)"\)\s*$', re.MULTILINE)
_HASH_KEY = re.compile(r"^COMPENDIUM_PDFIUM_(ARCHIVE|LIBRARY)_SHA256_(linux|win)_([a-z0-9]+)$")

# The LICENSE in the pinned archives is UTF-8 except for one Latin-1 byte in
# FreeType's notice ("copyright \xa9 <year>"). rootBundle.loadString decodes
# UTF-8 strictly, so the bundled copy re-encodes that one character; these are
# the two spellings, so the bundled copy can be mapped back and hashed.
_RELEASED_BYTES = b"copyright \xa9 <year>"
_BUNDLED_BYTES = b"copyright \xc2\xa9 <year>"


@dataclass(frozen=True)
class TargetHashes:
    archive_sha256: str
    library_sha256: str


@dataclass(frozen=True)
class PdfiumPin:
    printing_version: str
    version: str
    full_version: str
    license_sha256: str
    targets: dict[str, TargetHashes]


def read(path: Path) -> PdfiumPin:
    values = dict(_SET.findall(path.read_text(encoding="utf-8")))
    archive: dict[str, str] = {}
    library: dict[str, str] = {}
    for name, value in values.items():
        match = _HASH_KEY.match(name)
        if match is None:
            continue
        kind, os_name, arch = match.groups()
        (archive if kind == "ARCHIVE" else library)[f"{os_name}-{arch}"] = value
    targets = {
        target: TargetHashes(archive[target], library.get(target, ""))
        for target in sorted(archive)
    }

    def need(name: str) -> str:
        if name not in values:
            raise ValueError(f"{path}: no set({name} \"...\")")
        return values[name]

    return PdfiumPin(
        printing_version=need("COMPENDIUM_PDFIUM_PRINTING_VERSION"),
        version=need("COMPENDIUM_PDFIUM_VERSION"),
        full_version=need("COMPENDIUM_PDFIUM_FULL_VERSION"),
        license_sha256=need("COMPENDIUM_PDFIUM_LICENSE_SHA256"),
        targets=targets,
    )


def license_bytes_as_released(bundled: bytes) -> bytes:
    """Undo the one-character UTF-8 fix, giving the archive's LICENSE bytes."""
    if bundled.count(_BUNDLED_BYTES) != 1:
        raise ValueError("bundled pdfium LICENSE does not carry the expected FreeType line")
    return bundled.replace(_BUNDLED_BYTES, _RELEASED_BYTES)


def license_bytes_for_bundle(released: bytes) -> bytes:
    """The archive's LICENSE as the app bundles it (strict UTF-8)."""
    if released.count(_RELEASED_BYTES) != 1:
        raise ValueError("pdfium LICENSE does not carry the expected Latin-1 byte")
    return released.replace(_RELEASED_BYTES, _BUNDLED_BYTES)


def release_url(version: str, target: str) -> str:
    return (
        "https://github.com/bblanchon/pdfium-binaries/releases/download/"
        f"chromium/{version}/pdfium-{target}.tgz"
    )
