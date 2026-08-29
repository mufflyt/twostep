# Build the per-year raster grid context reused across all subspecialties.

Rasterizes tract population once so the 7 subspecialty cells of a given
year share it. Returns a terra SpatRaster of per-cell population plus
the tract sf (for the Step-2 zonal mean) and metadata.

## Usage

``` r
build_e2sfca_raster_grid(
  tracts_pop_sf,
  pop_col = "female_pop",
  area_crs = E2SFCA_AREA_CRS,
  resolution = 250
)
```

## Arguments

- tracts_pop_sf:

  \`sf\` with \`GEOID\`, a population column, and polygon geometry (one
  year's tracts).

- pop_col:

  Population column name (default "female_pop").

- area_crs:

  Equal-area EPSG (default \[E2SFCA_AREA_CRS\], 5070).

- resolution:

  Cell size in metres (default 250, matching Step 4).

## Value

list(pop_rast, tracts, template, pop_col, resolution).

## See also

Other E2SFCA raster grid:
[`allocate_pop_areaweighted()`](https://mufflyt.github.io/twostep/reference/allocate_pop_areaweighted.md),
[`attach_e2sfca_population()`](https://mufflyt.github.io/twostep/reference/attach_e2sfca_population.md),
[`build_e2sfca_grid_geometry()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_grid_geometry.md),
[`prepare_e2sfca_iso()`](https://mufflyt.github.io/twostep/reference/prepare_e2sfca_iso.md)
