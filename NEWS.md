# twostep NEWS

## twostep (development version)

### Manuscript and data
- Table 1 headline moved from 2020 to **2022** (the most recent non-right-censored
  year). 2022 provider counts and standardized supply are re-derived from the frozen
  E2SFCA national summary via the conservation identity and staged in
  `manuscript/data/workforce_counts_2022.csv` (cross-checked against the frozen run,
  0/7 disagreement; `SHA256SUMS.txt` and `docs/DATA_PROVENANCE.md` updated). Supply
  header is now "Supply per 100,000 women (all ages)".
- Subspecialty terminology changed from "female pelvic medicine and reconstructive
  surgery (FPMRS)" to **"urogynecology and reconstructive pelvic surgery (URPS)"**
  in all display text and table/figure labels; the internal `FPMRS` code key (SSOT
  set) is unchanged, so no data joins move.
- Added the true **2022 ACS 5-year** citation (`@Census2023ACS`, ACS 2018-2022,
  Table B01001) and repointed the "2022 American Community Survey" data statement to
  it (the general ACS methods reference stays `@Census2021ACS`).
- README now names the four analysis years explicitly and documents the
  `mufflyaccess` URPS contract (1,306 national / 1,303 CONUS, 2023).

### Not yet done, require the production spatial pipeline, not documentation
- **Figure 1 is still the 2020 access surface**; its validated 2022 regeneration is
  pending a production-pipeline run and it is not described as 2022.
- Table 2 and Figures 3-6 (detailed disparity analysis) remain 2020 and are labeled
  as such.

## twostep 0.1.0

Standalone analysis and manuscript for national travel-time accessibility to the
seven ABOG-certified obstetric and gynecologic subspecialties (E2SFCA on
road-network isochrones, 2013-2023), extracted from the isochrones pipeline so the
paper builds and reproduces on its own.

### Analysis and manuscript
- Enhanced two-step floating catchment area (E2SFCA) engine
  (`R/two_step_floating_catchment.R`, SHA-gated), mass-conserving area-weighted
  demand allocation on a 500 m EPSG:5070 grid, and a Spatial Access Ratio (SPAR).
- Fully reproducible manuscript (`render.R` -> self-contained HTML/DOCX) reading a
  frozen, checksummed subset of the production run `e2sfca_20260712_190734`.
- Live-computed values via `scripts/manuscript_e2sfca_values.R`; primary temporal
  change reported for 2013-2022 (2023 is right-censored and reported provisionally).

### Single source of truth (mufflyaccess)
- Shared band/geography/denominator constants and the disparity statistics are
  sourced live from the public, pinned `mufflyaccess` package (Imports; `renv.lock`
  pins `mufflyt/mufflyaccess@0.10.0`); the 2023 URPS workforce cross-reference in
  the manuscript is pulled via `mufflyaccess::urps_count()`, never hardcoded.

### Reproducibility and integrity guards
- `render.R` verifies `SHA256SUMS.txt` for all consumed artifacts before rendering.
- `e2sfca_reconcile_disparity_artifacts()` reconciles the disparity/coverage
  artifacts against the frozen national summary (wrong-source tripwire).
- `scripts/manuscript_trend_hac.R` is the in-repo producer for the frozen HAC trend
  artifact (verified to reproduce it exactly; adds `sandwich`/`lmtest`).
- Non-normative-access-language guard (`R/access_language.R`) forbids
  shortage/adequacy labels on the modeled accessibility index.
- 25 test files (765 checks), inline fixtures only.

### E2SFCA Access Explorer (Shiny)
- `inst/shiny/access_explorer/` (`twostep::run_access_explorer()`): a separate app
  from the isochrones coverage maps, disparities, sensitivity, temporal, and a
  provenance tab reading the frozen artifacts; verifiable provenance emitted as
  `PROVENANCE.md` / `provenance.json` / `provenance.txt` (SHA256SUMS format).

### Governance
- One-direction cross-repo dependency contract (`docs/REPO_CHARTERS.md`,
  `docs/data-ownership.md`): isochrones builds the roster, mufflyaccess certifies
  the number, twostep measures access, cliff projects the future.
