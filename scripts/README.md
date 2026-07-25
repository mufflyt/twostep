# scripts/

Most scripts here are **reference/provenance**: they document how the frozen
artifacts in `artifacts/` were produced, but they consume upstream pipeline inputs
(road-network isochrones, the year-cohort panel, the ACS bundle, Step-4 tract
access) that are **not** shipped in this repo. See `docs/DATA_PROVENANCE.md` and
`docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md`.

## Runs in this repo
- `manuscript_e2sfca_values.R` — canonical loaders sourced by the manuscript at
  render time (the only script the render depends on).
- `check_wordcount.R` — QA: counts the rendered main text vs the journal limit.

## Reference only (need upstream data)
- **E2SFCA engine drivers:** `run_2sfca.R`, `sensitivity_e2sfca_2020.R`,
  `seam_test_2sfca.R`, `prefetch_2sfca_acs.R`, `stratify_allyears_access.R`,
  `stratify_go_2020_access.R`, `stratify_go_allyears_access.R`,
  `inferential_stats_access.R`, `compile_inferential_table.R`,
  `spatial_outcomes_2020.R`, `parameter_stability_access.R`
- **Figures / maps:** `figure_2sfca_national_11yr.R`, `figure_2sfca_seam_outcomes.R`,
  `map_2sfca_coverage_by_year.R`, `map_go_2020_access_surface.R`,
  `map_fpmrs_allyears_access_surface.R`, `map_allsubspec_allyears_access_surface.R`,
  `map_equity_heatmap.R`
- **EC2 / S3 orchestration:** `ec2_run_2sfca.sh`, `ec2_run_seam.sh`,
  `ec2_install_pkgs.R`, `s3_multipart_put.sh`
- **`desjardins7/`** — the 7-subspecialty Desjardins E2SFCA replication.
- **`manuscript_catalog/`** — the area-weighted access catalog and bivariate map
  builders. These read Step-4 access data that lives in the isochrones repo
  (including the ~60 MB interactive bivariate map, which stays upstream).
