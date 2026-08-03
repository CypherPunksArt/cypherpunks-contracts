# Pixel-Proof Binding Manifest — Phase 8 Step 0

**Date:** 2026-07-08 (re-proven same day for the Gold Cobra 1/1 re-freeze)
**Frozen table:** `docs/art/traits/pieces.json`, sha256
`a2cd9560a1370809e2ca663d8e011092707a090d9333de159e6ec2ce9f8fe13f` (Rev 9
fingerprint — supersedes the Rev 8 `e94b9907…` table via approved relabels +
3 same-art Eyes merges, art byte-identical per I12; the file bytes ARE the
`JSON.stringify(pieces)` derivation, so `shasum -a 256` on the file
reproduces it directly).
**Generator:** `tools/art/bind_elements.py` (deterministic; rerun to verify).
**Machine-readable result:** `bindings.json` · per-punk blend regime:
`semi-rounding.json` · visual receipt: `contact-sheet.png`.

## Proof standard

Bindings were established by composite proof ONLY — the solver starts every
(gender, category, value) combo with all 356 elements as candidates and never
consults filenames to propose or restrict a binding (Rev 8 §02 rule):

1. **Top-down layer peel** (Accessory → Mouth → Eyes → Earring → Head →
   Clothing → Body): a candidate survives a combo iff, for every wearer,
   every fully-opaque candidate pixel not possibly occluded from above
   matches the frozen render exactly. Occlusion uses the union of upper
   combos' surviving candidates' footprints, so no wrong upper pick can
   eliminate true lower art.
2. **Product-search settlement** for the five combos with no opaque evidence
   (the fully-semi-alpha mouths, see below).
3. **Repair loop**: 20 low-wearer combos where the peel's largest-footprint
   pick was a visible-pixel-equivalent impostor were exposed by the full
   composite and rebound; every rebind re-verified against every wearer.
4. **Definitive proof:** all **10,000/10,000** punks composite **byte-exact**
   at native 40×40 against `docs/art/renders/`. Coverage is total: all 420
   gender-split metadata combos bound, every bound file proven by that
   byte-exact composite.

## Results

| | |
|---|---|
| Gender-split combos bound | **420 / 420** |
| Punks byte-exact | **10,000 / 10,000** |
| Element files bound | 330 of 356 (+1 derived copy, see flag) |
| Unused files | 26 (listed below) |
| Equivalent ties | 4 combos, all byte-identical twin files |

### Rev 8 change: Gold Cobra 1/1 (the LAST trait change — table closed)

`accessory_cobra_gold.png` (intake 2026-07-08: native 40×40 at scale 50,
block-uniform, lossless re-upscale, zero semi-alpha, silhouette identical
to `accessory_cobra.png`) binds `('Male', 'Accessory', 'Gold Cobra')` —
worn only by punk 4705, whose frozen render was regenerated with a
byte-exact composite proof (diff vs the Rev 7 render confined to the
125-px cobra mask). Cobra drops 10 → 9 wearers (8 male + 1 female).

### Named resolutions (requested)

- **Female Body Unobtainium** — `female_body_unobtainium.png` won;
  `body_unobtainium.png` is the male binding. Both candidates resolved by
  composite proof, no ambiguity.
- **Basketball (both variants):** `accessory_basketball 1.png` won BOTH
  the male (1 wearer) and female (1 wearer) combos; `accessory_basketball.png`
  is pixel-distinct and **unused** by the frozen collection.
- **Known traps confirmed:** metadata `Male Eyes Blue` → `eyes_teal.png`
  (`eyes_blue.png` exists and is unused — name matching would have bound
  wrong art); metadata `Male Mouth Grin` → `mouth_smile.png`.
- `head_trump.png` — see flag below.

### FLAG 1 (SIGNED OFF 2026-07-16): Combover art

> **Resolution — signed off by Kenny, 2026-07-16.** Ships as-is: the trait
> keeps the public name `Combover`, the art is unchanged, and the combo
> binds `derived/head_combover.png` per the never-bind rule below. No
> metadata, table, or fingerprint change. Decision made with full knowledge
> of the `head_trump.png` provenance.

