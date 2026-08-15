# ==============================================================================
# accessibility_stratification.R -- SSOT SHIM (LIVE from mufflyaccess).
# The population-weighted accessibility-disparity statistics (weighted_mean_all,
# zero_access_share, rurality_from_ruca, tract_vintage_of, acs_year_of,
# mc_weighted_ci, annual_trend, + TOTAL_FEMALE_VAR / RACE_FEMALE_VARS /
# RUCA_NONMETRO_MIN) are sourced live from the shared mufflyaccess package (now
# public + pinned in renv.lock), the single source of truth across isochrones /
# twostep / cliff. No local copies remain, so cross-repo drift is impossible.
# Consumers that source() this file (desjardins7_e2sfca.R, stratify_allyears_access.R,
# inferential_stats_access.R, spatial_outcomes_2020.R, sensitivity_e2sfca_2020.R,
# desjardins7/06_tract_e2sfca_denominator.R) keep working unchanged.
# Guarded by tests/testthat/test-accessibility-stratification.R and
# test-mufflyaccess-consistency.R.
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("mufflyaccess (>= 0.10.0) is required (SSOT for the disparity statistics). ",
       "renv::restore() or remotes::install_github('mufflyt/mufflyaccess').",
       call. = FALSE)

#' Accessibility-disparity statistics re-exported from mufflyaccess
#'
#' @description
#' These objects are not defined here. They are bound live to the implementations
#' in the shared \pkg{mufflyaccess} package, the single source of truth across
#' isochrones / twostep / cliff, so cross-repo drift is impossible. They are
#' re-exported under their original names so code that `source()`s this file keeps
#' working unchanged. See the \pkg{mufflyaccess} documentation for the full
#' argument and return contracts.
#'
#' @section Objects:
#' \describe{
#'   \item{`weighted_mean_all`}{Population-weighted mean across all tracts.}
#'   \item{`zero_access_share`}{Population share with zero modelled access.}
#'   \item{`rurality_from_ruca`}{Map RUCA codes to a rurality class.}
#'   \item{`tract_vintage_of`}{Census-tract vintage for an analysis year.}
#'   \item{`acs_year_of`}{ACS 5-year vintage for an analysis year.}
#'   \item{`mc_weighted_ci`}{Monte-Carlo CI for a weighted statistic.}
#'   \item{`annual_trend`}{Annual trend estimate over the study period.}
#'   \item{`TOTAL_FEMALE_VAR`}{ACS variable for the total female denominator.}
#'   \item{`RACE_FEMALE_VARS`}{ACS variables for race-stratified female denominators.}
#'   \item{`RUCA_NONMETRO_MIN`}{Minimum RUCA code counted as non-metro.}
#' }
#'
#' @seealso The guards in `tests/testthat/test-accessibility-stratification.R` and
#'   `tests/testthat/test-mufflyaccess-consistency.R`.
#'
#' @usage NULL
# `@usage NULL` suppresses the generated \usage block. These are bindings to
# functions defined in mufflyaccess, so roxygen would otherwise emit their
# signatures here and `R CMD check` would demand @param entries for arguments
# whose contracts belong to -- and are documented in -- the other package.
# Restating them would invite exactly the cross-repo drift this shim prevents.
#' @name accessibility_stratification_shim
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
weighted_mean_all  <- mufflyaccess::weighted_mean_all
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
zero_access_share  <- mufflyaccess::zero_access_share
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
rurality_from_ruca <- mufflyaccess::rurality_from_ruca
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
tract_vintage_of   <- mufflyaccess::tract_vintage_of
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
acs_year_of        <- mufflyaccess::acs_year_of
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
mc_weighted_ci     <- mufflyaccess::mc_weighted_ci
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
annual_trend       <- mufflyaccess::annual_trend
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
TOTAL_FEMALE_VAR   <- mufflyaccess::TOTAL_FEMALE_VAR
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
RACE_FEMALE_VARS   <- mufflyaccess::RACE_FEMALE_VARS
#' @rdname accessibility_stratification_shim
#' @usage NULL
#' @export
RUCA_NONMETRO_MIN  <- mufflyaccess::RUCA_NONMETRO_MIN
