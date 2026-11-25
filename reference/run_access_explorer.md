# Launch the twostep E2SFCA Access Explorer Shiny app

A SEPARATE Shiny app from the isochrones drive-time coverage maps.
twostep measures accessibility (supply-to-demand, per capita, by whom);
isochrones measures reachability. The app reads twostep's frozen
artifacts (the vendored 2023 access-by-group extract for the Disparities
tab; the staged tract layer for the Access-map tab) and never recomputes
them.

The Access-map tab reuses the leaflet logic in
\`scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R\`.

## Usage

``` r
run_access_explorer(...)
```

## Arguments

- ...:

  passed to \[shiny::runApp()\].

## Value

Invisibly, the value of \[shiny::runApp()\].

## See also

The app's \`inst/shiny/access_explorer/README.md\` and
\`generate_provenance.R\` (verifiable input provenance).

## Examples

``` r
if (FALSE) { # \dontrun{
run_access_explorer()                 # launch in the default browser
run_access_explorer(launch.browser = FALSE, port = 8080)
} # }
```
