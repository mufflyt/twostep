# twostep · E2SFCA Access Explorer (Shiny)

A **separate** Shiny app from the isochrones drive-time coverage maps. It is the
twostep **access** explorer: supply-to-demand accessibility to OB/GYN
subspecialists, per capita and by whom. isochrones answers "is a subspecialist
reachable"; twostep answers "how accessible, and for which populations."

## Run

The app's own dependencies are **not** pinned in `renv.lock` (`shiny`, `leaflet`,
`ggplot2`, and `arrow` for the map tab), so `renv::restore()` will not install
them. Install them first:

```r
install.packages(c("shiny", "leaflet", "ggplot2", "arrow"))
# from the repo root:
shiny::runApp("inst/shiny/access_explorer")
# or, once twostep is installed:
twostep::run_access_explorer()
```

Verifiable provenance for the app's inputs is emitted in three forms, regenerated
by one script (`Rscript inst/shiny/access_explorer/generate_provenance.R`):

- `PROVENANCE.md` — human-readable (sha256, byte/row counts, environment, contract)
- `provenance.json` — machine-readable, structured (for pipelines)
- `provenance.txt` — SHA256SUMS format; verify inputs from the repo root with
  `shasum -a 256 -c inst/shiny/access_explorer/provenance.txt`

## Tabs

- **Disparities** (always runnable): 2023 access `%` by race/ethnicity and by
  drive-time band, for a chosen subspecialty, with 90% MOE error bars. Reads the
  vendored `data/step_4_access_by_group.csv` (a 2023 cross-section: 7
  subspecialties x 4 bands x 8 race categories).
- **Access map** (gated): bivariate access x minority-share tract choropleth,
  **reusing** `scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R`
  (same tertile breaks and 3x3 palette, so it cannot drift from Figure 6). It
  lights up when the tract layer is staged (tract geometry under
  `data/cache/tract_boundaries/` + access-by-tract parquet under
  `scratchpad/seam_tracts/`); otherwise it shows how to stage it.

## Data provenance

The app **reads frozen artifacts and never recomputes them**. The in-app
**Provenance** tab renders this same table with a live "present in this checkout?"
status per source.

### By tab

| Tab | Source (read) | Grain | Fields used | Lineage / SSOT |
|---|---|---|---|---|
| **Disparities** | `data/step_4_access_by_group.csv` | 2023 cross-section; subspecialty × band × race-category | `range, category, subspecialty, percent, percent_moe, count, total` | Vendored Step-4 access extract (`data/PROVENANCE_vendored_inputs.md`); SSOT `DENOMINATOR_CATEGORY` (`R/access_categories.R`), band via `range` |
| **Sensitivity** | `data/step_4_access_by_group.csv` (+ live decay reweighting) | 2023; all women, 4 bands | cumulative `percent` at `range` 1800/3600/7200/10800 | Decay schemes lifted verbatim from `scripts/parameter_stability_access.R`; **base = `E2SFCA_DEFAULT_WEIGHTS`** from the SHA-gated engine `R/two_step_floating_catchment.R`. Composite computed live (incremental weights), not stored |
| **Temporal** | `artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv` | subspecialty × year (2013–2023) × stratum | `subspec, year, stratum_type, stratum, mean_access, pct_zero, women` | `scripts/stratify_allyears_access.R` over the frozen E2SFCA run; trend = OLS (mirrors `accessibility_stratification::annual_trend`). Artifact code `FPMRS` = URPS |
| **Access map** (gated) | `data/cache/tract_boundaries/*.rds` + `scratchpad/seam_tracts/*.parquet` | census tract; bivariate access × minority share | tract geometry; parquet `percent` + race `total` | Reuses `scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R` (same tertiles + 3×3 palette, cannot drift from Figure 6); SSOT `PRIMARY_ACCESS_BAND_SEC` + `DENOMINATOR_CATEGORY`; gated by `_staging_guard.R` |

### The one-direction contract

- **Supply** (workforce numerator): `mufflyaccess::urps_count()` under artifact contract 3.0.0, never re-derived or hardcoded here.
- **Demand** (population denominators): twostep's own ACS surfaces.
- **Reachability** (travel-time geometry): isochrones release artifacts.
- Numerator and denominator must share one geography (`assert_matching_geography()`).

Shared band/category constants: `R/contour_bands.R`, `R/access_categories.R`. E2SFCA
engine (SHA-gated): `R/two_step_floating_catchment.R`; CRS EPSG:5070, 500 m grid.
Frozen run + checksums: `docs/DATA_PROVENANCE.md`, `SHA256SUMS.txt` (run id pinned by
`E2SFCA_FROZEN_RUN_ID` in `scripts/manuscript_e2sfca_values.R`).

## Scope

This app does **not** project the workforce, that is cliff's domain (see
`cliff/docs/urps-workforce-projection-spec.md`). twostep's app is cross-sectional
/ temporal **access** only.

## Extending

- The vendored CSV is 2023 only; a temporal (2013-2023) Disparities view needs the
  all-years access artifact staged.
- A "sensitivity" tab (vary the Gaussian decay weights / threshold, watch access
  tiers shift) is the natural next tab, wired to `parameter_stability_access.R`.
