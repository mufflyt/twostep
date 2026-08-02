#' Launch the twostep E2SFCA Access Explorer Shiny app
#'
#' @description A SEPARATE Shiny app from the isochrones drive-time coverage maps.
#'   twostep measures accessibility (supply-to-demand, per capita, by whom);
#'   isochrones measures reachability. The app reads twostep's frozen artifacts
#'   (the vendored 2023 access-by-group extract for the Disparities tab; the staged
#'   tract layer for the Access-map tab) and never recomputes them.
#'
#'   The Access-map tab reuses the leaflet logic in
#'   `scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R`.
#' @param ... passed to [shiny::runApp()].
#' @return Invisibly, the value of [shiny::runApp()].
#' @seealso The app's `inst/shiny/access_explorer/README.md` and
#'   `generate_provenance.R` (verifiable input provenance).
#' @examples
#' \dontrun{
#' run_access_explorer()                 # launch in the default browser
#' run_access_explorer(launch.browser = FALSE, port = 8080)
#' }
#' @export
run_access_explorer <- function(...) {
  app <- system.file("shiny", "access_explorer", package = "twostep")
  if (!nzchar(app)) {
    # source-tree fallback (package not installed)
    root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                     error = function(e) getwd())
    app <- file.path(root, "inst", "shiny", "access_explorer")
  }
  if (!dir.exists(app))
    stop("Access Explorer app directory not found: ", app, call. = FALSE)
  if (!requireNamespace("shiny", quietly = TRUE))
    stop("Package 'shiny' is required to run the Access Explorer.", call. = FALSE)
  shiny::runApp(app, ...)
}
