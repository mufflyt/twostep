# RAW continuous Gaussian decay kernel G(d) = exp(-d^2 / (2 sigma^2)).

The un-normalized kernel: G(0) = 1 and G decreases monotonically. This
is the continuous decay function; it is NOT the zonal band weights
(which normalize to the inner band, see \[gaussian_band_weights\]). A
genuinely continuous E2SFCA would apply this to a per provider-to-cell
travel time. Do NOT normalize this to the 30-min value: distances \< 30
min would then exceed 1.

## Usage

``` r
gaussian_decay_weights(minutes, sigma = 60)
```

## Arguments

- minutes:

  Numeric travel times in minutes (\>= 0).

- sigma:

  Gaussian bandwidth in minutes, strictly positive.

## Value

Named numeric vector G(minutes) in (0, 1\], names = the minutes.

## References

Gaussian decay as a 2SFCA impedance function: McGrail & Humphreys (2009)
doi:10.1016/j.apgeog.2008.12.003 and McGrail (2012)
doi:10.1186/1476-072X-11-50 \[source 5\]; the Gaussian form also appears
in Luo & Qi (2009) \[source 2\] as one of the tested decay weights.

## See also

\[gaussian_band_weights\] (the normalized zonal wrapper actually used)

Other E2SFCA distance-decay weights:
[`e2sfca_band_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_band_weights.md),
[`e2sfca_incremental_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_incremental_weights.md),
[`gaussian_band_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_band_weights.md)

## Examples

``` r
gaussian_decay_weights(c(0, 30, 60, 120), sigma = 60)
#>         0        30        60       120 
#> 1.0000000 0.8824969 0.6065307 0.1353353 
# G(0) = 1, then 0.882, 0.607, 0.135 : the RAW kernel, not normalized to band 1
```
