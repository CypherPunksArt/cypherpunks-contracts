# Trait Element Intake — Reconciliation Report

**Date:** 2026-07-08
**Frozen table:** metadata.json deriving to `sha256:8ba2d3888e3eefb5908a80eaf84eac0edc944fc0d2227e383ee7d86acc303c29` (ruling (a), post Pepe→Frog)
**Export:** Notion ExportBlock-66cf9e19 (`Private & Shared/10K CypherPunks/`)
**Machine-readable detail:** `report2.json` (same directory). Intake script: `intake2.py`.

## Rev 7 numbers

| | |
|---|---|
| **Native canvas** | **40 × 40 px** (all 355 elements, 2000×2000 at exact 50 px blocks, lossless recovery proven per file) |
| **Unique trait elements** | **355 files** (+ 1 flat background) |
| **Categories** | Background (flat colour), Body, Clothing, Head, Earring, Eyes, Mouth, Accessory — plus Gender (element-set selector) and Year (non-art) |

## Inventory (step 2)

| Category | Element files | Metadata values (union M+F) |
|---|---|---|
| Body | 26 | 13 |
| Clothing | 102 | 73 |
| Head | 99 | 94 |
| Earring | 6 | 6 |
| Eyes | 36 | 34 |
| Mouth | 51 | 31 |
| Accessory | 35 | 31 |
| **Total** | **355** | 282 values / 419 gender-split combos |

File > value counts are expected: many values have separate male/female art.

## Step 1 — name matching (exact; near-misses reported, never normalised)

