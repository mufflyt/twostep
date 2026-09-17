# Measuring geographic access with E2SFCA

This vignette builds a four-tract, two-provider example small enough to
check by hand, and walks it through the same functions the national
analysis uses. Every number below is computed, not quoted, so if the
engine changes the vignette changes with it.

It uses no external data. The national surfaces depend on road-network
isochrones and ACS extracts that cannot ship in a package; the
arithmetic does not, and the arithmetic is what most people need to
understand first.

``` r
library(twostep)
```

## What the two steps are

Accessibility here is a **supply-to-demand ratio, smeared over a
catchment**.

**Step 1** — for each provider *j*, add up the population that can reach
it, weighting nearer people more heavily, and divide that provider’s
capacity by the total:

$$R_{j} = \frac{S_{j}}{\sum\limits_{i}w_{ij}\, P_{i}}$$

**Step 2** — for each tract *i*, add up the ratios of every provider *i*
can reach, with the same weights:

$$A_{i} = \sum\limits_{j}w_{ij}\, R_{j}$$

The weights $w_{ij}$ come from drive-time bands: someone 20 minutes away
counts more than someone 100 minutes away. That is the “enhanced” part —
the original two-step method treated everyone inside the catchment
identically.

## Band weights, and why they are subtracted

Isochrone bands are **nested**: the 60-minute polygon contains the
30-minute polygon. So the published weights are *cumulative*, and using
them directly would count the innermost population once per band it
falls inside.

