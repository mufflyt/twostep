# Compute tract x cumulative-band overlap fractions (the geometry step).

For every (provider origin \`coord_id\`, band, tract \`GEOID\`) this
returns the fraction of the TRACT's area that falls within the
provider's cumulative isochrone for that band. This is the only
geometry-heavy operation and it is YEAR-AGNOSTIC (isochrone geometry
does not change year to year; only the active-provider set and tract
population do). Compute it once per tract vintage and reuse across
years.

## Usage

``` r
compute_band_tract_overlap(
  iso_sf,
  tracts_sf,
  area_crs = E2SFCA_AREA_CRS,
  chunk_by_state = TRUE,
  verbose = TRUE
)
```

## Arguments

- iso_sf:

  \`sf\` of provider isochrones with columns \`coord_id\`,
  \`drive_time_minutes\` (band, one of 30/60/120/180) and polygon
  \`geometry\`. Cumulative bands (the project's consolidated artifacts).
  Any CRS.

- tracts_sf:

  \`sf\` of census tracts with column \`GEOID\` and polygon
  \`geometry\`. Any CRS.

- area_crs:

  EPSG code for the equal-area projection used for all area math.
  Default \[E2SFCA_AREA_CRS\] (5070).

- chunk_by_state:

  Logical (default TRUE). Process tracts in per-state chunks so a
  national \`st_intersection\` never materializes all intersecting pairs
  at once. Results are identical either way; only peak memory changes.
  Set FALSE for small inputs where the overhead isn't worth it.

- verbose:

  Logical; print progress.

## Value

tibble with columns \`coord_id\`, \`band\` (int minutes), \`GEOID\`,
\`overlap_fraction\` (area of tract within the cumulative band / tract
area, in \`\[0, 1\]\`). Only positive-overlap rows are returned.

## See also

\[compute_e2sfca\], \[compute_e2sfca_raster\]

Other E2SFCA computation:
[`compute_e2sfca()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca.md),
[`compute_e2sfca_raster()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca_raster.md),
[`compute_provider_supply()`](https://mufflyt.github.io/twostep/reference/compute_provider_supply.md),
[`e2sfca_cell_summaries()`](https://mufflyt.github.io/twostep/reference/e2sfca_cell_summaries.md)
