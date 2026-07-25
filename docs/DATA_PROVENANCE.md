# Frozen run artifacts — provenance

The manuscript in this repository renders entirely from **frozen artifacts of a
single production run**. No upstream pipeline, database, Census API, or Valhalla
server is needed to reproduce the paper. This document records exactly which
artifacts are used, where they came from, and what each one feeds.

## The frozen run

| Field | Value |
|---|---|
| Run ID | `e2sfca_20260712_190734` |
| Produced | 2026-07-13 00:30:21 UTC |
| Source commit (isochrones) | `ff3aac4a7aa97094fc3a9e69422425fe1a52b091` |
| Engine | raster |
| Grid / CRS | 500 m, EPSG:5070 (NAD83 / CONUS Albers, equal-area) |
| Allocator | `mass_conserving` (`allocate_pop_areaweighted`), module sha256 `2b78718b…` |
| Band weights | 30=1.00, 60=0.68, 120=0.22, 180=0.09 |
| Years | 2013–2023 (11) |
| Subspecialties | CFP, FPMRS, GO, MFM, MIGS, PAG, REI (7) → 77 subspecialty-year cells |
| Tolerances | allocator conservation 1e-6; national conservation 5e-3 |
| Headline source | `e2sfca_national_summary.csv` (cell-level, population-weighted) |
| ACS demand | frozen bundle `acs_bundle_2013_2022.rds` (no live Census API) |
| Env lock | R 4.5.1 / sf 1.1.1 / terra 1.9.34 / exactextractr 0.10.1 / GEOS 3.13.0 / GDAL 3.10.3 / PROJ 9.6.2 |

The full machine-readable manifest is
`artifacts/2sfca/ec2/e2sfca_20260712_190734/e2sfca_run_manifest.json`; it is the
authoritative provenance record (weights, per-year conservation, seam gate,
environment). The manuscript reads its `run_id` and `environment.r_version` from it
for the Data-source line and Reproducibility record.

## Artifacts and what they feed

Each is read through `scripts/manuscript_e2sfca_values.R` or directly by the
manuscript setup chunk. "Consumed by" names the object / element in
`manuscript/e2sfca_accessibility_manuscript.Rmd`.

| Artifact | Consumed by | Role |
|---|---|---|
| `artifacts/2sfca/ec2/e2sfca_20260712_190734/e2sfca_national_summary.csv` | `national_tbl` (`load_e2sfca_national_summary`) | Canonical headline: national population-weighted mean access + SPAR, per subspecialty-year |
| `artifacts/2sfca/ec2/e2sfca_20260712_190734/e2sfca_run_manifest.json` | `manifest_json` | Run provenance (run_id, allocator, env) for the Data-source + Reproducibility lines |
| `manuscript/data/workforce_counts_2020.csv` | `workforce_tbl` (`e2sfca_workforce_counts`) | Active subspecialist counts, 2020 |
| `artifacts/2sfca/figures/allsubspec_2020_inferential_TABLE.csv` | `disparity_tbl` (`e2sfca_disparity_2020`) | Table 3 + eResults S7: metro:rural ratio, rural %zero, AIAN access/%zero (with 95% ACS intervals) |
| `artifacts/2sfca/figures/GO_2020_inferential_MC_CI.csv` | `go_ci_tbl` (`gci()`) | Gynecologic-oncology Monte-Carlo 95% CIs used throughout Results |
| `artifacts/2sfca/figures/trend_hac.rds` | `trend_hac` | Newey-West HAC temporal trend estimates |
| `artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv` | stratified series | Rurality/race `pct_zero` + mean access per subspecialty-year; drives equity summaries and the rural zero-access range |
| `artifacts/2sfca/sensitivity/sensitivity_2020.csv` | sensitivity variants | 2020 seven-variant robustness sweep (base/sharper/slower/drop180/res500/gaussian/m2sfca) |
| `artifacts/2sfca/cell_zero/cell_zero_2020.csv` | `cell_zero_tbl` | Cell-level vs tract-level zero-access validation (eMethods) |
| `artifacts/2sfca/seam_subgroup/seam_subgroup.csv` | `seam_tbl` | Tract-vintage (2010↔2020) seam test by subgroup |
| `artifacts/2sfca/spatial_outcomes/spatial_outcomes_2020.csv` | `spatial_tbl` (`sp()`) | Gini, share outside 60/120/180 min, median/p10 access per subspecialty |
| `artifacts/2sfca_seam/change_faceted_df.rds` | Figure 7 change data | 2013→2023 cell-level change + winsorization threshold |
| `cliff/data/urps_module_d_differential_distance_2026-07-23.csv` | differential-distance chunk (optional) | Herb-2021-style differential distance to the nearest urogynecologist (two Discussion numbers); the render falls back to NA if absent |

## Verifying the freeze

Every artifact's SHA-256 is pinned in `SHA256SUMS.txt` at the repo root:

```bash
shasum -a 256 -c SHA256SUMS.txt   # expect "OK" for all 13 files
```

Any mismatch means an artifact changed and the rendered numbers would no longer
correspond to run `e2sfca_20260712_190734`. These files are outputs and must not be
edited by hand; to change them, re-run the analysis in the isochrones pipeline and
re-freeze.

## How the artifacts were produced (reference only)

The generation scripts in `scripts/` (`run_2sfca.R`, `stratify_allyears_access.R`,
`inferential_stats_access.R`, `sensitivity_e2sfca_2020.R`, the seam/map scripts) and
the engine in `R/` document how these artifacts were computed. They consume upstream
pipeline inputs (road-network isochrones, the year-cohort panel, the ACS bundle) that
are **not** shipped here, so they are included for provenance, not to be re-run inside
this repo. See `docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md`.
