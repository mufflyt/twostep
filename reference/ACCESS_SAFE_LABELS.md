# Approved, non-normative labels for E2SFCA / accessibility outputs

Descriptive labels safe to apply to a modeled accessibility result, in
place of normative adequacy/shortage language (see
\[ACCESS_FORBIDDEN_TERMS\]). E2SFCA is a supply-to-demand ratio, not a
measure of need, so these describe \*what was computed\* rather than
\*whether it is enough\*.

## Usage

``` r
ACCESS_SAFE_LABELS
```

## Format

Character vector of approved label strings.

## See also

\[assert_access_language()\], \[ACCESS_FORBIDDEN_TERMS\]

Other access-language:
[`ACCESS_FORBIDDEN_TERMS`](https://mufflyt.github.io/twostep/reference/ACCESS_FORBIDDEN_TERMS.md),
[`assert_access_language()`](https://mufflyt.github.io/twostep/reference/assert_access_language.md)

## Examples

``` r
"modeled accessibility" %in% ACCESS_SAFE_LABELS   # TRUE
#> [1] TRUE
```
