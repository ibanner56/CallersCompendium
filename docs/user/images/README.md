# User-documentation images

This folder holds the images used by the guides in [`../`](../) — screenshots,
diagrams, and illustrations.

## Status: placeholders for now

Real screenshots are captured **after packaging** (roadmap Phase 7.1), once the
app has installable builds on each platform and the visual theme is final. Until
then, guides may borrow the interim **wireframe SVGs** from
[`../../design/wireframes/`](../../design/wireframes/) as illustrations. These are
monochrome, structure-only sketches — they show layout and content, not the final
look — so any guide that uses one should say so in its caption and alt text (for
example, "Wireframe sketch of the Collection screen").

When real screenshots land, they replace the wireframes in place and the captions
drop the "wireframe" wording.

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
