# Locate the Connecticut tract GEOID equivalency table

Resolves the PI-approved ACS-2022 Connecticut equivalency table in a way
that works both when twostep is installed and when \`R/\` is
\`source()\`d directly from a checkout (which is how \`scripts/\`
consume it).

## Usage

``` r
ct_equivalency_table_path()
```

## Value

\`character(1)\` path. Returns \`""\` when no copy can be found, so that
callers can produce a domain-specific fail-closed error.

## Details

Resolution order: the \`TWOSTEP_CT_EQUIVALENCY_CSV\` environment
variable, then the installed \`inst/extdata\` copy, then the in-checkout
\`inst/extdata\` copy.
