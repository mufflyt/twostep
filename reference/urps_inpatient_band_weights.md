# E2SFCA band weights for urogynaecologic inpatient surgery

Wraps \[gaussian_band_weights\] with the CHIA-calibrated bandwidth.
Returns a monotone vector that passes \[e2sfca_band_weights\], unlike
the raw empirical kernel, which is non-monotone (women bypass nearer
hospitals for higher-volume ones) and would produce a negative
incremental weight.

## Usage

``` r
urps_inpatient_band_weights(
  bands = c(30L, 60L, 120L, 180L),
  sigma_minutes = URPS_INPATIENT_SIGMA_MINUTES
)
```

## Arguments

- bands:

  Band edges in minutes, as for \[gaussian_band_weights\].

- sigma_minutes:

  Calibrated bandwidth in minutes; defaults to the
  road-network-calibrated \[URPS_INPATIENT_SIGMA_MINUTES\] (41).

## Value

Named numeric vector of normalised zonal weights.

## Examples

``` r
urps_inpatient_band_weights()   # 1.000 0.448 0.018 0.000  (sigma = 41 min)
#>           30           60          120          180 
#> 1.000000e+00 4.479412e-01 1.803453e-02 8.529259e-05 
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
#> [1] 41
#> 
#> attr(,"decay_meta")$maximum_minutes
#> [1] 180
#> 
#> attr(,"decay_meta")$sigma_source
#> [1] "CHIA MA inpatient urogyn surgery, FY2007-2018"
#> 
#> attr(,"decay_meta")$sigma_miles
#> [1] 22.7
#> 
#> attr(,"decay_meta")$minutes_calibration
#> [1] "MA road-network isochrones, FPMRS/urology"
#> 
#> attr(,"decay_meta")$calibration_tier
#> [1] "observed_regional"
#> 
gaussian_band_weights()         # 1.000 0.687 0.153 0.013  (sigma = 60 min)
#>         30         60        120        180 
#> 1.00000000 0.68728928 0.15335497 0.01258814 
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
```
