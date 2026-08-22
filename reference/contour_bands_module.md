# Canonical Drive-Time Contour Bands (SHIM: live from mufflyaccess)

The SHARED band SSOTs – \`CANONICAL_BANDS\`, \`get_canonical_bands()\`,
\`PRIMARY_ACCESS_BAND_MIN\`, \`PRIMARY_ACCESS_BAND_SEC\`,
\`get_primary_access_band()\` – are sourced live from the shared
mufflyaccess package (now public + pinned in renv.lock), the single
source of truth across isochrones / twostep / cliff, so cross-repo drift
is impossible. Guarded by tests/testthat/test-ssot-access-constants.R.
This file also keeps the twostep-specific active-band pieces
(\`ACTIVE_BANDS_FALLBACK\`, \`get_active_bands()\`) that read
\`config/isochrone_config.yaml\` and are NOT in the package.

## Usage

``` r
CANONICAL_BANDS

PRIMARY_ACCESS_BAND_MIN

PRIMARY_ACCESS_BAND_SEC
```

## See also

Other contour-bands:
[`get_active_bands()`](https://mufflyt.github.io/twostep/reference/get_active_bands.md)
