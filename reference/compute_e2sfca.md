# Core E2SFCA computation for one (subspecialty, year) cell.

Given the year-agnostic overlap table, the year's tract population, and
the cell's provider supply, compute: Step 1 — provider-to-population
ratio R_j = S_j / Sum_b w'\_b \* CumPop_jb Step 2 — tract accessibility
A_i = Sum_j Sum_b w'\_b \* R_j \* f_jbi where f_jbi = fraction of tract
i within provider j's cumulative band b, and w'\_b are incremental band
weights. (See module header for the ring equivalence.)

## Usage

``` r
compute_e2sfca(
  overlap,
  tract_pop,
  supply,
  weights = E2SFCA_DEFAULT_WEIGHTS,
  step2_power = 1,
  pop_col = "female_pop",
  per_capita_scale = 1e+05,
  na_pop_policy = c("error", "zero")
)
```

## Arguments

- overlap:

  tibble from \[compute_band_tract_overlap\] (\`coord_id\`,\`band\`,
  \`GEOID\`,\`overlap_fraction\`).

- tract_pop:

  tibble with \`GEOID\` and a population column for the year.

- supply:

  tibble from \[compute_provider_supply\] (\`coord_id\`,\`supply\`).

- weights:

  Cumulative-band weights (see \[e2sfca_band_weights\]).

- step2_power:

  Exponent applied to the step-2 demand weights (default 1, the standard
  E2SFCA). Values above 1 sharpen distance decay in the demand-side sum;
  this is the M2SFCA-style sensitivity lever.

- pop_col:

  Name of the population column in \`tract_pop\` (default "female_pop").

- per_capita_scale:

  Multiply the accessibility index by this (default 1e5 →
  "subspecialists per 100,000 women").

- na_pop_policy:

  What to do when \`pop_col\` contains \`NA\`. \`"error"\` (default)
  refuses: NA is UNKNOWN population, and silently treating it as zero
  removes those residents from the Step 1 denominator and INFLATES
  accessibility. \`"zero"\` opts into that imputation explicitly, and
  should be used only where an upstream policy documents why the value
  is genuinely zero rather than unknown. A tract carrying an explicit
  \`0\` is unaffected by this setting: that is a valid measurement, not
  a missing one.

## Value

list with: \* \`access\` — tibble(\`GEOID\`, \`access\`,
\`access_scaled\`, \`n_providers\`, \`access_math\`,
\`access_scaled_math\`, \`reached\`, \`coverage_status\`) per tract.
\`coverage_status\` is \`"within_modeled_catchment"\` or
\`"outside_all_modeled_catchments"\` and agrees exactly with
\`reached\`. \* \`provider_ratios\` —
tibble(\`coord_id\`,\`supply\`,\`weighted_demand\`,\`ratio\`). \*
\`weights\` — the incremental weights used. \* \`audit\` — includes
\`n_within_modeled_catchment\`, \`n_outside_all_modeled_catchments\` and
\`n_reached_scoring_zero\`.

## Zero versus outside the model

\`0\` means modelled accessibility was calculated as zero. \`NA\` means
the tract lies outside every modelled catchment. \*\*These are not
interchangeable.\*\*

A tract inside a catchment whose weighted supply works out to zero has a
measured accessibility of zero. A tract no isochrone reaches has none.
Before this distinction existed the second was filled with \`0\` and
became indistinguishable from the first — 190 of 1,447 Colorado tracts,
13% of the state, each reported as a measured zero and shaded in the
zero class of any downstream map.

Coverage is established from catchment membership (the overlap x
modelled-provider x weighted-band relationship), never inferred from the
score, the supply or the population. A reached tract scoring zero stays
\`reached = TRUE\`.

Two score columns are therefore returned:

- \`access\`, \`access_scaled\`:

  The scientific value. \`NA\` outside every catchment. This is what a
  reader, a table or a map should consume.

- \`access_math\`, \`access_scaled_math\`:

  The algebraic form, zero-filled. A tract outside every catchment
  contributes exactly zero to \\\sum_i P_i A_i\\, so conservation
  identities and any other accounting use this column. Do not reach for
  \`na.rm = TRUE\` on the scientific column instead — that silently
  changes the estimand.

## References

The two-step supply-ratio then demand-accumulation structure is Luo &
Wang (2003) doi:10.1068/b29120 \[source 1\]; the zonal decay in both
steps is Luo & Qi (2009) doi:10.1016/j.healthplace.2009.06.002 \[source
2\]. The \`step2_power\` argument selects E2SFCA (1) vs M2SFCA (2,
Delamater 2013 doi:10.1016/j.healthplace.2013.07.012 \[source 3\]).
Zero-weighted-demand providers yield ratio = NA (undefined), never 0,
per the manuscript's zero-demand convention (see the \`\$audit\` block
and eMethods S4).

## See also

\[compute_band_tract_overlap\], \[compute_provider_supply\],
\[compute_e2sfca_raster\]

Other E2SFCA computation:
[`compute_band_tract_overlap()`](https://mufflyt.github.io/twostep/reference/compute_band_tract_overlap.md),
[`compute_e2sfca_raster()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca_raster.md),
[`compute_provider_supply()`](https://mufflyt.github.io/twostep/reference/compute_provider_supply.md),
[`e2sfca_cell_summaries()`](https://mufflyt.github.io/twostep/reference/e2sfca_cell_summaries.md)

## Examples

``` r
# Four tracts, two providers, small enough to check by hand.
tract_pop <- data.frame(
  GEOID      = c("T1", "T2", "T3", "T4"),
  female_pop = c(1000, 2000, 1500, 500)
)
# One row per (tract, provider, band), at the tract's TIGHTEST band.
overlap <- data.frame(
  GEOID            = c("T1", "T2", "T3", "T4", "T2", "T3"),
  coord_id         = c("P1", "P1", "P1", "P2", "P2", "P2"),
  band             = c(30L, 60L, 120L, 30L, 120L, 60L),
  overlap_fraction = 1
)
supply <- data.frame(coord_id = c("P1", "P2"), supply = c(4, 6))

# `weights` are CUMULATIVE; the increments are derived internally.
res <- compute_e2sfca(overlap, tract_pop, supply,
                      weights = c(`30` = 1, `60` = 0.68, `120` = 0.22, `180` = 0.09))
res$access[, c("GEOID", "access", "access_math", "reached")]
#>   GEOID       access  access_math reached
#> 1    T1 0.0008919861 0.0008919861    TRUE
#> 2    T2 0.0019849327 0.0019849327    TRUE
#> 3    T3 0.0028488558 0.0028488558    TRUE
#> 4    T4 0.0017297297 0.0017297297    TRUE

# Conservation: accessibility redistributes supply, it does not create it.
pop <- tract_pop$female_pop[match(res$access$GEOID, tract_pop$GEOID)]
stopifnot(all.equal(sum(pop * res$access$access_math), sum(supply$supply)))

# Missing population is an ERROR, not a zero: zero-filling would drop people
# from the Step 1 denominator and inflate accessibility.
gap <- tract_pop; gap$female_pop[3] <- NA
try(compute_e2sfca(overlap, gap, supply))
#> Error : compute_e2sfca: 1 tract(s) have NA in population column 'female_pop' (T3). NA is UNKNOWN population, not zero: coercing it to zero would drop those people from the Step 1 denominator and inflate accessibility. Fix the upstream join, or pass na_pop_policy = "zero" to declare an explicit, documented imputation.
```
