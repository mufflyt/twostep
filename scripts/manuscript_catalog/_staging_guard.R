# Fail-loud staging guard for the manuscript_catalog comparator layer.
# The per-tract access parquet (~410 MB) and its siblings are NOT vendored into the
# repo. Stage them from an isochrones production run (e.g. ac587845) before running any
# manuscript_catalog script. See scripts/manuscript_catalog/README_STAGING.md.
local({
  parq <- "scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet"
  if (!file.exists(parq))
    stop("[manuscript_catalog] missing staged input: ", parq,
         "\n  The comparator-layer inputs (~410 MB seam_tracts parquet + siblings) are not",
         " vendored. Stage them from an isochrones production run into scratchpad/seam_tracts/",
         " and scratchpad/manuscript_stage/. See scripts/manuscript_catalog/README_STAGING.md.",
         call. = FALSE)
})
