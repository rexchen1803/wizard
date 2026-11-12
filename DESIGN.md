# Wizard visual system

The current direction is pinned by Rex: GTA VI / Rockstar / Miami across the native App and the complete GitHub presentation. This replaces the preceding neutral repository artwork while retaining the functional model.

## Shared tokens
| Token | Value | Role |
| --- | --- | --- |
| Midnight | #0C0D1B | Main ground and readable overlay |
| Plum | #21152D | Panels and elevated surfaces |
| Cream | #FFF9CB | Primary display text |
| Sunset pink | #F7A6BE | Primary action and selected state |
| Orchid | #D65A98 | Secondary gradient and emphasis |
| Peach | #F8B38E | Warm gradient endpoint |

Artwork remains naturally colored. Gradients are framing and selected controls, not a blanket recolor of every photograph. Secondary text needs sufficient contrast against the actual surface.

## Native App — Operate / Experience
Full-bleed landscape media is the canvas. Bundle the static OFL-licensed Anton-Regular face for display numerals and Latin display roles; keep readable system/PingFang CJK controls. The same reviewed font bytes ship in device and Simulator builds. Register the bundled face on launch, retain safe system fallbacks, and record its resolved name and bundled origin in native capture evidence. Do not bundle Rockstar fonts. Keep touch targets at least 44pt and preserve the existing menu model, editing, cancellation and Reduce Motion behavior. Use consistent plum-toned panels, quiet borders, cream labels and pink selection. Preserve persisted user transforms and stable identifiers.

## GitHub README — Persuade / Read
Use a continuous illustrated composition with cinematic artwork, Anton display typography and cream/pink on midnight/plum. Every desktop panel uses a 1200px canvas and 64px content gutters; narrow panels use 760px and 40px gutters. Align visible glyph ink, images and action labels to these rails. The desktop gallery/editorial pair uses equal 520px columns and a 32px gap. Narrow screens use a single column with larger reading type. Avoid isolated chapter strips, mixed centered/left text rails and arbitrary-width screenshot pairs.

All seven panels occupy the same full README width. Their spacing comes from the same enclosing paragraph, not unrelated margins. The main installation link appears in the hero, followed by unlinked native captures, collection, direct installation, Agent instructions, source and licenses. Every painted action has a matching real anchor. The collection leads to its readable materials guide rather than a draft-only download. Alt text preserves the subject and route; complete installation and development instructions remain in ordinary Markdown documents.

Use the App's exact Anton font bytes for Latin display lettering and licensed Noto CJK outlines for promotional Chinese. Native CJK controls retain their actual system font. Embedded App JPEGs remain unmodified, with a visible Simulator/build caption. The generator checks source/capture/font identity, layout bounds and content overlap; complete desktop and phone page screenshots still require independent visual review. Source inputs, geometry and rights are in assets/readme/SOURCES.md and LAYOUT.json. GitHub supplies its own chrome; the README needs no custom CSS or JavaScript.

## Artwork and rights
The primary source is the supplied ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg, owned by Rockstar Games and applicable rights holders. Derived display images and screenshots are separate from the MIT source license. Keep exact source identities in the material attribution.

## Verification
Native captures must identify runtime, build, scene and source fingerprint. Browser mockups are not native captures. Run host, package and repository checks; retain the separate physical-device boundary. See docs/COMPATIBILITY.md for the current evidence.
