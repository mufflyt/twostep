# twostep (development version)

## Scientific validity: fail closed on ambiguous data

A scientific join doctrine now governs every path that consumes scientific keys:
**no silent loss, no silent multiplication, no silent zeroing.** An unmatched
tract, provider, or year is an error naming what joined to what, how many keys
failed, and representative offending IDs -- not a quietly dropped row.

- `compute_e2sfca()` gains `na_pop_policy = c("error", "zero")`. `NA` population
  is UNKNOWN, not zero; coercing it drops real people from the Step 1
  denominator and **inflates** accessibility. The historical zero-fill is still
  available but must be named.
- `attach_e2sfca_population()` gains the same parameter. It previously
  zero-filled every grid tract missing from `pop_vals`, so a tract set and a
  population table that disagreed produced a complete-looking raster surface
  with a hole in the demand denominator.
- `dj7_no_access_share()` previously dropped tracts that had a measured access
  value but no demand weight, silently changing the population denominator of
  the reported no-access share.
- `dj7_tract_access()` fails closed on tracts missing from `dvec` and origins
  missing from `Rj`.
- Duplicate scientific keys are refused wherever a lookup would otherwise keep
  one row and discard the rest, which made results depend on row order.

Two real defects were found this way: a duplicate tract row inflated demand
(understating access) and a duplicate supply row **doubled** access. Neither was
reachable from the frozen run, which reports `pop_excluded_missing_pop = 0`
across all 77 rows.

## Scientific-core coverage

- New `tools/ci/scientific_coverage.R` asks a yes/no question per export -- does
  any test call this? -- rather than reporting a percentage. A headline coverage
  number stays high while an individual exported function is called by nothing.
- It found **ten scientific-core exports with zero test contact**: seven `dj7_`
  helpers and three raster-grid builders (`build_e2sfca_grid_geometry()`,
  `prepare_e2sfca_iso()`, `attach_e2sfca_population()`), confirmed independently
  by `covr` at 0% executed lines. Core coverage went 23/33 to 33/33 exercised.
  Both `dj7_no_access_share()` and `attach_e2sfca_population()` defects above
  were hiding behind that gap.
- Exports are tiered CORE / SUPPORT / OTHER by hand, because what counts as
  scientific core is a judgement about the study rather than a naming
  convention. Only CORE is fatal.

## Manuscript integrity

- Verbal quantifiers in the paper are now asserted at render time. Numbers are
  inline R against the frozen run and cannot go stale; the words around them
  could. "About one in five", "more than twice", "about six times" are checked
  against the values they describe, and a contradiction **fails the render**.
  All four claims are currently true; this pins them rather than fixing them.


## Manuscript and data
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
- Main text trimmed to under 3,000 words and the Methods rewritten in plain language
  for a clinical audience: E2SFCA is explained conceptually first, and the technical
  parameterization (distance-decay weights, Gaussian variant, conservation algebra,
  grid CRS) moved to eMethods S4. No analytical numbers, tables, or figures changed.
- **Figure 1 (`fig0_level2020.jpg`) regenerated (2026-08-02)** to remove the in-image
  title, subtitle, and footnote caption and to simplify the colorbar label; content
  unchanged (still the 2020 surface; panel numbers remain the national
  population-weighted means).
- **Figure 3 replaced (2026-08-02):** the GO-only `fig3_go2020.jpg` gave way to
  `fig3_allsubspec_stratified_2020.jpg`, which shows 2020 accessibility by rurality
  (A) and race/ethnicity (B) for **all seven subspecialties**. New twostep-native
  generator `scripts/figure3_allsubspec_stratified_2020.R` reads the vendored
  `allsubspec_allyears_stratified_LONG.csv` (the series behind Figures 4 to 6), so it
  regenerates from twostep alone. Verified from the data: rural < metropolitan and
  American Indian or Alaska Native lowest in every subspecialty.

## Figure provenance
- Added [`docs/FIGURE_PROVENANCE.md`](docs/FIGURE_PROVENANCE.md) and
  [`manuscript/figures/FIGURE_PROVENANCE.csv`](manuscript/figures/FIGURE_PROVENANCE.csv):
  for every figure, the generator script (isochrones, with the three vendored copies
  flagged), the intermediate output, the data input, the build date, and a sha256.
  Cross-linked from the README, `docs/DATA_PROVENANCE.md`, and a comment above each
  figure chunk plus the Rmd reproducibility record. Documents that filenames do not
  track figure numbers (e.g. Figure 5 is `fig4_gotrends.jpg`).

## Not yet done, require the production spatial pipeline, not documentation
- **Figure 1 is still the 2020 access surface**; its validated 2022 regeneration is
  pending a production-pipeline run and it is not described as 2022.
- Table 2 and Figures 3-6 (detailed disparity analysis) remain 2020 and are labeled
  as such.

# twostep 0.1.0

Standalone analysis and manuscript for national travel-time accessibility to the
seven ABOG-certified obstetric and gynecologic subspecialties (E2SFCA on
road-network isochrones, 2013-2023), extracted from the isochrones pipeline so the
paper builds and reproduces on its own.

## Analysis and manuscript
- Enhanced two-step floating catchment area (E2SFCA) engine
  (`R/two_step_floating_catchment.R`, SHA-gated), mass-conserving area-weighted
  demand allocation on a 500 m EPSG:5070 grid, and a Spatial Access Ratio (SPAR).
- Fully reproducible manuscript (`render.R` -> self-contained HTML/DOCX) reading a
  frozen, checksummed subset of the production run `e2sfca_20260712_190734`.
- Live-computed values via `scripts/manuscript_e2sfca_values.R`; primary temporal
  change reported for 2013-2022 (2023 is right-censored and reported provisionally).

## Single source of truth (mufflyaccess)
- Shared band/geography/denominator constants and the disparity statistics are
  sourced live from the public, pinned `mufflyaccess` package (Imports; `renv.lock`
  pins `mufflyt/mufflyaccess@0.10.0`); the 2023 URPS workforce cross-reference in
  the manuscript is pulled via `mufflyaccess::urps_count()`, never hardcoded.

## Reproducibility and integrity guards
- `render.R` verifies `SHA256SUMS.txt` for all consumed artifacts before rendering.
- `e2sfca_reconcile_disparity_artifacts()` reconciles the disparity/coverage
  artifacts against the frozen national summary (wrong-source tripwire).
- `scripts/manuscript_trend_hac.R` is the in-repo producer for the frozen HAC trend
  artifact (verified to reproduce it exactly; adds `sandwich`/`lmtest`).
- Non-normative-access-language guard (`R/access_language.R`) forbids
  shortage/adequacy labels on the modeled accessibility index.
- 25 test files (765 checks), inline fixtures only.

## E2SFCA Access Explorer (Shiny)
- `inst/shiny/access_explorer/` (`twostep::run_access_explorer()`): a separate app
  from the isochrones coverage maps, disparities, sensitivity, temporal, and a
  provenance tab reading the frozen artifacts; verifiable provenance emitted as
  `PROVENANCE.md` / `provenance.json` / `provenance.txt` (SHA256SUMS format).

## Governance
- One-direction cross-repo dependency contract (`docs/REPO_CHARTERS.md`,
  `docs/data-ownership.md`): isochrones builds the roster, mufflyaccess certifies
  the number, twostep measures access, cliff projects the future.