[`e2sfca_incremental_weights()`](https://mufflyt.github.io/twostep/reference/e2sfca_incremental_weights.md)
performs the Abel summation that fixes this — each ring gets the
difference between its own weight and the next one out:

``` r
W_cumulative <- c(`30` = 1.00, `60` = 0.68, `120` = 0.22, `180` = 0.09)
W_incremental <- e2sfca_incremental_weights(W_cumulative)
W_incremental
#>   30   60  120  180 
#> 0.32 0.46 0.13 0.09
```

The outermost band keeps its cumulative weight, and the increments sum
back to the innermost cumulative weight — every ring counted exactly
once:

``` r
sum(W_incremental)
#> [1] 1
identical(unname(sum(W_incremental)), unname(W_cumulative[["30"]]))
#> [1] TRUE
```

Get this wrong and accessibility is overstated everywhere, in a way that
looks entirely plausible. It is the single easiest place to introduce a
believable error, which is why the test suite pins it from several
directions.

## A worked example

Four tracts, two providers. Tract populations and which band each tract
falls into for each provider:

``` r
# `pop_col` defaults to "female_pop", the denominator the study uses.
tract_pop <- data.frame(
  GEOID      = c("T1", "T2", "T3", "T4"),
  female_pop = c(1000, 2000, 1500, 500),
  stringsAsFactors = FALSE
)

# One row per (tract, provider, band). Nested bands: a tract in the 30-minute
# ring is also inside the 60-minute polygon, but appears once, at its tightest.
overlap <- data.frame(
  GEOID    = c("T1", "T2", "T3", "T4", "T2", "T3"),
  coord_id = c("P1", "P1", "P1", "P2", "P2", "P2"),
  band     = c(30L,  60L,  120L, 30L,  120L, 60L),
  # What fraction of the tract lies in that band. 1 = wholly inside.
  overlap_fraction = 1,
  stringsAsFactors = FALSE
)

supply <- data.frame(
  coord_id = c("P1", "P2"),
  supply   = c(4, 6),
  stringsAsFactors = FALSE
)
```

Step 1 by hand for provider P1: its weighted demand is
`1000 x 0.32 + 2000 x 0.46 + 1500 x 0.13`, and its ratio is `4` divided
by that.

``` r
w <- W_incremental
demand_P1 <- 1000 * w[["30"]] + 2000 * w[["60"]] + 1500 * w[["120"]]
demand_P1
#> [1] 1435
4 / demand_P1
#> [1] 0.002787456
```

Now the engine. Note it takes the **cumulative** weights and derives the
increments itself, so the correction above cannot be skipped by
accident:

``` r
res <- compute_e2sfca(
  overlap   = overlap,
  tract_pop = tract_pop,
  supply    = supply,
  weights   = W_cumulative
)
res$access[, c("GEOID", "access", "access_math", "reached")]
#>   GEOID       access  access_math reached
#> 1    T1 0.0008919861 0.0008919861    TRUE
#> 2    T2 0.0019849327 0.0019849327    TRUE
#> 3    T3 0.0028488558 0.0028488558    TRUE
#> 4    T4 0.0017297297 0.0017297297    TRUE
```

## The conservation identity

The property worth internalising: **total supply is conserved**. Summing
each tract’s accessibility, weighted by its population, returns total
capacity — accessibility redistributes supply across space, it does not
create or destroy it:

$$\sum\limits_{i}P_{i}A_{i} = \sum\limits_{j}S_{j}$$

This is the strongest single check on an accessibility surface. A result
that violates it is wrong no matter how plausible the map looks.

``` r
pop <- tract_pop$female_pop[match(res$access$GEOID, tract_pop$GEOID)]
c(redistributed = sum(pop * res$access$access_math),
  total_supply  = sum(supply$supply))
#> redistributed  total_supply 
#>            10            10
```

Those two agree exactly. Every tract with positive demand contributes;
the identity holds over providers reachable by someone. Tracts outside
every catchment are a separate matter, and the distinction is deliberate
— see below.

## Unmeasured is not zero

A tract outside every modelled catchment has **no measurement**, which
is not the same as measured zero access. Reporting the two identically
would let missing data masquerade as a finding.

[`compute_e2sfca()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca.md)
therefore returns both:

- `access` is `NA` for tracts no provider reaches
- `access_math` is the zero-filled algebraic form, for sums and
  identities

Feed `access` to anything that averages and unreached tracts drop out;
feed `access_math` and they count as zero. Which you want depends on the
question, and the package refuses to choose for you.

## Missing data fails closed

The package will not silently repair an ambiguous join. If a tract has
no population row, or a population of `NA`, that is an error rather than
a zero:

``` r
tract_pop_gap <- tract_pop
tract_pop_gap$female_pop[tract_pop_gap$GEOID == "T3"] <- NA

compute_e2sfca(
  overlap   = overlap,
  tract_pop = tract_pop_gap,
  supply    = supply,
  weights   = W_cumulative
)
#> Error:
#> ! compute_e2sfca: 1 tract(s) have NA in population column 'female_pop' (T3). NA is UNKNOWN population, not zero: coercing it to zero would drop those people from the Step 1 denominator and inflate accessibility. Fix the upstream join, or pass na_pop_policy = "zero" to declare an explicit, documented imputation.
```

The reasoning is directional and worth stating plainly. Coercing unknown
population to zero removes people from the Step 1 denominator, which
**inflates** accessibility — the direction that makes a study look
better than its data supports. If an imputation is genuinely intended it
can be requested by name:

``` r
compute_e2sfca(
  overlap       = overlap,
  tract_pop     = tract_pop_gap,
  supply        = supply,
  weights       = W_cumulative,
  na_pop_policy = "zero"   # explicit, documented imputation
)
```

The same rule governs unmatched tracts, unmatched providers, and
duplicate keys throughout: **no silent loss, no silent multiplication,
no silent zeroing.** Duplicate keys are refused because a lookup would
otherwise keep one row and discard the rest, making the answer depend on
row order. A duplicated supply row was once found to *double* a tract’s
accessibility.

## Where to go next

| topic                              | see                                                                                                                                                                                                          |
|------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| the desjardins7 tract-level engine | [`?dj7_tract_access`](https://mufflyt.github.io/twostep/reference/dj7_tract_access.md)                                                                                                                       |
| the raster/grid path               | [`?build_e2sfca_grid_geometry`](https://mufflyt.github.io/twostep/reference/build_e2sfca_grid_geometry.md), [`?compute_e2sfca_raster`](https://mufflyt.github.io/twostep/reference/compute_e2sfca_raster.md) |
| mass-conserving demand allocation  | [`?allocate_pop_areaweighted`](https://mufflyt.github.io/twostep/reference/allocate_pop_areaweighted.md)                                                                                                     |
| how figures and data were produced | `docs/FIGURE_PROVENANCE.md`                                                                                                                                                                                  |

The published parameterisation, the sensitivity specifications, and the
national results are in the manuscript, which reproduces from the frozen
run.
