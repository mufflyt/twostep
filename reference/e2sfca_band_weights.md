# Validate and return E2SFCA cumulative-band weights.

Validate and return E2SFCA cumulative-band weights.

## Usage

``` r
e2sfca_band_weights(weights = E2SFCA_DEFAULT_WEIGHTS)
```

## Arguments

- weights:

  Named numeric vector keyed by band-in-minutes. Defaults to
  \[E2SFCA_DEFAULT_WEIGHTS\]. Must be non-negative and (weakly) monotone
  decreasing in band, so incremental weights are non-negative.

## Value

The validated named numeric vector, sorted by ascending band.

## References

Luo & Qi (2009) doi:10.1016/j.healthplace.2009.06.002 \[source 2\]: the
monotone-decreasing zonal weights are what make E2SFCA "enhanced" over
the flat 2SFCA of Luo & Wang (2003) \[source 1\].

## See also

\[gaussian_band_weights\], \[e2sfca_incremental_weights\]

Other E2SFCA distance-decay weights:
[`e2sfca_incremental_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_incremental_weights.md),
[`gaussian_band_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_band_weights.md),
[`gaussian_decay_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_decay_weights.md)

## Examples

``` r
# No argument uses [E2SFCA_DEFAULT_WEIGHTS], the production weights. It is the
# authoritative SSOT but is not exported, so the example calls the default
# rather than naming it -- and rather than restating the literal, which the
# SSOT guards in tests/testthat/test-ssot-band-weights.R forbid duplicating.
e2sfca_band_weights()
#>   30   60  120  180 
#> 1.00 0.68 0.22 0.09 
e2sfca_band_weights(c("30" = 1, "60" = 0.5, "120" = 0.2, "180" = 0.1))
#>  30  60 120 180 
#> 1.0 0.5 0.2 0.1 
try(e2sfca_band_weights(c("30" = 0.5, "60" = 1)))       # errors: not monotone
#> Error : e2sfca_band_weights: weights must be monotone non-increasing in band (else a farther band would count MORE than a nearer one, and an incremental weight would be negative).
```
