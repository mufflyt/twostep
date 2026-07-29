# ==============================================================================
# geography_agreement.R -- boundary-enforcement primitive (twostep-owned).
# The workforce numerator (providers, from the isochrones roster via the
# mufflyaccess SSOT) and the population / access denominator (twostep's own ACS
# denominators) MUST be expressed on the same geography before any supply-to-
# demand ratio is formed. Mixing, e.g., a national numerator with a CONUS
# denominator silently biases every accessibility score. This guard makes that a
# hard, fail-loud precondition.
#
# The E2SFCA pipeline (run_twostep_accessibility / prepare_provider_supply) MUST
# call this before combining supply and demand. See docs/data-ownership.md.
# ==============================================================================

#' Assert the workforce numerator and denominator share one geography
#'
#' Fail-loud precondition for any supply-to-demand computation: the geography of
#' the workforce numerator must be identical to the geography of the population /
#' access denominator. This is the twostep materialization of
#' `stopifnot(identical(workforce_geography, denominator_geography))`.
#'
#' @param numerator_geography scalar geography label of the workforce numerator
#'   (e.g. "national", "conus", a state FIPS). Character or factor.
#' @param denominator_geography scalar geography label of the population/access
#'   denominator.
#' @return invisibly `TRUE` when the two agree; otherwise `stop()`s.
#' @export
assert_matching_geography <- function(numerator_geography, denominator_geography) {
  num <- as.character(numerator_geography)
  den <- as.character(denominator_geography)
  stopifnot(
    "numerator_geography must be a single non-missing value" =
      length(num) == 1L && !is.na(num) && nzchar(num),
    "denominator_geography must be a single non-missing value" =
      length(den) == 1L && !is.na(den) && nzchar(den)
  )
  if (!identical(num, den)) {
    stop(sprintf(
      paste0("geography mismatch: workforce numerator is '%s' but the ",
             "population/access denominator is '%s'. The E2SFCA numerator and ",
             "denominator must share one geography."),
      num, den), call. = FALSE)
  }
  invisible(TRUE)
}
