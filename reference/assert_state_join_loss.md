# Fail closed when any single state loses too much of a join

Computes the per-state share of rows that failed to match and
\`stop()\`s, naming the offending states and their loss rates, when any
state exceeds \`max_frac\`. Use after a \`left_join()\` on tract
\`GEOID\`s so that a vocabulary mismatch fails loudly instead of
silently removing a state.

## Usage

``` r
assert_state_join_loss(geoid, lost, context = "join", max_frac = 0.05)
```

## Arguments

- geoid:

  \`character\` tract GEOIDs; the first two characters are the state
  FIPS code.

- lost:

  \`logical\` of the same length; \`TRUE\` marks a row that failed to
  match (typically \`is.na(joined_column)\`).

- context:

  \`character(1)\` prefix for the error message, e.g. \`"GO 2023"\`.

- max_frac:

  \`numeric(1)\` maximum tolerated per-state loss share. Defaults to
  0.05 (5%), the threshold used by the isochrones production run.

## Value

Invisibly, a named \`numeric\` of per-state loss fractions for the
states that lost at least one row. Called for its fail-closed side
effect.

## Examples

``` r
g <- c("09001010101", "09001010102", "25025010100")
# Nothing lost -> passes:
assert_state_join_loss(g, c(FALSE, FALSE, FALSE), "demo")
```
