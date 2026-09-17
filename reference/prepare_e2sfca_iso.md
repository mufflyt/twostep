# Prepare isochrones for the raster engine ONCE (hoist out of the cell loop).

The transform to the equal-area CRS and \`st_make_valid\` over thousands
of large isochrone polygons is the single most expensive per-call step;
running it once here instead of inside every \[compute_e2sfca_raster\]
call turns an O(cells x polygons) cost into O(polygons).

## Usage

``` r
prepare_e2sfca_iso(iso_sf, area_crs = E2SFCA_AREA_CRS)
```

## Arguments

- iso_sf:

  \`sf\` with \`coord_id\`, \`drive_time_minutes\`, polygon geometry.

- area_crs:

  Equal-area EPSG (default \[E2SFCA_AREA_CRS\]).

## Value

list(bands = named list of per-band \`sf\` (\`coord_id\`, geometry),
area_crs). Pass this as the \`iso\` argument to
\[compute_e2sfca_raster\].

## See also

\[compute_e2sfca_raster\]

Other E2SFCA raster grid:
[`allocate_pop_areaweighted()`](https://mufflyt.github.io/twostep/reference/allocate_pop_areaweighted.md),
[`attach_e2sfca_population()`](https://mufflyt.github.io/twostep/reference/attach_e2sfca_population.md),
[`build_e2sfca_grid_geometry()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_grid_geometry.md),
[`build_e2sfca_raster_grid()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_raster_grid.md)
