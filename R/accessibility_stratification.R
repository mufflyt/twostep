# ==============================================================================
# accessibility_stratification.R -- SSOT SHIM.
# Every function that lived here (weighted_mean_all, zero_access_share,
# rurality_from_ruca, tract_vintage_of, acs_year_of, mc_weighted_ci,
# annual_trend, + TOTAL_FEMALE_VAR / RACE_FEMALE_VARS) was promoted VERBATIM to
# the shared mufflyaccess package (single source of truth across isochrones /
# twostep). This file now loads the package so the consumers that source() it
# (desjardins7_e2sfca.R, stratify_allyears_access.R, inferential_stats_access.R,
# spatial_outcomes_2020.R, sensitivity_e2sfca_2020.R,
# desjardins7/06_tract_e2sfca_denominator.R) keep working -- there is no local
# definition here anymore, so cross-repo drift is impossible.
#
# BEHAVIOR-PRESERVED: verified byte/behaviorally identical to the package before
# replacement. The only prior difference (rurality_from_ruca hardcoded 1:3/4:10)
# is cosmetic -- the package derives the same split from RUCA_NONMETRO_MIN = 4,
# producing identical output on every code incl. NA/0/11 boundaries.
#
# PRIMARY SOURCES (retained for the rebuild): ACS 90% MOE -> SE = MOE/z90
# (Census 2020); rurality = USDA RUCA (1-3 metro, 4-10 rural); tract vintage =
# 2016-2020 ACS is first on 2020 tracts (Walker ch.7); MC-CI = parametric
# Normal(est,se) weight redraw. Guarded by
# tests/testthat/test-accessibility-stratification.R (behavioral) +
# mufflyaccess's own test-accessibility-stats.R + test-mufflyaccess-consistency.R.
#   install: renv::install("mufflyt/mufflyaccess")   # pin >= 0.1.4
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("Package 'mufflyaccess' is required. Install: renv::install(\"mufflyt/mufflyaccess\").",
       call. = FALSE)
suppressPackageStartupMessages(library(mufflyaccess))
