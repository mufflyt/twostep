# Convert cumulative-band weights W_b into incremental weights for step 1 or 2.

See the module header for the Abel-summation identity that makes
cumulative bands + incremental weights equivalent to ring-based
(E2)SFCA. With \`step2_power = 1\` (the default, and always the STEP-1
demand denominator) this returns the ordinary E2SFCA increments \`w'\_b
= W_b - W\_\[b+1\]\`. With \`step2_power = 2\` it returns the M2SFCA
(Delamater 2013) STEP-2 access increments derived from the SQUARED
cumulative weights, \`w”\_b = W_b^2 - W\_\[b+1\]^2\` (this is
\`diff(W^2)\`, NOT \`diff(W)^2\`), so the access step applies the
distance penalty a second time and a suboptimally configured system
shows lower access. The outermost band's increment is its own (possibly
powered) weight (W beyond the last band is 0).

## Usage

``` r
e2sfca_incremental_weights(weights = E2SFCA_DEFAULT_WEIGHTS, step2_power = 1)
```

## Arguments

- weights:

  Named cumulative-band weights (see \[e2sfca_band_weights\]).

- step2_power:

  Exponent applied to the CUMULATIVE weights before differencing: 1 =
  E2SFCA, 2 = M2SFCA. Must be \>= 1. For power \> 1 every cumulative
  weight must be \<= 1 (else squaring would INCREASE access).

## Value

Named numeric vector of incremental weights, same names/order.

## References

The cumulative-band + incremental-weight identity is the
Abel/summation-by-parts reformulation of the ring-based E2SFCA of Luo &
Qi (2009) \[source 2\] (see module header). step2_power = 2 implements
the M2SFCA penalty of Delamater (2013)
doi:10.1016/j.healthplace.2013.07.012 \[source 3\]: the
squared-cumulative difference diff(W^2), applied in STEP 2 ONLY.
Analytic fixtures pinning both cases live in
tests/testthat/test-e2sfca-m2sfca-gaussian.R.

## See also

\[e2sfca_band_weights\], \[compute_e2sfca\]

Other E2SFCA distance-decay weights:
[`e2sfca_band_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_band_weights.md),
[`gaussian_band_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_band_weights.md),
[`gaussian_decay_weights()`](https://mufflyt.github.io/twostep/reference/gaussian_decay_weights.md)

## Examples

``` r
# E2SFCA (step2_power = 1): plain incremental weights W_b - W_[b+1]
e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 1)  # 0.5 0.5
#>  30  60 
#> 0.5 0.5 
# M2SFCA (step2_power = 2): diff of SQUARED cumulative weights, W^2_b - W^2_[b+1]
e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 2)  # 0.75 0.25
#>   30   60 
#> 0.75 0.25 
```
