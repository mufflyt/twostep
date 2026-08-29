# Raster E2SFCA for one (subspecialty, year) cell.

Raster E2SFCA for one (subspecialty, year) cell.

## Usage

``` r
compute_e2sfca_raster(
  grid,
  iso,
  supply,
  weights = E2SFCA_DEFAULT_WEIGHTS,
  step2_power = 1,
  per_capita_scale = 1e+05,
  thresholds = E2SFCA_DEFAULT_THRESHOLDS,
  return_surface = FALSE,
  unmatched_supply_policy = c("error", "drop")
)
```

## Arguments

- grid:

  Output of \[build_e2sfca_raster_grid\] (shared across subspecialties
  of the same year).

- iso:

  \`sf\` isochrones (\`coord_id\`, \`drive_time_minutes\`, geometry) —
  any CRS; re-projected internally — OR a prepared context from
  \[prepare_e2sfca_iso\] (hoist the transform/validate out of the cell
  loop).

- supply:

  tibble from \[compute_provider_supply\] (\`coord_id\`,\`supply\`).

- weights:

  Cumulative-band weights (see \[e2sfca_band_weights\]).

- step2_power:

  Exponent applied to the step-2 demand weights (default 1, the standard
  E2SFCA). See \[compute_e2sfca\].

- per_capita_scale:

  Multiplier for the index (default 1e5).

- thresholds:

  Access thresholds (scaled units) for cell-level pop shares.

- return_surface:

  Logical. \`FALSE\` (default) returns summaries only; \`TRUE\`
  additionally returns the full accessibility \`SpatRaster\`, which is
  large – request it only when the surface itself is needed.

- unmatched_supply_policy:

  What to do when a \`supply\` origin appears in no isochrone band.
  \`"error"\` (default) fails closed, naming the origins and the share
  of supply they carry; \`"drop"\` warns and proceeds, declaring the
  loss explicitly. An origin with supply but no catchment contributes
  nothing to the surface, so silently dropping it depresses every
  downstream mean – observed at 0.786% when 5 of 516 origins lacked
  isochrones.

## Value

list(access, provider_ratios, weights, national). \`access\` carries
BOTH \`access_mean_area\` (area-weighted, secondary) and
\`access_mean_population\` (population-weighted, the authoritative tract
value). \`national\` holds the cell-level authoritative headline
summaries from \[e2sfca_cell_summaries\] — the sole source for headline
estimates.

## References

Raster realization of the same Luo & Wang (2003) \[source 1\] / Luo & Qi
(2009) \[source 2\] two-step method as \[compute_e2sfca\], on the
mass-conserving grid of \[allocate_pop_areaweighted\] (Apparicio 2017
\[source 7\]); \`step2_power\` selects M2SFCA (Delamater 2013 \[source
3\]); the national block adds SPAR (Wan 2012 \[source 4\]). This is the
PRODUCTION path used for the manuscript
(docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md, engine = raster).

## See also

\[build_e2sfca_raster_grid\], \[prepare_e2sfca_iso\],
\[compute_provider_supply\], \[e2sfca_cell_summaries\]

Other E2SFCA computation:
[`compute_band_tract_overlap()`](https://mufflyt.github.io/twostep/reference/compute_band_tract_overlap.md),
[`compute_e2sfca()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca.md),
[`compute_provider_supply()`](https://mufflyt.github.io/twostep/reference/compute_provider_supply.md),
[`e2sfca_cell_summaries()`](https://mufflyt.github.io/twostep/reference/e2sfca_cell_summaries.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# End-to-end for one (subspecialty, year) cell (production = raster engine):
grid   <- build_e2sfca_raster_grid(tracts_pop_sf, pop_col = "female_pop")  # once per year
iso_p  <- prepare_e2sfca_iso(isochrones_sf)                                 # hoist transform
supply <- compute_provider_supply(year_coord_map, cohort, "GO", year = 2020)
res    <- compute_e2sfca_raster(grid, iso_p, supply,
                                weights = E2SFCA_DEFAULT_WEIGHTS, step2_power = 1)
res$national$mean_population_weighted   # the authoritative headline number
res$access$relative_access              # per-tract SPAR (national mean = 1.00)
} # }
```
