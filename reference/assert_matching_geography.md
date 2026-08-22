# Assert the workforce numerator and denominator share one geography

Fail-loud precondition for any supply-to-demand computation: the
geography of the workforce numerator must be identical to the geography
of the population / access denominator. This is the twostep
materialization of \`stopifnot(identical(workforce_geography,
denominator_geography))\`.

## Usage

``` r
assert_matching_geography(numerator_geography, denominator_geography)
```

## Arguments

- numerator_geography:

  scalar geography label of the workforce numerator (e.g. "national",
  "conus", a state FIPS). Character or factor.

- denominator_geography:

  scalar geography label of the population/access denominator.

## Value

invisibly \`TRUE\` when the two agree; otherwise \`stop()\`s.

## See also

\[assert_access_language()\] (the companion non-normative-language
guard)

## Examples

``` r
assert_matching_geography("national", "national")   # invisibly TRUE
assert_matching_geography("08", "08")                # state FIPS; ok
if (FALSE) { # \dontrun{
assert_matching_geography("national", "conus")       # errors: geography mismatch
} # }
```
