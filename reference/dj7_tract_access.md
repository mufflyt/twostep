# Tract-level E2SFCA accessibility from per-band tract membership.

Reproduces the demand/supply/access recurrence of \`run_e2sfca()\`
(script 06) with base R so it is exercisable against hand-computed
fixtures:

1.  demand \\D_j = \sum_b w'\_b \cdot \mathrm{cumpop}\_b(j)\\ where
    \\\mathrm{cumpop}\_b(j)\\ is the population of tracts whose centroid
    falls in origin j's band-b (nested) isochrone;

2.  supply-to-demand ratio \\R_j = S_j / \max(D_j, \epsilon)\\,
    non-finite set to 0 (so a zero-demand origin contributes nothing);

3.  access \\A_i = \sum\_{j \ni i} W\_{b^\*(i,j)} R_j\\ where \\b^\*\\
    is the tightest band reaching tract i from origin j (max cumulative
    weight across the bands in which the (i,j) pair appears).

A tract reached by no positive-supply origin gets \\A_i = 0\\ — the
zero-access set, which is purely geometric (independent of the demand
denominator and of the particular positive band weights).

## Usage

``` r
dj7_tract_access(membership, supply, dvec, Wc = DJ7_WC_BASE)
```

## Arguments

- membership:

  named list keyed by band ("30","60","120","180"); each element a
  data.frame with columns \`coord_id\`, \`GEOID\` (one row per
  origin-tract pair whose centroid is inside that band). Bands are
  nested.

- supply:

  named numeric vector supply\[coord_id\] = provider supply.

- dvec:

  named numeric vector dvec\[GEOID\] = demand population.

- Wc:

  length-4 cumulative band weights (default \[DJ7_WC_BASE\]).

## Value

data.frame(GEOID, A) for every reached tract (A \> 0 unless the reaching
origins all have zero supply).
