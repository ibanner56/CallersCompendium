#!/usr/bin/env bash
# Build the macOS installer disk image (drag-to-Applications window).
#
# Usage: packaging/macos/build_dmg.sh <path/to/App.app> <output.dmg>
#
# Lays out the window with dmgbuild (packaging/macos/dmg_settings.py): branded
# background with an arrow and instructions, the app and an Applications
# shortcut at fixed positions, the app's icon as the volume icon. Then mounts
# the result read-only and checks that what a user will see is actually there,
# because dmgbuild does not fail when one of its copy or attribute steps does.
#
# DMGBUILD_PYTHON selects the interpreter that has dmgbuild installed (the
# release job installs the hash-pinned packaging/macos/requirements-dmg.txt
# into a virtualenv); it defaults to python3. Run from the repository root.
# Signing and notarizing the result are the caller's job.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <App.app> <output.dmg>" >&2
  exit 2
fi
app_path="${1%/}"
dmg="$2"
python="${DMGBUILD_PYTHON:-python3}"
here="$(cd "$(dirname "$0")" && pwd)"
volume_name="Caller's Compendium"
app_name="$(basename "$app_path")"

if [ ! -d "$app_path" ]; then
  echo "error: app bundle not found: $app_path" >&2
  exit 1
fi
if [ ! -f "$app_path/Contents/Resources/AppIcon.icns" ]; then
  echo "error: $app_path has no Contents/Resources/AppIcon.icns for the volume icon" >&2
  exit 1
fi

mkdir -p "$(dirname "$dmg")"
rm -f "$dmg"
"$python" -m dmgbuild \
  -s "$here/dmg_settings.py" \
  -D app="$app_path" \
  -D background="$here/dmg-background.png" \
  "$volume_name" "$dmg"

# ---- verify the image a user will open -------------------------------------
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/cc-dmg-verify.XXXXXX")"
cleanup() {
  hdiutil detach "$mount_point" -quiet 2>/dev/null \
    || hdiutil detach "$mount_point" -force -quiet 2>/dev/null || true
  rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach "$dmg" -readonly -nobrowse -noautoopen -mountpoint "$mount_point" -quiet

fail() { echo "error: $dmg: $*" >&2; exit 1; }
[ -d "$mount_point/$app_name" ] || fail "missing $app_name"
# ditto must have copied the bundle exactly (signature, symlinks and all).
diff -rq "$app_path" "$mount_point/$app_name" >/dev/null \
  || fail "$app_name differs from $app_path"
[ "$(readlink "$mount_point/Applications")" = "/Applications" ] \
  || fail "Applications shortcut missing or not pointing at /Applications"
[ -f "$mount_point/.DS_Store" ] || fail "missing window layout (.DS_Store)"
[ -f "$mount_point/.background.tiff" ] \
  || fail "missing HiDPI background (.background.tiff; is the @2x PNG present?)"
[ -f "$mount_point/.VolumeIcon.icns" ] || fail "missing volume icon"

echo "Built $dmg"
