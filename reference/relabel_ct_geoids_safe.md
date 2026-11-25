# Geometry-safe Connecticut planning-region to legacy county GEOID relabel

Relabels 2022+ ACS Connecticut planning-region tract GEOIDs
(09110-09190) to the legacy county GEOIDs (09001-09015) used by the
isochrone overlap lineage and the 2020 native tract boundaries, so that
GEOID joins across the 2022 vocabulary break do not silently drop the
entire state.

## Usage

``` r
relabel_ct_geoids_safe(x, census_year, path = ct_equivalency_table_path())
```

## Arguments

- x:

  \`sf\` or \`data.frame\` carrying a character \`GEOID\` column (ACS
  data). Returned unchanged when it is \`NULL\` or has no \`GEOID\`.

- census_year:

  \`integer\` ACS end-year. No-op below 2022.

- path:

  Equivalency table path. Defaults to \[ct_equivalency_table_path()\].

## Value

\`x\` with Connecticut planning-region GEOIDs relabeled to legacy county
GEOIDs. Geometry and row order are preserved.

## Details

No-op for \`census_year \< 2022\`, and idempotent: a second pass sees
only legacy GEOIDs and changes nothing. Fail-closed on a missing
equivalency table or an unmapped planning-region GEOID.

## Examples

``` r
df <- data.frame(GEOID = c("09190010101", "25025010100"))
# 2021 is before the break, so this is a no-op:
relabel_ct_geoids_safe(df, 2021)$GEOID
#> [1] "09190010101" "25025010100"
```
