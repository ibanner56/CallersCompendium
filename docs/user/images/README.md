# User-documentation images

This folder holds the images used by the guides in [`../`](../) — screenshots,
diagrams, and illustrations.

## Status: the guides are text-only today

The user guides are bundled into the app, and the in-app reader does not render
images — it shows the alt text as a caption instead. So an illustration only ever
reaches readers on GitHub, and no guide may depend on one to make sense. Write
every procedure so it stands on its own words; treat an image as an enhancement.

Where a guide does illustrate a screen today, it borrows an interim **wireframe
SVG** from [`../../design/wireframes/`](../../design/wireframes/). These are
monochrome, structure-only sketches — they show layout and content, not the final
look — so any guide that uses one says so in its caption and alt text (for
example, "Wireframe sketch of the Collection screen").

Real screenshots are tracked as follow-up work. When they land, they replace the
wireframes in place and the captions drop the "wireframe" wording.

## Conventions

The full rules live in the [style guide](../style-guide.md); the essentials:

- **Every image needs descriptive alt text.** Decorative images are marked as
  decorative (empty alt). See the alt-text policy in the style guide.
- **Naming:** `screen-topic.png`, lowercase, hyphen-separated
  (for example, `collection-search-panel.png`, `perform-mode-dark.png`).
- **Format:** PNG for screenshots, SVG for diagrams and wireframes.
- **Size:** keep files small (aim for well under 500 KB per screenshot); crop to
  the relevant area rather than shipping full-desktop captures.

This README keeps the directory tracked in version control until real images
land.
