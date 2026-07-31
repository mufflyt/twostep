# ==============================================================================
# accessibility_stratification.R -- SSOT (twostep-local, VENDORED).
# The population-weighted accessibility-disparity statistics (weighted_mean_all,
# zero_access_share, rurality_from_ruca, tract_vintage_of, acs_year_of,
# mc_weighted_ci, annual_trend, + TOTAL_FEMALE_VAR / RACE_FEMALE_VARS) were
# promoted to the shared mufflyaccess package, but that package is private, so to
# keep twostep self-contained and reproducible by outsiders they are VENDORED
# here (single in-repo source of truth). Upstream origin: mufflyaccess (itself
# promoted verbatim from isochrones/R/accessibility_stratification.R).
# Behavior-identical; guarded by tests/testthat/test-accessibility-stratification.R
# and tests/testthat/test-mufflyaccess-consistency.R.
#
# PRIMARY SOURCES: ACS 90% MOE -> SE = MOE/z90 (Census 2020); rurality = USDA
# RUCA (1-3 metro, 4-10 rural, derived from RUCA_NONMETRO_MIN = 4); tract vintage
# = 2016-2020 ACS is first on 2020 tracts (Walker ch.7); MC-CI = parametric
# Normal(est,se) weight redraw. Base R + `stats` only.
# ==============================================================================

#' Canonical 2-level RUCA breakpoint: first NON-metropolitan primary code.
#' RUCA 1-3 metropolitan; 4-10 non-metropolitan. Used by [rurality_from_ruca()].
#' @keywords internal
RUCA_NONMETRO_MIN <- 4L

#' Population-weighted mean over all elements (sparse-group safe).
#' @param a numeric values.
#' @param w numeric weights (same length as `a`).
#' @return weighted mean, or NA if the weights sum to 0 / non-finite.
#' @export
weighted_mean_all <- function(a, w) {
  stopifnot(length(a) == length(w))
  sw <- sum(w)
  if (!is.finite(sw) || sw == 0) return(NA_real_)
  sum(a * w) / sw
}

#' Zero-access share (percent of weighted population with access EXACTLY 0).
#' @param access numeric accessibility values.
#' @param w numeric weights.
#' @return percent in [0,100] under non-negative weights, or NA.
#' @export
zero_access_share <- function(access, w) {
  stopifnot(length(access) == length(w))
  sw <- sum(w)
  if (!is.finite(sw) || sw == 0) return(NA_real_)
  100 * sum(w * (access == 0)) / sw
}

#' Map a USDA RUCA primary code to a binary rurality class.
#' Metropolitan = primary RUCA 1..(RUCA_NONMETRO_MIN-1); Rural = RUCA_NONMETRO_MIN..10.
#' @param code integer-coercible RUCA primary code(s).
#' @return character "Metropolitan"/"Rural" (NA for NA/invalid codes).
#' @export
rurality_from_ruca <- function(code) {
  code  <- suppressWarnings(as.integer(code))
  metro <- seq_len(RUCA_NONMETRO_MIN - 1L)   # 1:3
  rural <- RUCA_NONMETRO_MIN:10L             # 4:10
  out <- ifelse(code %in% metro, "Metropolitan",
         ifelse(code %in% rural, "Rural", NA_character_))
  out[is.na(code)] <- NA_character_
  out
}

#' Census tract boundary vintage for a study year (2010 tracts <=2019, 2020 >=2020).
#' @param year integer-coercible study year(s).
#' @return integer 2010 or 2020.
#' @export
tract_vintage_of <- function(year) ifelse(as.integer(year) >= 2020L, 2020L, 2010L)

#' ACS 5-year data year for a study year (clamped to the 2013-2022 window).
#' @param year integer-coercible study year(s).
#' @return integer ACS data end-year(s), clamped to [2013, 2022].
#' @export
acs_year_of <- function(year) pmax(pmin(as.integer(year), 2022L), 2013L)

#' Canonical ACS female-population variable codes (footgun: race tables use _017,
#' full B01001 uses _026).
#' @export
TOTAL_FEMALE_VAR <- "B01001_026"
#' @rdname TOTAL_FEMALE_VAR
#' @export
RACE_FEMALE_VARS <- c(white_nh = "B01001H_017", hispanic = "B01001I_017",
                      black = "B01001B_017", aian = "B01001C_017",
                      asian = "B01001D_017", nhpi = "B01001E_017")

#' Monte-Carlo CI for a population-weighted accessibility statistic.
#' Redraws weights ~ Normal(est, se) B times (unbiased: point estimate lies inside its interval).
#' @param access numeric accessibility values.
#' @param est numeric weight estimates.
#' @param se numeric weight standard errors (ACS MOE / z90).
#' @param stat "mean"/"zero".
#' @param B draws.
#' @param probs interval quantiles.
#' @param seed RNG seed.
#' @return named numeric c(point, lo, hi).
#' @export
mc_weighted_ci <- function(access, est, se, stat = c("mean", "zero"),
                           B = 2000L, probs = c(0.025, 0.975), seed = 1L) {
  stat <- match.arg(stat)
  stopifnot(length(access) == length(est), length(est) == length(se), all(se >= 0 | is.na(se)))
  se[is.na(se)] <- 0
  f <- if (stat == "mean") weighted_mean_all else zero_access_share
  point <- f(access, est)
  set.seed(seed)
  n <- length(est)
  draws <- vapply(seq_len(B), function(b) f(access, stats::rnorm(n, est, se)), numeric(1))
  q <- stats::quantile(draws, probs, na.rm = TRUE)
  c(point = point, lo = unname(q[1]), hi = unname(q[2]))
}

#' OLS temporal trend of an annual series (95% t-interval on the slope).
#' @param year integer years.
#' @param value numeric annual estimates.
#' @return named numeric c(slope, lo, hi, p).
#' @export
annual_trend <- function(year, value) {
  d <- data.frame(year = as.numeric(year), value = as.numeric(value))
  d <- d[stats::complete.cases(d), ]
  if (nrow(d) < 3) return(c(slope = NA, lo = NA, hi = NA, p = NA))
  m <- stats::lm(value ~ year, d)
  s <- summary(m)$coefficients["year", ]
  ci <- stats::confint(m)["year", ]
  c(slope = unname(s[["Estimate"]]), lo = unname(ci[1]), hi = unname(ci[2]),
    p = unname(s[["Pr(>|t|)"]]))
}
