# Normative terms that must NOT be applied to an accessibility result without a defensible demand target (there is none in this study).

Adequacy/shortage vocabulary that asserts a normative demand target
E2SFCA does not define. \[assert_access_language()\] rejects any string
containing one of these as a whole word (case-insensitive). Use
\[ACCESS_SAFE_LABELS\] instead.

## Usage

``` r
ACCESS_FORBIDDEN_TERMS
```

## Format

Character vector of forbidden (whole-word) terms.

## See also

\[assert_access_language()\], \[ACCESS_SAFE_LABELS\]

Other access-language:
[`ACCESS_SAFE_LABELS`](https://mufflyt.github.io/twostep/reference/ACCESS_SAFE_LABELS.md),
[`assert_access_language()`](https://mufflyt.github.io/twostep/reference/assert_access_language.md)

## Examples

``` r
"shortage" %in% ACCESS_FORBIDDEN_TERMS   # TRUE
#> [1] TRUE
```