`('Male', 'Head', 'Combover')` (82 wearers) is pixel-proven to render the art
contained in `head_trump.png` — it is the **unique** non-vacuous survivor,
and no other file reproduces those 82 frozen renders. Per the never-bind
rule the file `head_trump.png` does not bind and stays on the excluded list;
the combo binds a byte-identical derived copy `derived/head_combover.png`
(raw-RGBA sha256 `e65aa9a055b38bc6…`). The on-chain bytes are forced by the
frozen renders either way — only the naming/provenance is a choice, so this
does not block the Descriptor, but it needs explicit sign-off.

### FLAG 2: two semi-alpha rounding regimes in the frozen renders

The three semi-transparent mouths (`mouth_focused/happy/sad.png`, each a
single colour (0,0,0) at alpha 128 = 50%) blend against varying bodies. The
frozen renders were produced by **two different export pipelines** that
round `x.5` ties differently (empirical over all 2,590 semi-mouth wearers;
**no punk mixes regimes**):

- regime **F** (1,858 punks): standard `over` with a=128/255, round to
  nearest — dst 235 → 117;
- regime **C** (715 punks): alpha treated as exactly ½, round half up —
  dst 235 → 118;
- 7,427 punks composite identically under both (no semi mouth, or no odd
  dst under a semi pixel).

Per-punk regime is recorded in `semi-rounding.json` and is a property of the
frozen PNGs, not of the art. The Descriptor carries `(0,0,0,128)` verbatim;
the I12 harness composites decoded tokenURI data with the recorded per-punk
regime for byte-exactness. Browser SVG rasterisers blend in float and may
show at most ±1/255 on ≤4 pixels for these punks versus the frozen PNGs —
sub-perceptual, and the on-chain data is exact.

### Cross-gender shared art

`female_mouth_focused.png` / `female_mouth_happy.png` exist but are UNUSED:
the frozen female Focused/Happy punks render the male `mouth_focused.png` /
`mouth_happy.png` (pixel-proven). Several other combos share one file across
genders (recorded per-combo in `bindings.json`).

### Equivalent ties (byte-identical twins)

Both files in each pair are byte-identical, so either binds; the canonical
name was chosen and the twin listed as unused:

- `head_blonde_mohawk.png` ≡ `head_blonde_mohawk 1.png`
  (Male + Female Blonde Mohawk)
- `head_mullet_blonde.png` ≡ `head_mullet_blonde 1.png`
  (Male + Female Blonde Mullet)

### Excluded / unused art (26 files)

Present in the import, bound to nothing — the frozen collection never
renders them:

`accessory_basketball.png`, `accessory_doge.png`, `accessory_eagle.png`,
`clothing_baseball_dodgers.png`, `clothing_baseball_yankees.png`,
`clothing_tshirt_banana.png`, `clothing_tshirt_bubble.png`,
`clothing_tshirt_butcher.png`, `clothing_tshirt_eth.png`,
`clothing_tshirt_ringers.png`, `clothing_tshirt_squiggle.png`,
`eyes_aviators_gold.png`, `eyes_blue.png`, `eyes_laser_teal.png`,
`eyes_pokerchips.png`, `eyes_retro_pink.png`,
`female_clothing_doomed_mono_crop.png`,
`female_clothing_hoodiefem_black.png`, `female_mouth_focused.png`,
`female_mouth_happy.png`, `head_bandana_gold.png`, `head_birthday_hat.png`,
`head_blonde_mohawk 1.png`, `head_mullet_blonde 1.png`, `head_trump.png`
(never-bind), `mouth_braces.png`.

## Contact sheet

`contact-sheet.png` — 24 seeded-random punks (seed 8379) plus the three
semi-alpha mouth wearers (`mouth_focused` punk 91, `mouth_happy` punk 81,
`mouth_sad` punk 6), element-composite beside frozen render, ×8
nearest-neighbour.
