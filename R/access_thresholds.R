# ==============================================================================
# access_thresholds.R -- SSOT SHIM (LIVE from mufflyaccess).
# TRACT_REACHED_COVERAGE_PCT is sourced live from the shared mufflyaccess package
# (now public + pinned in renv.lock), the single source of truth across isochrones
# / twostep / cliff. No local copy remains, so cross-repo drift is impossible.
# Guarded by tests/testthat/test-ssot-access-constants.R.
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("mufflyaccess (>= 0.10.0) is required (SSOT for TRACT_REACHED_COVERAGE_PCT). ",
       "renv::restore() or remotes::install_github('mufflyt/mufflyaccess').",
       call. = FALSE)

#' Tract "reached"/"covered" population-coverage threshold (percent)
#'
#' A census tract counts as REACHED by a subspecialty at a drive-time band when
#' at least this percent of its (female) population lies within the isochrone --
#' a majority of tract women. Live from `mufflyaccess::TRACT_REACHED_COVERAGE_PCT`.
#' @format Integer scalar, percent in (0, 100].
#' @export
TRACT_REACHED_COVERAGE_PCT <- mufflyaccess::TRACT_REACHED_COVERAGE_PCT
