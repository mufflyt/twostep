################################################################################
# R/urps_inpatient_sigma.R
# Empirically calibrated Gaussian bandwidth for urogynaecologic inpatient surgery
#
# Calibration tier: observed_regional (Massachusetts CHIA, FY2007-2018)
# Source: mufflyt/simulation docs/CHIA_TECHNICAL_APPENDIX.md section 5
#         builder: mufflyt/simulation scripts/chia/fit_urps_sigma.R
#
# WHAT THIS IS
# ------------
# E2SFCA_DEFAULT_WEIGHTS in two_step_floating_catchment.R is not a raw Luo/Qi
# table: it is a Gaussian decay with sigma = 60 minutes, evaluated at the four
# band edges and normalised to the 30-minute band. Sigma is therefore the single
# free parameter, and it has been an assumption. This file supplies an
# empirical value for one specific question -- where women actually travelled
# for admitted urogynaecologic surgery -- measured from 9,081 operations by
# board-certified URPS surgeons across 38 Massachusetts hospitals.
#
# THE HEADLINE: THE DEFAULT IS ~46% TOO WIDE
# ------------------------------------------
# Case-weighted global sigma is 22.7 MILES = 41 MINUTES on the Massachusetts
# road network, against a 60-minute default. Converting to band weights:
#
#   sigma = 60 min (default)     1.000  0.687  0.153  0.013
#   sigma = 41 min (calibrated)  1.000  0.448  0.018  0.000
#
# The default credits the 60-minute band 1.5x, the 120-minute band 8x, and the
# 180-minute band ~100x more supply than women were observed to use. For
# urogynaecologic surgery it materially over-states how much distant capacity is
# reachable.
#
# HOW THE MINUTES WERE OBTAINED (this is the part that matters)
# -------------------------------------------------------------
# NOT by assuming a road speed. The conversion is calibrated against real
# road-network isochrones for the FPMRS/urology provider cohort
# (mufflyt/isochrones, augmented_isochrones_fpmrs_uro), restricted to the 195
# Massachusetts providers. Equivalent-area radius by band:
#
#   30 min -> 15.6 mi     60 min -> 35.7 mi
#  120 min -> 70.1 mi    180 min -> 101.8 mi
#
# Interquartile ranges are tight (14.5-16.7 mi at 30 min), and a log-log fit
# gives R2 = 0.997. Implied effective speed is 31-36 mph and rises with trip
# length, which no single mph constant reproduces.
#
# CORRECTION: an earlier version of this file reported 44-59 minutes and
# concluded the 60-minute default was confirmed. That conversion applied a 1.3
# circuity factor on top of an assumed speed -- but an isochrone's equivalent-area
# radius ALREADY embeds road circuity, so the factor was counted twice and
# inflated the estimate. The corrected figure is 41 minutes.
#
# THE ACTUAL FINDING: SIGMA IS NOT A CONSTANT
# -------------------------------------------
# Sigma depends strongly on what is available:
#
#   nearest capable hospital <= 5 mi   sigma =   5.0 mi   (urban)
#   nearest 5-10 mi                    sigma =  22.1 mi
#   nearest 10-25 mi                   sigma =  27.4 mi
#   nearest > 25 mi                    sigma = 108.7 mi   (rural)
#
# A twenty-fold range. Women adapt travel to what exists: those with a hospital
# nearby rarely pass it, those without travel as far as needed. A fixed-sigma
# Gaussian cannot express that, so a single global value -- 60 minutes or 22.7
# miles -- necessarily understates access in dense areas and overstates the
# burden in sparse ones. The stratified vector is the more faithful object.
#
# A NOTE ON HOW THIS WAS NEARLY GOT WRONG
# ---------------------------------------
# Fitting sigma only on the urban stratum gives 5.0 miles, roughly 10 minutes,
# and appears to show the 60-minute default overstating reach five- to
# sevenfold. That conditioning selects women who HAVE close options, whose
# revealed decay is necessarily tight. The stratified fit is what makes the
# aggregate value trustworthy; the urban-only fit is a selection artefact.
#
# SCOPE
# -----
# Massachusetts, hospital inpatient surgery, operator-defined urogynaecology
# (board-certified URPS surgeon), FY2007-2018. Distances are straight-line miles
# between ZCTA centroids -- MEASURED. Minute equivalents apply a 1.3 circuity
# factor and an assumed road speed and are NOT measured; the speed constant moves
# the answer by roughly 14 points, so prefer the mile-denominated value and
# substitute true drive times from mufflyt/isochrones when available.
################################################################################

