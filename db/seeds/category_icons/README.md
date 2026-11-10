# Default category icons

One 256×256 PNG per seed `icon` key (`doctor.png`, `pharmacy.png`, …), attached by
`Category#attach_default_icon!` (seeds and `bin/rails categories:attach_default_icons`).

Glyphs: [Material Symbols](https://github.com/google/material-design-icons) (rounded, filled),
© Google, Apache License 2.0 — npm `@material-symbols/svg-400` 0.48.2. Every glyph is solid black
(`#000000`, 144px) on one neutral tile (`#EEEEEE`, radius 60) so it still reads on a dark app
background; a black glyph on a transparent PNG would disappear there.

| key | symbol |
|---|---|
| doctor | stethoscope |
| pharmacy | pill |
| restaurant | lunch_dining |
| shop | shopping_bag |
| craft | construction |
| school | backpack |
| bakery | breakfast_dining |
| transport | airport_shuttle |
| mosque | mosque |
| sports | trophy |
| services | apartment |

Replacing a file here changes nothing for a category that already has an image:
`attach_default_icon!` skips those on purpose, so dashboard uploads are never overwritten.
