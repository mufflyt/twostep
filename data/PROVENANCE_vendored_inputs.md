# Vendored analysis inputs (auxiliary scripts)

These were preserved out of the ephemeral isochrones scratchpad into this committed
data folder so the twostep auxiliary sensitivity/comparator scripts are self-contained
and reproduce on a clean clone. They are NOT part of the manuscript render path.

| file | sha256 | source | consumed by |
|---|---|---|---|
| `urogyn_tract_fem65_centroids.rds` | `39dda36fccdaf851...` | isochrones/scratchpad/ (derived tract fem65 centroids, GEOID+fem65+geom 4326) | scripts/parameter_stability_access.R |
| `step_4_access_by_group.csv` | `4bff57453bf3b926...` | isochrones/artifacts/production/20260614_214343_ac587845/ | scripts/manuscript_catalog/compute_subspec_access.R |
