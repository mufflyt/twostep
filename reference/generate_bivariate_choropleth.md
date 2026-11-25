# Generate Bivariate Choropleth Map

Creates a bivariate choropleth map showing the relationship between two
variables (e.g., female population and subspecialist access).

## Usage

``` r
generate_bivariate_choropleth(
  data,
  var1,
  var2,
  var1_label = var1,
  var2_label = var2,
  palette = "BlueYellow",
  n_bins = 3,
  method = "quantile",
  title = "Bivariate Choropleth Map",
  subtitle = NULL,
  output_filename = "bivariate_choropleth",
  output_dir = here("manuscript", "figures"),
  width = 12,
  height = 8,
  dpi = 300
)
```

## Arguments

- data:

  \`sf\` object with polygon geometry plus \`var1\` and \`var2\`.

- var1:

  Column name for first variable (X-axis, e.g., "female_population")

- var2:

  Column name for second variable (Y-axis, e.g., "subspecialist_access")

- var1_label:

  Label for first variable (for legend)

- var2_label:

  Label for second variable (for legend)

- palette:

  Color palette name (default: "BlueYellow")

- n_bins:

  Number of bins per dimension (default: 3)

- method:

  Classification method (default: "quantile")

- title:

  Map title

- subtitle:

  Map subtitle (optional)

- output_filename:

  Output filename (without extension)

- output_dir:

  Directory the TIFF, PNG and classified data are written to (default
  \`here("manuscript", "figures")\`). Created if absent.

- width:

  Width in inches (default: 12)

- height:

  Height in inches (default: 8)

- dpi:

  Resolution (default: 300)

## Value

List with map object, classified data, and file paths

## Details

Bivariate Choropleth Maps: - Show relationship between TWO variables
simultaneously - Each census tract colored by combination of both
variables - Legend is 2D grid (not 1D color bar)

Use Cases: - Female population × subspecialist access (healthcare
equity) - Poverty rate × healthcare coverage (socioeconomic
disparities) - Minority percentage × travel time (geographic access
barriers)

Best Practices: - Use 3×3 bins (9 colors) for clarity (4×4 = too many
categories) - Quantile method recommended (equal counts per bin) -
Choose palettes carefully (avoid red-green for colorblind accessibility)

## Examples

``` r
if (FALSE) { # \dontrun{
# Female population × subspecialist access
result <- generate_bivariate_choropleth(
  data = census_tracts,
  var1 = "female_population_total",
  var2 = "percent_with_access_30min",
  var1_label = "Female Population",
  var2_label = "Subspecialist Access (%)",
  title = "Female Population and FPMRS Access by Census Tract",
  output_filename = "bivariate_female_pop_access"
)
} # }
```
