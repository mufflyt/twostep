# Gaussian-DERIVED zonal band weights (a four-band approximation, NOT continuous).

This engine has only four nested travel-time polygons (30/60/120/180
min) and rasterizes one constant contribution per band, so it is a ZONAL
method. This helper derives the four zonal band weights from a Gaussian
decay evaluated at each band's OUTER edge; it does NOT implement a
continuous distance function (that would need a per provider-to-cell
travel time or much finer contours).

## Usage

``` r
gaussian_band_weights(bands = c(30L, 60L, 120L, 180L), sigma = 60)
```

## Arguments

- bands:

  Integer band outer edges in minutes (default 30/60/120/180).

- sigma:

  Gaussian bandwidth in minutes, strictly positive (default 60).

## Value

Named cumulative-band weights (monotone non-increasing), W_1 == 1.

## Details

Equation and parameterization (reproducible): raw_b = exp( - d_b^2 / (2
\* sigma^2) ) d_b = band outer edge in minutes W_b = raw_b / raw_1
(normalized so the nearest band = 1) with sigma the Gaussian bandwidth
in minutes. Travel times beyond the last band receive weight 0 (the
incremental convention; see \[e2sfca_incremental_weights\]).

## References

McGrail (2012) doi:10.1186/1476-072X-11-50 \[source 5\] on decay-
function choice; normalization to the inner band follows the zonal
E2SFCA convention of Luo & Qi (2009) \[source 2\]. Used only by the
\`gaussian\` sensitivity variant in scripts/sensitivity_e2sfca_2020.R.

## See also

\[gaussian_decay_weights\] (the raw kernel this normalizes)

Other E2SFCA distance-decay weights:
[`e2sfca_band_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_band_weights.md),
[`e2sfca_incremental_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_incremental_weights.md),
[`gaussian_decay_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_decay_weights.md)

## Examples

``` r
round(gaussian_band_weights(c(30, 60, 120, 180), sigma = 60), 4)
#>     30     60    120    180 
#> 1.0000 0.6873 0.1534 0.0126 
#> attr(,"decay_meta")
#> attr(,"decay_meta")$decay_function
#> [1] "gaussian"
#> 
#> attr(,"decay_meta")$decay_type
#> [1] "zonal"
#> 
#> attr(,"decay_meta")$normalization
#> [1] "first_band"
#> 
#> attr(,"decay_meta")$normalization_minutes
#> [1] 30
#> 
#> attr(,"decay_meta")$sigma_minutes
#> [1] 60
#> 
#> attr(,"decay_meta")$maximum_minutes
#> [1] 180
#> 
# 30=1.0000 60=0.6873 120=0.1534 180=0.0126 : normalized to the 30-min band
attr(gaussian_band_weights(), "decay_meta")$sigma_minutes   # 60
#> [1] 60
```
