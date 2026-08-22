# Partition rows whose access is unknown, rather than zeroing them

Splits a study frame into rows with a measured access value and rows
where access is missing. Missing access is a PROVENANCE GAP, not an
observation of no access: coercing it to zero
(\`d\$access\[is.na(d\$access)\] \<- 0\`, the historic behaviour) biases
the population-weighted mean DOWN and the zero-access share UP, because
a tract that was never measured is counted as a tract where no provider
is reachable.

## Usage

``` r
partition_unknown_access(d, access_col = "access")
```

## Arguments

- d:

  \`data.frame\` of study rows.

- access_col:

  \`character(1)\` name of the access column. Default \`"access"\`.

## Value

\`list\` with \`kept\` (rows with measured access), \`n_unknown\` (count
excluded) and \`frac_unknown\`.

## Examples

``` r
d <- data.frame(GEOID = c("a", "b", "c"), access = c(1, NA, 0))
p <- partition_unknown_access(d)
p$n_unknown          # 1 excluded, NOT turned into a measured zero
#> [1] 1
nrow(p$kept)         # 2: the measured 1 and the measured 0 both survive
#> [1] 2
```
