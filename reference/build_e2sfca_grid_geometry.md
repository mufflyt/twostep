# Year-agnostic half of the raster grid: rasterize tract geometry once.

Tract boundaries change only at the 2010-\>2020 vintage break, so this
(expensive) rasterization is computed once per vintage and reused across
all its years via \[attach_e2sfca_population\].

## Usage

``` r
build_e2sfca_grid_geometry(
  tracts_geom_sf,
  area_crs = E2SFCA_AREA_CRS,
  resolution = 250,
  template = NULL
)
```

## Arguments

- tracts_geom_sf:

  \`sf\` with \`GEOID\` + polygon geometry.

- area_crs:

  Equal-area EPSG (default \[E2SFCA_AREA_CRS\]).

- resolution:

  Cell size in metres.

- template:

  Optional existing \`SpatRaster\` to rasterize onto. \`NULL\` (default)
  builds a fresh template from \`tracts_geom_sf\` at \`resolution\`;
  pass one to force an identical grid across vintages.

## Value

list(template, tracts (with \`.tid\`,\`.ncell\`), area_crs, resolution).

## See also

\[allocate_pop_areaweighted\]

Other E2SFCA raster grid:
[`allocate_pop_areaweighted()`](https://mufflyt.github.io/twostep/reference/allocate_pop_areaweighted.md),
[`attach_e2sfca_population()`](https://mufflyt.github.io/twostep/reference/attach_e2sfca_population.md),
[`build_e2sfca_raster_grid()`](https://mufflyt.github.io/twostep/reference/build_e2sfca_raster_grid.md),
[`prepare_e2sfca_iso()`](https://mufflyt.github.io/twostep/reference/prepare_e2sfca_iso.md)
