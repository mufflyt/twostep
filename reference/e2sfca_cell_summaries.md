# Authoritative cell-level national summaries from the access surface.

Computes the national population-weighted mean access and the population
share at each access threshold DIRECTLY from the aligned cell grids —
never by recombining tract averages (which would not be
partition-robust). One explicit valid-cell mask governs every summary so
the denominator never silently changes between metrics.

## Usage

``` r
e2sfca_cell_summaries(
  surface,
  pop_rast,
  thresholds = E2SFCA_DEFAULT_THRESHOLDS,
  scale = 1e+05
)
```

## Arguments

- surface:

  terra SpatRaster of access values S_c (raw ratio units).

- pop_rast:

  terra SpatRaster of per-cell population p_c (same support).

- thresholds:

  Numeric thresholds in the SCALED units (per \`scale\`).

- scale:

  Multiplier applied to S_c before thresholding / reporting (default 1e5
  -\> per-100k).

## Value

list with the mask accounting, national pop-weighted mean (raw and
scaled), and a \`threshold_shares\` tibble.

## Details

Valid cell = finite access AND finite, non-negative population, on
matching raster support. Excluded population (missing access, or
missing/negative population) is reported, not silently dropped.

## References

The population-weighted national mean is the standardized supply-
per-population index of Wang & Luo (2005)
doi:10.1016/j.healthplace.2004.02.003 \[source 6\]. Dividing each cell's
access by this mean yields the Spatial Access Ratio (SPAR) of Wan, Zhan,
Zou & Chow (2012) doi:10.1016/j.apgeog.2011.05.001 \[source 4\]
(national mean == 1.00 by construction), attached downstream as
\`relative_access\`.

## See also

\[compute_e2sfca_raster\]

Other E2SFCA computation:
[`compute_band_tract_overlap()`](https://mufflyt.github.io/twostep/reference/compute_band_tract_overlap.md),
[`compute_e2sfca()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca.md),
[`compute_e2sfca_raster()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca_raster.md),
[`compute_provider_supply()`](https://mufflyt.github.io/twostep/reference/compute_provider_supply.md)
