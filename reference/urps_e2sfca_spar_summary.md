# Summarise a compute_e2sfca() result into a Spatial Access Ratio (SPAR) row

The bridge between \`twostep::compute_e2sfca()\` and the
one-row-per-scenario-year accessibility metric
\[urps_project_accessibility()\] collects. Given an E2SFCA result and
the tract population, it returns the population-weighted mean access and
the SPAR distribution – the true drive-time accessibility summary, not a
supply-density stand-in. Because it operates only on the returned
\`data.frame\`s, it is base R and testable without the
\`sf\`/\`terra\`/\`dplyr\` geospatial stack (feed it a synthetic
\`\$access\` frame).

## Usage

``` r
urps_e2sfca_spar_summary(
  e2sfca,
  tract_pop,
  pop_col = "female_pop",
  low_spar = 0.5
)
```

## Arguments

- e2sfca:

  The list returned by \`twostep::compute_e2sfca()\` (uses its
  \`\$access\` element: \`GEOID\`, \`access_scaled\`).

- tract_pop:

  A \`data.frame\` with \`GEOID\` and the population column.

- pop_col:

  Population column name in \`tract_pop\` (default \`"female_pop"\`).

- low_spar:

  SPAR threshold defining a "low access" tract (default \`0.5\`, i.e.
  under half the national mean).

## Value

A one-row \`data.frame\`: \`mean_access_per100k\`,
\`spar_national_mean\` (a \`1.00\` sanity check),
\`low_access_pop_share\`, \`zero_access_pop_share\`, and
\`n_reached_tracts\`.

## Details

SPAR is per-capita access normalised so the population-weighted national
mean is \`1.00\` (Wan/Luo & Wang): \`spar = access_scaled /
weighted.mean(access_scaled, pop)\`. Tracts absent from
\`e2sfca\$access\` are unreached and counted as zero access, so the
population shares use the full denominator.

## See also

\[urps_project_accessibility()\], \`twostep::compute_e2sfca()\`
