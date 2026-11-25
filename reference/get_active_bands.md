# Return the currently active drive-time bands from config

Reads \`config/isochrone_config.yaml\` for the active band set, with a
three-strategy path resolver (here::here / PIPELINE_ROOT / getwd) so it
works in nested callr subprocesses. Falls back to
\[ACTIVE_BANDS_FALLBACK\] (NOT the package's \`CANONICAL_BANDS\`) to
avoid fingerprint mismatches.

## Usage

``` r
get_active_bands()
```

## Value

Integer vector of active drive-time thresholds in minutes.

## See also

\[ACTIVE_BANDS_FALLBACK\]

Other contour-bands:
[`contour_bands_module`](https://mufflyt.github.io/twostep/reference/contour_bands_module.md)
