# Whether a recovered physician re-enters the accessibility surface.

Reproduces script 08's \`in_surface_5km \<- nearest_origin_km \<= 5\`: a
recovered location within (inclusive) the 5-km DBSCAN cluster radius of
an existing isochrone origin reuses that origin's catchment. The
boundary is INCLUSIVE (exactly \`radius_km\` is in-surface). NA distance
-\> FALSE.

## Usage

``` r
dj7_in_surface(nearest_origin_km, radius_km = 5)
```

## Arguments

- nearest_origin_km:

  numeric distance to the nearest origin (km).

- radius_km:

  inclusive cluster radius (default 5, per CLAUDE.md \#17).

## Value

logical.
