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
# THE HEADLINE: THE DEFAULT IS SOUND
# ----------------------------------
# Case-weighted global sigma is 22.7 MILES, which is 44 minutes at 40 mph and
# 59 minutes at 30 mph. The 60-minute default sits inside that range. This
# measurement CONFIRMS the existing parameter for aggregate use; it does not
# overturn it.
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

#' Calibrated bandwidth in minutes, by assumed road speed
#'
#' Derived from [URPS_INPATIENT_SIGMA_MILES] as `miles * 1.3 / mph * 60`. The
#' spread across plausible speeds is the reason the mile value is canonical.
#' @format Named numeric vector keyed by assumed mph.
#' @export
URPS_INPATIENT_SIGMA_MINUTES <- c("30" = 59, "40" = 44, "50" = 35)

#' Bandwidth stratified by distance to the nearest capable hospital
#'
#' Names are the upper bound of the nearest-facility distance stratum in miles.
#' The twenty-fold range is the substantive result: sigma is availability
#' dependent, and a fixed value cannot represent both ends.
#' @format Named numeric vector, sigma in miles.
#' @export
URPS_INPATIENT_SIGMA_BY_AVAILABILITY <- c(
  "5"   = 5.0,     # urban: a capable hospital within 5 miles
  "10"  = 22.1,
  "25"  = 27.4,
  "999" = 108.7    # rural: nearest capable hospital beyond 25 miles
)

#' E2SFCA band weights for urogynaecologic inpatient surgery
#'
#' Wraps [gaussian_band_weights] with the CHIA-calibrated bandwidth. Returns a
#' monotone vector that passes [e2sfca_band_weights], unlike the raw empirical
#' kernel, which is non-monotone (women bypass nearer hospitals for
#' higher-volume ones) and would produce a negative incremental weight.
#'
#' @param bands Band edges in minutes, as for [gaussian_band_weights].
#' @param mph Assumed road speed used to express the calibrated bandwidth in
#'   minutes. Defaults to 40.
#' @return Named numeric vector of normalised zonal weights.
#' @examples
#' urps_inpatient_band_weights()            # calibrated
#' gaussian_band_weights()                  # the sigma = 60 min default
#' @export
urps_inpatient_band_weights <- function(bands = c(30L, 60L, 120L, 180L),
                                        mph = 40) {
  checkmate::assert_number(mph, lower = 1)
  sigma_minutes <- URPS_INPATIENT_SIGMA_MILES * 1.3 / mph * 60
  w <- gaussian_band_weights(bands = bands, sigma = sigma_minutes)
  attr(w, "decay_meta")$sigma_source <- "CHIA MA inpatient urogyn surgery, FY2007-2018"
  attr(w, "decay_meta")$sigma_miles <- URPS_INPATIENT_SIGMA_MILES
  attr(w, "decay_meta")$assumed_mph <- mph
  attr(w, "decay_meta")$calibration_tier <- "observed_regional"
  w
}
