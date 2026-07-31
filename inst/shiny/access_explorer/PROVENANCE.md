# Access Explorer -- Verifiable Provenance

Computed from the live artifacts by `generate_provenance.R` (do not hand-edit;
rerun the script to refresh). Absent artifacts are recorded as not staged.

## Inputs

| Tab | Source | Present | sha256 | bytes | rows x cols | grain / producer |
|---|---|---|---|---|---|---|
| Disparities + Sensitivity | `data/step_4_access_by_group.csv` | yes | `4bff57453bf3b926...` | 44,986 | 224 x 15 | 2023 cross-section; subspecialty x band x race-category; vendored Step-4 access extract (data/PROVENANCE_vendored_inputs.md) |
| Temporal (2013-2023) | `artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv` | yes | `1acb9605042351f5...` | 48,602 | 616 x 7 | subspecialty x year (2013-2023) x stratum (race/rurality); scripts/stratify_allyears_access.R over the frozen E2SFCA run |
| Access map (tract geometry) | `data/cache/tract_boundaries/*.rds` | **not staged** | - | - | - | census tract polygons (CONUS); isochrones tract-boundary cache (staged) |
| Access map (access-by-tract) | `scratchpad/seam_tracts/*.parquet` | **not staged** | - | - | - | tract x subspecialty x band access + race totals; staged comparator parquet (_staging_guard.R) |

## Environment

- R: 4.4.2
- packages: sf 1.1-1, arrow (not in renv.lock -- install manually), leaflet (not in renv.lock -- install manually), ggplot2 (not in renv.lock -- install manually), dplyr 1.2.1, shiny (not in renv.lock -- install manually)
- frozen run id: `e2sfca_20260712_190734`
- engine: R/two_step_floating_catchment.R (SHA-gated); base decay = E2SFCA_DEFAULT_WEIGHTS
- CRS / grid: EPSG:5070, 500 m
- SSOT constants: R/contour_bands.R, R/access_categories.R

## One-direction contract

- **Supply** (numerator): mufflyaccess::urps_count() (artifact contract 3.0.0); never re-derived/hardcoded
- **Demand** (denominators): twostep ACS population denominators
- **Reachability** (geometry): isochrones release artifacts
- **Geography rule**: assert_matching_geography(numerator, denominator)

Full frozen-run lineage + checksums: `docs/DATA_PROVENANCE.md`, `SHA256SUMS.txt`.
This app measures access only; workforce projection is cliff's
(`cliff/docs/urps-workforce-projection-spec.md`).