Of 419 gender-split metadata (gender, category, value) combos:
- **162 matched exactly** against the export CSVs (the export's own value→file table).
- **186 matched only as near-misses** — overwhelmingly trailing spaces in CSV trait names (165 distinct CSV names carry stray whitespace, e.g. `'Braces '`, `'Smile '`). Findings, listed in report2.json `near_miss_pairs`.
- **11 resolved cross-gender** (female metadata values whose art row is listed male-only or vice versa — shared elements).
- **60 unmatched metadata values** and **82 unmatched CSV rows** (orphans both ways, full lists below). Most pair up as obvious label drift (word order, renames, misspellings).
- **1 ambiguous**: Female Body `Unobtainium` matches both `body_unobtainium.png` and `female_body_unobtainium.png` (two CSV rows).
- **0 orphan files on disk, 0 CSV-referenced files missing** — every top-level element PNG is CSV-referenced and present.

### Orphans: metadata values with no export row (60)

M Accessory: Frog (1) — **known pair**: export row 'Pet Pepe ' → accessory_pepe.png
M+F Accessory: Gold Boombox (10+1) — likely 'Boombox Gold' → accessory_boombox_gold.png
M+F Accessory: Punk Necklace (9+1) — likely 'CypherPunk(s) Necklace ' → accessory_eth_chain.png
M+F Body: Bones (238+26) — likely 'Skeleton'/'Skeleton ' → body_skeleton.png / female_body_skeleton.png
M Clothing: #24 Jersey (46) — likely 'Mamba Jersey' → clothing_jersey_lakers.png
M+F Clothing: Gold Cape (24+4) — likely 'Cape Gold' → clothing_cape_gold.png / female_clothing_cape_gold.png
F Clothing: Pink Cape (5) — likely 'Cape Pink' → female_clothing_cape_pink.png
F Clothing: Polka Dot Dress (25) — likely 'Dress (new pattern) ' → female_clothing_dress_polkadot.png
M+F Clothing: Prison Stripes (98+2) — likely 'Jail Strips ' → clothing_tahirt_jail.png [sic] / female_clothing_jail_stripes_fem.png
M Clothing: Punk Jacket 1 (124) — likely 'Punk Jacket' → clothing_jacket_punk.png
F Clothing: Punk Jacket 3 (21), Punk Jacket 4 (10) — female CSV has 'Punk Jacket' and 'Punk Jacket 2 ' only
M Clothing: Purple Cape (61) / Red Cape (123) — likely 'Cape Purple ' / 'Cape Red '
M+F Clothing: Spot Puffer (32+9) — likely 'Damien Hirst Puffer' → clothing_puffa_hurst.png
M Clothing: Wallstreet Suit (115) — likely 'Wolf of Wallstreet Suit ' → clothing_suit_wolf.png
M+F Eyes: Blue Beams (46+3) — likely 'Blue Beam eyes ' → eyes_laserangle_teal.png
M Eyes: Classic Shades (5) — no candidate row identified
M+F Eyes: Cosmo Shades (122+3) — likely 'Cosomo Shades ' [sic] → eyes_cosomo.png
M+F Eyes: Laser Eyes (59+10) — likely 'Red Laser ' → eyes_laser_red.png (colour variants exist: teal)
M+F Eyes: On Fire (6+5) — no candidate row identified
M+F Eyes: Right Click (127+9) — likely 'Right click and save shades ' → eyes_right_click.png
M Eyes: Right Click Shades (2) — overlaps same candidate; distinct value, QUESTION
M+F Eyes: Shades (336+46) — likely 'Ray Bans' → eyes_raybans.png
M+F Head: Black BW Cap (161+25) — likely 'BW Cap Black ' → head_bw_cap_black.png (same for Red 176, White 169)
F Head: Blonde 50s (16) — likely 'Monroe ' → female_head_monroe.png
F Head: Blue Tiara (6) / Purple Tiara (4) — likely 'Tiara Blue Gem ' / 'Tiara Purple Gem '
F Head: Brunette Long (47) — likely 'Brown Long' → female_hair_long_brown.png
F Head: Brunette Sidehair (56) — likely 'Brown Sidehair' → female_hair_side_brown.png
M Head: Combover (82) — likely 'Trump' → head_trump.png
F Head: Crazy 80s (8) — likely 'Crazy Hair ' → female_head_crazy.png
M Head: Crazy Purple (79) — likely 'Purple ' → head_purple.png
M Head: Forrest Beanie (27) — likely 'Forrest Forrest' [sic] → head_beanie_forrest.png
F Head: Navy Beanie (20) — likely 'Black Beanie ' → female_head_beanie_black.png (QUESTION: navy vs black)
F Head: Orange Cap (28) — likely 'Yellow Cap ' → female_head_cap_yellow.png (QUESTION: orange vs yellow)
M Head: Pink Beanie (43) — likely 'Tangerine Beanie' → head_beanie_tangerine.png (QUESTION: pink vs tangerine)
M Head: Porkpie Hat (170) — likely 'Hiesenburg Hat ' [sic] → head_heisenberg.png
M+F Head: Red Visor (46+19) — no candidate row identified
M Mouth: Brown Beard (276) — likely 'Full Beard Brown' → mouth_beard_brown.png
F Mouth: Goofy (25) — likely 'Laugh ' → female_mouth_goofy.png
M Mouth: Grey Beard (10) — likely 'Full Beard Grey' → mouth_beard_grey.png
M Mouth: Napoleon (275) — likely 'Napolean ' [sic] → mouth_napoleon.png
M Mouth: Thick Stache (290) — likely 'Selleck ' → mouth_selleck.png

("likely" pairings are token/pixel-informed suggestions, NOT applied. Two were pixel-PROVEN in step 6: see below.)

### Orphans: export rows matching no metadata value (82)

Full list in report2.json `unmatched_csv_rows`. By category: Clothing 26, Head 21, Eyes 17, Mouth 8, Accessory 7, Body 3. They are largely the other half of the pairs above, plus genuinely unused art:
- `head_trump.png` ('Trump'), `eyes_teal.png` ('Teal' — but see step 6: this art IS used, under the label 'Blue'), `eyes_blue.png` matched 'Blue' by name but is NOT the art the frozen collection renders, `head_birthday_hat.png` ('Birthday Hat'), `accessory_doge.png`/`accessory_eagle.png` ('Pet Doge '/'Pet Eagle '), jersey rows ('Mamba Jersey', 'Boys In Blue Jersey' → clothing_baseball_dodgers.png, 'Bronx Jersey' → clothing_baseball_yankees.png).

### Whitespace census
165 of 449 CSV trait names carry leading/trailing whitespace. Systemic Notion data-entry artifact; every affected match is filed as a near-miss, none normalised.

## Step 3 — dimensions & native grid

- 355/355 trait elements: exactly 2000×2000, uniform 50 px blocks, native **40×40**, nearest-neighbour re-upscale reproduces the original **byte-exact (lossless recovery proven per file)**.
- **Zero blockers** among trait elements: no non-uniform blocks, no non-integer scales, no anti-aliased edges.
- `background.png`: 1600×1600 solid single colour RGB(99,133,150) — exactly the background colour of the frozen composed punks. Not a grid; no blocker.
- 1/1 art (4 PNGs + `traders_1of1_xcopy.gif`) excluded from element checks — they are full punks, not layers. The GIF would be a blocker if treated as an element.

## Step 4 — palette

- **379 distinct opaque colours** collection-wide (union over native grids).
- Per element: 1–21 colours (incl. transparency).
- Transparency is a **true alpha channel** (alpha=0 pixels), not a background colour — confirmed on all 355.
- **Finding:** 3 male mouth files (`mouth_focused.png`, `mouth_happy.png`, `mouth_sad.png`) each contain 1 semi-transparent colour (0<alpha<255). The frozen renders blend it identically to standard alpha compositing (step-6 punk 2120 reproduces byte-exact), but Phase 8's RLE/palette design must budget for non-binary alpha on these three.

## Step 5 — layer order: QUESTION

The export does **not** encode a z-order (CSVs carry no layer index; folder structure is per-trait pages). Inferred order:

**Background → Body → Clothing → Head → Earring → Eyes → Mouth → Accessory**

Basis: the local punk-editor compositor uses it (verified pixel-perfect 2026-07-06 on punks 1/500/7777) and all five step-6 composites reproduce frozen art byte-exact under it. Please confirm for Rev 7.

## Step 6 — composite spot-check (seed 8379, native 40×40)

| Punk | Result |
|---|---|
| 2073 (M) | **PASS** — 0 diff |
| 3218 (M) | **PASS** — 0 diff |
| 2120 (M) | **PASS** — 0 diff (exercises semi-alpha mouth_focused) |
| 9034 (M) | FAIL as-mapped (16 px) → **PASS (0 diff)** with `mouth_smile.png` for Mouth='Grin' and `eyes_teal.png` for Eyes='Blue' |
| 4008 (M) | FAIL as-mapped (12 px) → **PASS (0 diff)** with `mouth_smile.png` for Mouth='Grin' |

Two pixel-proven label-drift pairs:
- Metadata **'Grin'** (M Mouth) = export **'Smile '** → `mouth_smile.png`.
- Metadata **'Blue'** (M Eyes) = export **'Teal'** → `eyes_teal.png`. **Trap:** export also has a row 'Blue' → `eyes_blue.png` which matches the metadata label exactly but is NOT the art the frozen collection renders. Name matching alone will bind wrong art here; Phase 8 needs pixel-validated bindings.

Sample was drawn from the 6,692 punks fully resolvable via exact+documented-near-miss mapping; 3,308 punks carry at least one of the 60 orphan values above.

## Remarks

- 1/1s (Vitalik, Beeple, Snowfro, Cozomo PNGs + XCOPY GIF) exist in the export but correspond to no metadata trait value — how they map to the frozen 10k (GENESIS range?) is outside this intake's scope.
- Notion page attachments in subfolders include `Boxing_Robe.png` (an element-looking file NOT at top level and not CSV-referenced) and 4 screenshots — noted, not treated as elements.
- `accessory_basketball 1.png` exists alongside `accessory_basketball.png`: BOTH are CSV-referenced (per-gender rows) and their bytes DIFFER — two distinct elements, not a Notion artifact. `head_blonde_mohawk 1.png` is CSV-referenced and byte-identical to `head_blonde_mohawk.png`. (Corrected at import; the original intake wording called these duplicates.)
- Planning tables (Distribution, Body Rarity) ignored per scope.
