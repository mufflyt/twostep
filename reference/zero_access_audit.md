# Population-weighted zero-access coverage audit

Returns the full population accounting behind a zero-access share, never
a bare number, so the denominator can be inspected rather than trusted.

## Usage

``` r
zero_access_audit(surf_scaled, wrast, tol_unresolved = 0)
```

## Arguments

- surf_scaled:

  \`SpatRaster\` accessibility surface.

- wrast:

  \`SpatRaster\` population weights (the eligible denominator).

- tol_unresolved:

  Maximum population permitted to have no evaluable accessibility before
  the share is withheld. Default \`0\`: nothing unresolved. A non-zero
  value is an explicit, documented decision to report a share over an
  incomplete denominator.

## Value

A list with \`eligible_population\`, \`evaluable_population\`,
\`zero_access_population\`, \`excluded_population\`,
\`unresolved_population\`, \`pct_evaluable\` and \`zero_share\`
(percent, over EVALUABLE population; \`NA\` when unresolved population
exceeds \`tol_unresolved\`).

## Why \`NA\` is not zero access

\[compute_e2sfca_raster\] builds the surface DENSELY: it initialises
every cell to \`0\` and accumulates rasterized band contributions with
\`background = 0\`. Every cell therefore carries a computed value, and a
cell outside every catchment holds an \*explicit\* zero. Verified on a
fixture in which three of four tracts lie outside all catchments: 665
cells, zero \`NA\` in the surface, zero \`NA\` in the population raster,
393 populated cells at exactly \`0\`.

The surface is not sparse. An \`NA\` therefore does \*\*not\*\* mean "no
provider reachable" – it means something upstream is incomplete: a
partial surface, a template/population mismatch, a failed routing input.
Counting it as zero access would inflate the reported share using
missing data, which is the conflation this package refuses everywhere
else: an explicit zero is a measurement, a missing value is not.

## See also

\[zshare_rast\]

Other zero access:
[`zshare_rast()`](https://mufflyt.github.io/twostep/reference/zshare_rast.md)
