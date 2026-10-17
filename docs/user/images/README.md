# User-documentation images

This folder holds the images used by the guides in [`../`](../) — screenshots,
diagrams, and illustrations.

## Status: screenshots are enhancements

The user guides are bundled into the app along with every file in this folder
except this README (`tools/ci/sync_user_docs.py` mirrors them), so the in-app
reader, GitHub and the hosted Pages guide all show the screenshots. Screen-reader
and low-vision readers rely on the alt text, and the in-app reader shows it as a
caption if an image fails to load. No guide may depend on an image to make sense.
Write every procedure so it stands on its own words; treat an image as an
enhancement.

Every image file here ships inside the app, so keep each one small.

The guides use real PNG screenshots for the Collection, dance detail, Programs
builder and matrix, Perform mode, Settings/Dialect, import review, and dance
editor figure entry. They show the finished app's layout and content, but remain
optional context rather than required instructions.

The design documentation may still use interim **wireframe SVGs** from
[`../../design/wireframes/`](../../design/wireframes/); those are monochrome,
structure-only sketches and are not screenshots.

## Conventions

The full rules live in the [style guide](../style-guide.md); the essentials:

- **Every image needs descriptive alt text.** Decorative images are marked as
  decorative (empty alt). See the alt-text policy in the style guide.
- **Naming:** `screen-topic.png`, lowercase, hyphen-separated
  (for example, `collection-search-panel.png`, `perform-mode-dark.png`).
- **Format:** PNG for screenshots, SVG for diagrams and wireframes.
- **Size:** keep files small (aim for well under 500 KB per screenshot); crop to
  the relevant area rather than shipping full-desktop captures.
