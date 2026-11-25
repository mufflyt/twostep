# Create Bivariate Color Palette

Generates a 3×3 or 4×4 bivariate color palette for choropleth mapping.
Uses research-based color schemes from Joshua Stevens and Cynthia
Brewer.

## Usage

``` r
create_bivariate_palette(palette = "BlueYellow", n_bins = 3)
```

## Arguments

- palette:

  Palette name (default: "BlueYellow") Options: "BlueYellow",
  "PurpleGreen", "BrownBlue", "PinkBlue"

- n_bins:

  Number of bins per dimension (default: 3) Options: 3 (3×3 = 9 colors)
  or 4 (4×4 = 16 colors)

## Value

Matrix of hex colors (n_bins × n_bins)

## Details

Bivariate Color Theory: - X-axis: First variable (e.g., female
population) - Y-axis: Second variable (e.g., subspecialist access) -
Color saturation increases with both variables - Corner colors represent
extreme combinations

Palette Sources: - Joshua Stevens (2015): "Bivariate Choropleth Maps: A
How-to Guide" - Cynthia Brewer: ColorBrewer 2.0

## Examples

``` r
if (FALSE) { # \dontrun{
# 3×3 Blue-Yellow palette (default)
pal <- create_bivariate_palette()

# 4×4 Purple-Green palette
pal <- create_bivariate_palette("PurpleGreen", n_bins = 4)
} # }
```
