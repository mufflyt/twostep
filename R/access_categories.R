# ==============================================================================
# access_categories.R -- SSOT (twostep-local, VENDORED).
# DENOMINATOR_CATEGORY was promoted to the shared mufflyaccess package, but that
# package is private, so to keep twostep self-contained and reproducible by
# outsiders the value is VENDORED here (single in-repo source of truth).
# Upstream origin: mufflyaccess::DENOMINATOR_CATEGORY (itself from
# isochrones/R/access_categories.R). Behavior-identical; guarded by
# tests/testthat/test-ssot-access-constants.R.
# ==============================================================================

#' Total-female access-table denominator category label
#'
#' The `category` value marking the all-female-population row in the access
#' tables (`filter(category == DENOMINATOR_CATEGORY)`) -- the denominator for
#' every access percentage. The race categories are a DISTINCT
#' `"total_female_<race>"` prefixed family and are intentionally NOT this value.
#' @format Character scalar.
#' @export
DENOMINATOR_CATEGORY <- "total_female"

stopifnot(
  "DENOMINATOR_CATEGORY must be a single non-empty string" =
    is.character(DENOMINATOR_CATEGORY) && length(DENOMINATOR_CATEGORY) == 1L &&
    nzchar(DENOMINATOR_CATEGORY),
  "DENOMINATOR_CATEGORY must be the bare total-female label, NOT race-prefixed" =
    !grepl("^total_female_", DENOMINATOR_CATEGORY)
)
