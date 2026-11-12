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
Use cinematic wide artwork, Anton display typography, cream on midnight/plum and sunset gradients. Image-made chapter titles and generous separation establish an editorial reading rhythm; related screenshots may sit in two columns, while installation methods stay readable without dense three-column prose tables. Real current native captures are the central proof. Keep accessible text, normal Markdown links and installation instructions; fold technical detail into docs or disclosures. GitHub controls its own page chrome and document body font; typography within supplied art is controllable. No unsupported CSS or JavaScript is needed in the README.

## Artwork and rights
The primary source is the supplied ULTIMATE_EDITION_VICE_CITY_STYLE_01.jpg, owned by Rockstar Games and applicable rights holders. Derived display images and screenshots are separate from the MIT source license. Keep exact source identities in the material attribution.

## Verification
Native captures must identify runtime, build, scene and source fingerprint. Browser mockups are not native captures. Run host, package and repository checks; retain the separate physical-device boundary. See docs/COMPATIBILITY.md for the current evidence.
