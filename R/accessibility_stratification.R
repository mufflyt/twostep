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

#' @rdname accessibility_stratification_shim
#' @name accessibility_stratification_shim
#' @export
weighted_mean_all  <- mufflyaccess::weighted_mean_all
#' @export
zero_access_share  <- mufflyaccess::zero_access_share
#' @export
rurality_from_ruca <- mufflyaccess::rurality_from_ruca
#' @export
tract_vintage_of   <- mufflyaccess::tract_vintage_of
#' @export
acs_year_of        <- mufflyaccess::acs_year_of
#' @export
mc_weighted_ci     <- mufflyaccess::mc_weighted_ci
#' @export
annual_trend       <- mufflyaccess::annual_trend
#' @export
TOTAL_FEMALE_VAR   <- mufflyaccess::TOTAL_FEMALE_VAR
#' @export
RACE_FEMALE_VARS   <- mufflyaccess::RACE_FEMALE_VARS
#' @export
RUCA_NONMETRO_MIN  <- mufflyaccess::RUCA_NONMETRO_MIN
