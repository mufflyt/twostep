# Classify Values into Bivariate Bins

Classifies two continuous variables into discrete bins for bivariate
mapping.

## Usage

``` r
classify_bivariate(data, var1, var2, n_bins = 3, method = "quantile")
```

## Arguments

- data:

  Data frame or \`sf\` object containing \`var1\` and \`var2\`.

- var1:

  Column name for first variable (X-axis)

- var2:

  Column name for second variable (Y-axis)

- n_bins:

  Number of bins per dimension (default: 3)

- method:

  Classification method (default: "quantile") Options: "quantile"
  (equal-count), "equal" (equal-interval), "jenks" (natural breaks)

## Value

Data frame with added columns: var1_class, var2_class, bivar_class

## Details

Classification Methods: - \*\*Quantile\*\*: Equal number of observations
per bin (recommended for skewed data) - \*\*Equal-interval\*\*: Equal
range per bin (good for normal distributions) - \*\*Jenks\*\*: Natural
breaks (maximizes between-class variance)

Output Classes: - var1_class: 1 (low) to n_bins (high) - var2_class: 1
(low) to n_bins (high) - bivar_class: Concatenated string (e.g., "1-1",
"3-3")

## Examples

``` r
if (FALSE) { # \dontrun{
# Quantile classification (default)
data_classified <- classify_bivariate(
  data = census_tracts,
  var1 = "female_population",
  var2 = "subspecialist_access",
  n_bins = 3
)
} # }
```
