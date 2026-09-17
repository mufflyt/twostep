# Population-weighted no-access share (percent) from a tract access table.

Percent of \`dvec\` population in tracts with \`A \<= 0\` (equivalently
\`A == 0\`, since access is non-negative). The zero-access tract SET is
geometric; the reported share is denominator-weighted, so it varies with
\`dvec\` but is invariant to the positive band weights.

## Usage

``` r
dj7_no_access_share(access_df, dvec)
```

## Arguments

- access_df:

  output of \[dj7_tract_access\] (GEOID, A).

- dvec:

  named numeric demand vector over ALL tracts (unreached tracts count as
  zero access).

## Value

percent in \[0, 100\].

## Examples

``` r
acc  <- data.frame(GEOID = c("A", "B", "C", "D"), A = c(0, 0, 0.5, 0.9))
dvec <- c(A = 50, B = 50, C = 400, D = 500)
# Population-weighted, NOT a tract count: the two zero-access tracts hold
# 100 of 1000 women, so the share is 10 percent and not 50.
dj7_no_access_share(acc, dvec)
#> [1] 10

# A tract with a measured access value but no demand weight would change the
# population denominator, so it is refused rather than dropped.
try(dj7_no_access_share(rbind(acc, data.frame(GEOID = "Z", A = 0)), dvec))
#> Error : dj7_no_access_share: access_df -> dvec joined on `GEOID`: 1 key(s) in access_df have no match in dvec (Z). A tract with a measured access value but no demand weight cannot be dropped silently; it changes the population denominator.
```
