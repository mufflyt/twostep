# ==============================================================================
# access_thresholds.R -- SSOT (twostep-local, VENDORED).
# TRACT_REACHED_COVERAGE_PCT was promoted to the shared mufflyaccess package, but
# that package is private, so to keep twostep self-contained and reproducible by
# outsiders the value is VENDORED here (single in-repo source of truth).
# Upstream origin: mufflyaccess::TRACT_REACHED_COVERAGE_PCT (itself from
# isochrones/R/access_thresholds.R). Behavior-identical; guarded by
# tests/testthat/test-ssot-access-constants.R.
# ==============================================================================

#' Tract "reached"/"covered" population-coverage threshold (percent)
#'
#' A census tract counts as REACHED by a subspecialty at a drive-time band when
#' at least this percent of its (female) population lies within the isochrone --
#' a majority of tract women. `reached == 0` (below this) AND rural defines a
#' subspecialty access desert. This is the binary coverage cut for desert counts,
#' the exclusive-access contrast, and the logistic "reached" outcome.
#' @format Integer scalar, percent in (0, 100].
#' @export
TRACT_REACHED_COVERAGE_PCT <- 50L

stopifnot(
  "TRACT_REACHED_COVERAGE_PCT must be a single integer" =
    is.integer(TRACT_REACHED_COVERAGE_PCT) && length(TRACT_REACHED_COVERAGE_PCT) == 1L,
  "TRACT_REACHED_COVERAGE_PCT must be a percent in (0, 100]" =
    TRACT_REACHED_COVERAGE_PCT > 0L && TRACT_REACHED_COVERAGE_PCT <= 100L
)
