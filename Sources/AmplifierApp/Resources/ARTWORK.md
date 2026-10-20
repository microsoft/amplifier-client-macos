# Tempo artwork

Arc (cyan/amber), Relay (blue), and Crest (purple/blue) were generated for this
project from selected Amplifier Edge + Flow concepts. Arc uses the
rounded triangular swirl from the selected reference. No faces or limbs.

The three animated sprite sheets are 1536 × 2288: eight columns of 192 × 208 cells,
nine activity rows followed by sixteen clockwise look directions. Activity frame
counts: 6, 8, 8, 4, 5, 8, 6, 6, 6. Look rows have eight frames each, starting
at up (000°), clockwise through right (090°), down (180°), left (270°).

The selected design inventory is Relay, Accord, Arc, Crest, Chord, and Meter;
colors exclude white lights. All six shapes are bundled. Accord, Meter, and Chord use transparent still sculptures with native floating motion; Arc, Relay, and Crest retain their frame animations. The shared palette is applied at render time to preserve glass highlights and alpha.

New transparent cutouts were generated with built-in image_gen from the selected concept boards. Exact prompts are preserved in GENERATED-ARTWORK.json.

MenuBarIcon.png and MenuBarIcon@2x.png are the official Amplifier menu-bar
template assets, copied unchanged from microsoft/amplifier-unified
assets/branding/icons at 0720c876a. macOS tints these for light and dark menus.

Verified identical to microsoft/amplifier assets/branding/icons/MenuBarIcon@2x.png
(Git blob 1a798aae8238c9906406be2cca3aee89b1646b16).

Dark glass uses six separate transparent sculptures reconstructed with built-in
image_gen from the original DARK GLASS Meter/Accord/Relay, Lattice/Eddy Soft/Arc,
and Chord/Crest/Fold concept boards. These are independent assets, not dimmed clear
glass. The Clear / Dark buttons select the resource; the same runtime palette colors
its light channels. All dark sculptures use native floating motion, respecting
Reduce Motion. Exact prompts and asset hashes are in GENERATED-ARTWORK.json.
