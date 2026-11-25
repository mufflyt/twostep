# Career-stage split at years-since-certification (boundary at the cutoff).

Reproduces the inline rule in scripts 00/10: a physician is
"Early-to-mid" when \`years_since_cert \<= cutoff\` and "Late"
otherwise. The boundary is INCLUSIVE of the cutoff (exactly \`cutoff\`
years is Early-to-mid). NA years -\> NA stage.

## Usage

``` r
dj7_career_stage(years_since_cert, cutoff = 15)
```

## Arguments

- years_since_cert:

  numeric study-year minus certification year.

- cutoff:

  inclusive upper bound of the early-to-mid class (default 15).

## Value

character "Early-to-mid"/"Late" (NA for NA input).
