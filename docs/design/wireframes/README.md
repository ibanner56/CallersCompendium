# Wireframes

Low-fidelity, per-screen wireframes for Caller's Compendium, committed as SVG so they
diff in git and need no design-tool licence. They fulfil the **"Deliverables next"**
item in [`../ux.md`](../ux.md) — the low-fi wireframes due *before Phase 3 implementation
of each screen* — and use [`../ux.md`](../ux.md) as the contract for what each screen
must contain.

These are intentionally **monochrome and structure-only**. Color, real typography, final
spacing, and the design-system tokens live in the visual proposal
[`../ux-modernization.md`](../ux-modernization.md) (PR #42), not here. The wireframes lock
**layout, content, and interaction**; the modernization doc dresses them.

## Index

| # | Wireframe | Screen (ux.md) |
| --- | --- | --- |
| 1 | [`1-collection.svg`](1-collection.svg) | §1 Collection — browse + search |
| 2 | [`2-dance-detail.svg`](2-dance-detail.svg) | §2 Dance detail / card |
| 3 | [`3-dance-editor.svg`](3-dance-editor.svg) | §3 Dance editor (keyboard-first entry) |
| 4 | [`4-programs-builder.svg`](4-programs-builder.svg) | §4 Programs list & builder (List view) |
| 5 | [`5-program-matrix.svg`](5-program-matrix.svg) | §4 Programs — Matrix view tab |
| 6 | [`6-perform.svg`](6-perform.svg) | §5 Performance mode |
| 7 | [`7-settings.svg`](7-settings.svg) | §6 Settings |

## Reading the wireframes

Shared visual language, identical across every file:

| Element | Meaning |
| --- | --- |
| Solid gray bars | text / labels (length ≈ relative content length) |
| Light dashed boxes | placeholder / virtualized / scrollable region |
| Rounded rects | cards, controls, and containers |
| Circle + glyph | icon (always paired with a text bar → never color-only) |
| Terracotta number badge | annotation marker, explained in the "Notes" block on each screen |
| Terracotta outline | focus ring / keyboard-first affordance |

**Responsiveness** follows `ux.md`: desktop = nav **rail** + list/detail split; phone =
**bottom nav**, single pane. Each wireframe annotates its responsive behavior rather than
drawing every breakpoint. Performance mode (§5) is shown on its dark-stage default to convey
the ≥7:1 contrast requirement from [`../research/accessibility-baseline.md`](../research/accessibility-baseline.md).

The Matrix wireframe (#5) mirrors the **already-implemented** `program_matrix_table.dart`
(pinned row/column headers, mirrored scrolling, ★ first-figure / ✓ present, legend) — its
remaining work is theming only, per `ux-modernization.md` §5.

Each wireframe's implementation issue will still carry the detailed semantics and
keyboard/AT acceptance criteria; these files show the structure those criteria attach to.
