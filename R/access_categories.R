# ==============================================================================
# access_categories.R -- SSOT SHIM (LIVE from mufflyaccess).
# DENOMINATOR_CATEGORY is sourced live from the shared mufflyaccess package (now
# public + pinned in renv.lock), the single source of truth across isochrones /
# twostep / cliff. No local copy remains, so cross-repo drift is impossible.
# Guarded by tests/testthat/test-ssot-access-constants.R.
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("mufflyaccess (>= 0.10.0) is required (SSOT for DENOMINATOR_CATEGORY). ",
       "renv::restore() or remotes::install_github('mufflyt/mufflyaccess').",
       call. = FALSE)

#' Total-female access-table denominator category label
#'
#' The `category` value marking the all-female-population row in the access
#' tables (`filter(category == DENOMINATOR_CATEGORY)`). Live from
#' `mufflyaccess::DENOMINATOR_CATEGORY`.
#' @format Character scalar.
#' @export
DENOMINATOR_CATEGORY <- mufflyaccess::DENOMINATOR_CATEGORY