#' Calibrated Gaussian bandwidth for urogynaecologic inpatient surgery (miles)
#'
#' Case-weighted across nearest-facility strata. Measured, not assumed.
#' @format Numeric scalar, miles.
#' @seealso [URPS_INPATIENT_SIGMA_BY_AVAILABILITY], [E2SFCA_DEFAULT_WEIGHTS]
#' @export
URPS_INPATIENT_SIGMA_MILES <- 22.7

#' Calibrated bandwidth in minutes
#'
#' Measured, not assumed: converted from [URPS_INPATIENT_SIGMA_MILES] using
#' real Massachusetts road-network isochrones for the FPMRS/urology cohort
#' (30 min = 15.6 mi, 60 = 35.7, 120 = 70.1, 180 = 101.8; log-log R2 = 0.997).
#' @format Numeric scalar, minutes.
#' @export
URPS_INPATIENT_SIGMA_MINUTES <- 41

#' Miles-to-minutes calibration for the Massachusetts road network
#'
#' Equivalent-area radius of real drive-time isochrones, 195 MA FPMRS/urology
#' providers. Use this rather than a speed constant.
#' @format Named numeric vector: minutes -> median radius in miles.
#' @export
MA_ROAD_NETWORK_RADIUS_MILES <- c("30" = 15.6, "60" = 35.7, "120" = 70.1, "180" = 101.8)

#' Bandwidth stratified by distance to the nearest capable hospital
#'
#' Names are the upper bound of the nearest-facility distance stratum in miles.
#' The twenty-fold range is the substantive result: sigma is availability
#' dependent, and a fixed value cannot represent both ends.
#' @format Named numeric vector, sigma in miles.
#' @export
URPS_INPATIENT_SIGMA_BY_AVAILABILITY <- c(
  "5"   = 5.0,     # urban: a capable hospital within 5 miles  (10 min)
  "10"  = 22.1,    #                                           (40 min)
  "25"  = 27.4,    #                                           (50 min)
  "999" = 108.7    # rural: nearest capable hospital beyond 25 miles (185 min)
)

#' The same stratified bandwidths expressed in minutes
#' @format Named numeric vector, sigma in minutes.
#' @export
URPS_INPATIENT_SIGMA_BY_AVAILABILITY_MIN <- c(
  "5" = 10, "10" = 40, "25" = 50, "999" = 185
)

#' E2SFCA band weights for urogynaecologic inpatient surgery
#'
#' Wraps [gaussian_band_weights] with the CHIA-calibrated bandwidth. Returns a
#' monotone vector that passes [e2sfca_band_weights], unlike the raw empirical
#' kernel, which is non-monotone (women bypass nearer hospitals for
#' higher-volume ones) and would produce a negative incremental weight.
#'
#' @param bands Band edges in minutes, as for [gaussian_band_weights].
#' @param sigma_minutes Calibrated bandwidth in minutes; defaults to the
#'   road-network-calibrated [URPS_INPATIENT_SIGMA_MINUTES] (41).
#' @return Named numeric vector of normalised zonal weights.
#' @examples
#' urps_inpatient_band_weights()   # 1.000 0.448 0.018 0.000  (sigma = 41 min)
#' gaussian_band_weights()         # 1.000 0.687 0.153 0.013  (sigma = 60 min)
#' @export
urps_inpatient_band_weights <- function(bands = c(30L, 60L, 120L, 180L),
                                        sigma_minutes = URPS_INPATIENT_SIGMA_MINUTES) {
  checkmate::assert_number(sigma_minutes, lower = 1)
  w <- gaussian_band_weights(bands = bands, sigma = sigma_minutes)
  attr(w, "decay_meta")$sigma_source <- "CHIA MA inpatient urogyn surgery, FY2007-2018"
  attr(w, "decay_meta")$sigma_miles <- URPS_INPATIENT_SIGMA_MILES
  attr(w, "decay_meta")$minutes_calibration <- "MA road-network isochrones, FPMRS/urology"
  attr(w, "decay_meta")$calibration_tier <- "observed_regional"
  w
}
