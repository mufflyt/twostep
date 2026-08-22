# Assert a string (e.g. a plot label or user-facing caption) uses no normative adequacy/shortage language for an accessibility result.

Assert a string (e.g. a plot label or user-facing caption) uses no
normative adequacy/shortage language for an accessibility result.

## Usage

``` r
assert_access_language(x, context = "label")
```

## Arguments

- x:

  character vector of user-facing strings.

- context:

  short label for the error message (default "label").

## Value

invisibly \`TRUE\` when clean; otherwise \`stop()\`s listing the
offenders.

## See also

\[ACCESS_FORBIDDEN_TERMS\], \[ACCESS_SAFE_LABELS\]

Other access-language:
[`ACCESS_FORBIDDEN_TERMS`](https://mufflyt.github.io/twostep/reference/ACCESS_FORBIDDEN_TERMS.md),
[`ACCESS_SAFE_LABELS`](https://mufflyt.github.io/twostep/reference/ACCESS_SAFE_LABELS.md)

## Examples

``` r
assert_access_language("modeled accessibility by county")   # invisibly TRUE
assert_access_language(c("mean access", "change from baseline"))
if (FALSE) { # \dontrun{
assert_access_language("provider shortage in rural tracts") # errors (normative)
} # }
```
