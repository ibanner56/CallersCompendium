# dmgbuild settings for the macOS installer disk image.
#
# Read by dmgbuild (https://dmgbuild.readthedocs.io), which executes this file
# with a `defines` mapping built from its `-D key=value` arguments. Invoked by
# packaging/macos/build_dmg.sh; see docs/dev/releasing.md#macos-installer-disk-image.
#
# dmgbuild writes the window layout (.DS_Store) and background directly, without
# scripting Finder, so the same layout comes out on a headless CI runner.
#
# The geometry constants below are also read (not executed) by
# tools/brand/generate_dmg_background.py, which places the arrow and the icon
# shadows from them: re-run it after moving an icon or resizing the window.

import os.path

# --- geometry (points) ------------------------------------------------------
WINDOW_SIZE = (660, 420)
ICON_SIZE = 112
APP_POS = (170, 220)
APPLICATIONS_POS = (490, 220)
# ----------------------------------------------------------------------------

app = defines["app"]  # noqa: F821  (supplied by dmgbuild)
background_png = defines["background"]  # noqa: F821
app_name = os.path.basename(app.rstrip("/"))

files = [app]
symlinks = {"Applications": "/Applications"}

# The volume shows the app's own icon in Finder's sidebar and on the desktop
# while mounted, instead of a generic external-disk icon.
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# Unchanged from the previous hdiutil recipe: zlib-compressed, HFS+, readable
# on every macOS the app supports.
format = "UDZO"
filesystem = "HFS+"

# The @2x sibling of this file is found by name and combined into one
# multi-resolution TIFF, so the art is sharp on Retina displays.
background = background_png

# A clean, fixed window: no toolbar, sidebar, path bar, status bar or tabs;
# icon view only, positioned near the top-left of the screen.
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
window_rect = ((200, 140), WINDOW_SIZE)

arrange_by = None
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
text_size = 13
icon_size = ICON_SIZE
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

# No hide_extensions: Finder already shows an app without ".app", and the flag
# would add Finder info to the signed bundle inside the image.
icon_locations = {
    app_name: APP_POS,
    "Applications": APPLICATIONS_POS,
}
