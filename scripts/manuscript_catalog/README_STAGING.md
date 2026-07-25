# Staging the manuscript-catalog comparator inputs

The `manuscript_catalog/` scripts produce the SECONDARY comparator tables/figures
(Tables/Figures beyond the primary E2SFCA paper). They are **not** part of the main
manuscript render (`render.R` does not depend on them).

## Why these inputs are not in the repo

They depend on a per-tract access dataset that is too large to vendor into git:

| Input (repo-root relative) | Size | Notes |
|---|---|---|
| `scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet` | ~410 MB | per-tract access x RUCA, 2023 |
| `scratchpad/seam_tracts/acs_b01001_female_age_2023.rds` | ~6.5 MB | ACS female age bands, 2023 |
| `scratchpad/manuscript_stage/statistics_catalog.rds` | ~8 KB | catalog snapshot |

The small, stable auxiliary inputs used elsewhere ARE vendored in `data/` (see
`data/PROVENANCE_vendored_inputs.md`); only this large comparator dataset is staged.

## How to stage

Copy the files above from an isochrones production run (the frozen lineage used for the
comparator layer is run **ac587845**) into the matching paths under `scratchpad/`:

```
mkdir -p scratchpad/seam_tracts scratchpad/manuscript_stage
cp <isochrones>/scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet scratchpad/seam_tracts/
cp <isochrones>/scratchpad/seam_tracts/acs_b01001_female_age_2023.rds               scratchpad/seam_tracts/
cp <isochrones>/scratchpad/manuscript_stage/statistics_catalog.rds                  scratchpad/manuscript_stage/
```

Every `manuscript_catalog/` script sources `_staging_guard.R`, which **fails loudly**
with this instruction if the parquet is absent, so a missing stage is an explicit error
rather than a cryptic crash.
