# User-documentation images

This folder holds the images used by the guides in [`../`](../) — screenshots,
diagrams, and illustrations.

## Status: screenshots are enhancements

The user guides are bundled into the app along with every PNG in this folder
(`tools/ci/sync_user_docs.py` mirrors them; SVGs and this README are not
bundled), so the in-app reader, GitHub and the hosted Pages guide all show the
screenshots. Screen-reader
and low-vision readers rely on the alt text, and the in-app reader shows it as a
caption if an image fails to load. No guide may depend on an image to make sense.
Write every procedure so it stands on its own words; treat an image as an
enhancement.

Every PNG here ships inside the app, so keep each one small.

The guides use real PNG screenshots for the Collection, dance detail, Programs
builder and matrix, Perform mode, Settings/Dialect, import review, and dance
editor figure entry. They show the finished app's layout and content, but remain
optional context rather than required instructions.

### How the current screenshots were taken

So a retake matches the rest of the set:

- A release Linux build (`flutter build linux --release`), run under Xvfb with
  `GDK_SCALE=2` in a 1500×940 logical window (3000×1880 pixels), then scaled
  to 1800×1128. Perform mode uses its dark stage theme; every other screen uses
  the default light theme.
- An invented demo collection: made-up titles, authors (Alex Rivera, Jordan
  Ellis, Sam Okafor, Priya Shah) and venue (Grange Hall, Millbrook), every
  dance 64 beats with every figure recognized, plus the app's own sample
  dance. One performed program, "Friday Contra Dance", holds eight of them
  with a break after the fourth. Never use a real person's collection.
- The import review is the same collection opened from a `.ccshare` file it
  was exported to, so every dance is a possible match.
- Each PNG is reduced to a 256-color palette (Pillow's fast-octree
  quantizer, which keeps accent colors such as the mixer stripe accurate).

The design documentation may still use interim **wireframe SVGs** from
[`../../design/wireframes/`](../../design/wireframes/); those are monochrome,
structure-only sketches and are not screenshots.

## Conventions

The full rules live in the [style guide](../style-guide.md); the essentials:

- **Every image needs descriptive alt text.** Decorative images are marked as
  decorative (empty alt). See the alt-text policy in the style guide.
- **Naming:** `screen-topic.png`, lowercase, hyphen-separated
  (for example, `collection-search-panel.png`, `perform-mode-dark.png`).
- **Format:** PNG for screenshots, SVG for diagrams and wireframes. Only PNGs
  are bundled into the app (the in-app reader cannot decode SVG), so a guide that
  embeds an SVG shows its alt text as a caption there; keep such a diagram's
  meaning in the surrounding words.
- **Size:** keep files small (aim for well under 500 KB per screenshot); crop to
  the relevant area rather than shipping full-desktop captures.
