# Imported art inputs — Phase 8 (Descriptor)

Imported 2026-07-08 from the trait-element intake session. Sources:

- `elements/` — 356 trait elements at NATIVE 40x40, losslessly recovered
  (block-uniformity asserted per file) from the 2000x2000 PNGs in the Notion
  export `f5014bd6-...-ExportBlock-66cf9e19...zip` ("Private & Shared/10K
  CypherPunks"). Includes the intake-session renames: clothing_8_jersey,
  clothing_23_jersey, clothing_33_jersey, accessory_frog; plus
  accessory_cobra_gold.png (Gold Cobra 1/1 on #4705, intake 2026-07-08 —
  the LAST trait change, table closed).
- `background.json` — the flat background: solid RGBA(99,133,150,255)
  ("Punk"), from background.png (1600x1600 solid) in the same export.
- `renders/` — all 10,000 frozen composed punks at NATIVE 40x40, losslessly
  recovered from frontend/public/punks/full/ in CypherPunksArt/cypherpunks
  at commit 0d8715bf (trait table fingerprint sha256:4e19f6cc...);
  cypherpunk-4705.png regenerated 2026-07-08 (Cobra → Gold Cobra, byte-exact
  composite proof; trait table fingerprint now sha256:a2cd9560... — Rev 9 table;
  supersedes Rev 8 sha256:e94b9907 via approved relabels + 3 same-art Eyes merges,
  art byte-identical per I12).
- `intake/` — the intake reconciliation report (INTAKE-REPORT.md, report2.json).

These are Phase 8 inputs only. Bindings element->value come from the pixel-proof
manifest (Step 0), NOT from filenames — name matching is prohibited (Rev 7).
