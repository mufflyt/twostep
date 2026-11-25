# Population-weighted zero-access share, failing closed

The share of population with no reachable provider, as a percentage of
EVALUABLE population. Errors – naming the population involved – when any
population has no evaluable accessibility, rather than returning a
plausible number computed over a silently shrunken denominator.

The share is population-weighted, not tract- or cell-counted: two of
four cells may be zero-access while holding a tenth of the people.

## Usage

``` r
zshare_rast(surf_scaled, wrast, tol_unresolved = 0)
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

Percent in \`\[0, 100\]\`.

## See also

\[zero_access_audit\]

Other zero access:
[`zero_access_audit()`](https://mufflyt.github.io/twostep/reference/zero_access_audit.md)
