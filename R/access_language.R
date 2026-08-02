# ==============================================================================
# access_language.R -- non-normative vocabulary guard for reporting accessibility.
#
# E2SFCA is a MODELED supply-to-demand ratio, not a measure of need, adequacy, or
# shortage. Labeling it "shortage" / "surplus" / "adequate" / "need met" asserts a
# normative demand target that this study does not define (historical utilization
# is not population need; apparent surplus can be underuse/underfunding/barriers).
# Use the approved, descriptive labels below instead. This is the accessibility
# analogue of the figure-dashes / no-hardcoded-count language guards.
#
# Guarded by tests/testthat/test-access-language-guard.R.
# ==============================================================================

#' Approved, non-normative labels for E2SFCA / accessibility outputs
#'
#' @description Descriptive labels safe to apply to a modeled accessibility
#'   result, in place of normative adequacy/shortage language (see
#'   [ACCESS_FORBIDDEN_TERMS]). E2SFCA is a supply-to-demand ratio, not a measure
#'   of need, so these describe *what was computed* rather than *whether it is
#'   enough*.
#' @format Character vector of approved label strings.
#' @family access-language
#' @seealso [assert_access_language()], [ACCESS_FORBIDDEN_TERMS]
#' @examples
#' "modeled accessibility" %in% ACCESS_SAFE_LABELS   # TRUE
#' @export
ACCESS_SAFE_LABELS <- c(
  "modeled accessibility",
  "relative accessibility",
  "projected supply-demand difference",
  "change from baseline",
  "population-to-clinical-FTE ratio",
  "population per provider",
  "% of women with access",
  "mean access"
)

#' Normative terms that must NOT be applied to an accessibility result without a
#' defensible demand target (there is none in this study).
#'
#' @description Adequacy/shortage vocabulary that asserts a normative demand
#'   target E2SFCA does not define. [assert_access_language()] rejects any string
#'   containing one of these as a whole word (case-insensitive). Use
#'   [ACCESS_SAFE_LABELS] instead.
#' @format Character vector of forbidden (whole-word) terms.
#' @family access-language
#' @seealso [assert_access_language()], [ACCESS_SAFE_LABELS]
#' @examples
#' "shortage" %in% ACCESS_FORBIDDEN_TERMS   # TRUE
#' @export
ACCESS_FORBIDDEN_TERMS <- c(
  "shortage", "surplus", "adequacy", "adequate", "inadequate",
  "unmet need", "unmet needs", "need met", "needs met",
  "undersupply", "oversupply", "under-supply", "over-supply",
  "sufficient", "insufficient"
)

#' Assert a string (e.g. a plot label or user-facing caption) uses no normative
#' adequacy/shortage language for an accessibility result.
#'
#' @param x character vector of user-facing strings.
#' @param context short label for the error message (default "label").
#' @return invisibly `TRUE` when clean; otherwise `stop()`s listing the offenders.
#' @family access-language
#' @seealso [ACCESS_FORBIDDEN_TERMS], [ACCESS_SAFE_LABELS]
#' @examples
#' assert_access_language("modeled accessibility by county")   # invisibly TRUE
#' assert_access_language(c("mean access", "change from baseline"))
#' \dontrun{
#' assert_access_language("provider shortage in rural tracts") # errors (normative)
#' }
#' @export
assert_access_language <- function(x, context = "label") {
  x <- as.character(x)
  pat <- paste0("\\b(", paste(gsub("([-])", "\\\\\\1", ACCESS_FORBIDDEN_TERMS), collapse = "|"), ")\\b")
  hit <- grepl(pat, x, ignore.case = TRUE, perl = TRUE)
  if (any(hit)) {
    offenders <- vapply(which(hit), function(i) {
      term <- regmatches(x[i], regexpr(pat, x[i], ignore.case = TRUE, perl = TRUE))
      sprintf("  '%s'  (normative term: %s)", x[i], term)
    }, character(1))
    stop(sprintf(
      "[access-language] %s uses normative adequacy/shortage language for an accessibility result.\n%s\nUse a descriptive label instead (see ACCESS_SAFE_LABELS).",
      context, paste(offenders, collapse = "\n")), call. = FALSE)
  }
  invisible(TRUE)
}
