# ==============================================================================
# accessibility_stratification.R
# ------------------------------------------------------------------------------
# Single source of truth for the population-weighted accessibility-disparity
# statistics used by scripts/stratify_allyears_access.R and
# scripts/inferential_stats_access.R. Extracted into pure functions so the
# adversarial + semantic test suite (tests/testthat/test-accessibility-
# stratification.R) can guard them — in particular the Monte-Carlo estimator,
# where a clamp/filter bug once put sparse-group point estimates OUTSIDE their
# own confidence intervals (fixed 2026-07-13).
#
# ------------------------------------------------------------------------------
# PRIMARY SOURCES  (data conventions + estimators; cross-ref manuscript
# eMethods S1 and CLAUDE.md. Rebuild aid: this is the SSOT the two stratify /
# inferential scripts call, guarded by test-accessibility-stratification.R.)
#   ACS margin of error: ACS publishes a 90% MOE, so SE = MOE / 1.645.
#     U.S. Census Bureau, "Understanding and Using American Community Survey Data:
#     What All Data Users Need to Know" (2020), MOE appendix. -> mc_weighted_ci()
#     (called with se = MOE / 1.645).
#   MOE uncertainty propagation: parametric Monte-Carlo (redraw each weight
#     ~ Normal(estimate, SE), recompute the statistic B times), the simulation
#     analogue of the Census variance-replicate approach. -> mc_weighted_ci().
#   Rurality: USDA Economic Research Service Rural-Urban Commuting Area (RUCA)
#     codes; primary RUCA 1-3 = metropolitan, 4-10 = rural (USDA convention).
#     -> rurality_from_ruca().
#   Tract boundary vintage: the 2016-2020 ACS (data end-year 2020) is the FIRST
#     to use 2020 Census tract boundaries; earlier study years use 2010 tracts.
#     Walker K, "Analyzing US Census Data" ch.7; see CLAUDE.md (2026-06-30 cutoff)
#     and docs/TECHNICAL_APPENDIX_ACS_TRACT_BOUNDARY_VINTAGE_2026-06-30.md.
#     -> tract_vintage_of() / acs_year_of().
#   ACS female-population variables: table B01001 (_026 = female total) vs the
#     race-iterated tables B01001A-I (_017 = female total). U.S. Census Bureau ACS
#     table shells. -> TOTAL_FEMALE_VAR / RACE_FEMALE_VARS (see the _017/_026 footgun).
#   Temporal trend: annual_trend() here is plain OLS with a t-interval; the
#     PUBLISHED trends use Newey-West HAC standard errors (Newey WK, West KD (1987),
#     Econometrica 55(3):703-708, doi:10.2307/1913610) via
#     scripts/inferential_stats_access.R and trend_hac.rds, dropping the
#     right-censored final year (eMethods S1).
#   Design-based aggregation: weighted_mean_all() / zero_access_share() sum over
#     ALL elements (no w>0 filter) so the ratio estimator stays unbiased for
#     sparse groups (Horvitz-Thompson-type reasoning; see the fixed 2026-07-13 bug).
# ==============================================================================

#' Population-weighted mean over ALL elements.
#'
#' Sums over every element; it does NOT drop non-positive weights. Monte-Carlo
#' draws of ACS counts can be negative for zero-estimate tracts, and those must
#' remain in the aggregate so that E[sum(w)] = sum(estimate) stays unbiased.
#' Filtering `w > 0` keeps only the positive halves of near-zero draws and
#' re-introduces a large upward bias for sparse groups (e.g., American Indian or
#' Alaska Native, Native Hawaiian or Other Pacific Islander). For a point
#' estimate (w = estimate >= 0) summing over all elements is identical because
#' zero-weight elements contribute 0 to both numerator and denominator.
#' @param a numeric values (e.g., tract accessibility).
#' @param w numeric weights (e.g., female population), same length as `a`.
#' @return weighted mean, or NA if the weights sum to 0 / non-finite.
#' @seealso [zero_access_share], [mc_weighted_ci]
#' @family accessibility-disparity statistics
#' @examples
#' weighted_mean_all(c(1, 3), c(10, 30))   # 2.5: (1*10 + 3*30) / 40
#' weighted_mean_all(c(5, 5), c(0, 0))     # NA: weights sum to 0
#' # sparse-group safety: a negative MC draw stays in the sum (no w > 0 filter)
#' weighted_mean_all(c(2, 4), c(100, -100)) # NA here only because weights cancel
#' @export
weighted_mean_all <- function(a, w) {
  stopifnot(length(a) == length(w))
  sw <- sum(w)
  if (!is.finite(sw) || sw == 0) return(NA_real_)
  sum(a * w) / sw
}

#' Zero-access share (percent).
#'
#' Percent of weighted population in elements whose value is EXACTLY zero
#' (`access == 0`) — a tract with any positive accessibility, however small, does
#' not count. Sums over all elements (see [weighted_mean_all]).
#' @param access numeric accessibility values.
#' @param w numeric weights.
#' @return percent in [0, 100] under non-negative weights, or NA.
#' @seealso [weighted_mean_all]
#' @family accessibility-disparity statistics
#' @examples
#' zero_access_share(c(0, 2, 0), c(10, 10, 10))  # 66.67: two of three tracts are 0
#' zero_access_share(c(0.01, 5), c(50, 50))      # 0: 0.01 > 0 does not count as zero
#' @export
zero_access_share <- function(access, w) {
  stopifnot(length(access) == length(w))
  sw <- sum(w)
  if (!is.finite(sw) || sw == 0) return(NA_real_)
  100 * sum(w * (access == 0)) / sw
}

#' Map a USDA RUCA primary code to a binary rurality class.
#'
#' Metropolitan = primary RUCA 1-3; Rural = 4-10 (USDA convention).
#' @param code integer-coercible RUCA primary code(s).
#' @return character "Metropolitan"/"Rural" (NA for NA/invalid codes).
#' @references USDA Economic Research Service, Rural-Urban Commuting Area (RUCA)
#'   codes (primary codes 1-3 metropolitan, 4-10 rural). See module header.
#' @family accessibility-disparity statistics
#' @examples
#' rurality_from_ruca(c(1, 3, 4, 10, 99, NA))
#' # "Metropolitan" "Metropolitan" "Rural" "Rural" NA NA  (99 = zero-pop, dropped)
#' @export
rurality_from_ruca <- function(code) {
  code <- suppressWarnings(as.integer(code))
  out <- ifelse(code %in% 1:3, "Metropolitan",
         ifelse(code %in% 4:10, "Rural", NA_character_))
  out[is.na(code)] <- NA_character_
  out
}

#' Census tract boundary vintage for a study year (2010 tracts <=2019, 2020 >=2020).
#'
#' The 2016-2020 ACS (data end-year 2020) is the first to use 2020 Census tract
#' boundaries; keyed off the ACS data year, NOT the isochrone target year.
#' @references Walker K, "Analyzing US Census Data" ch.7; CLAUDE.md (2026-06-30
#'   cutoff note) and docs/TECHNICAL_APPENDIX_ACS_TRACT_BOUNDARY_VINTAGE_2026-06-30.md.
#' @family accessibility-disparity statistics
#' @seealso [acs_year_of]
#' @examples
#' tract_vintage_of(c(2013, 2019, 2020, 2023))  # 2010 2010 2020 2020
#' @export
tract_vintage_of <- function(year) ifelse(as.integer(year) >= 2020L, 2020L, 2010L)

#' ACS 5-year data year for a study year (clamped to the 2013-2022 window).
#'
#' The last released 5-year ACS is 2018-2022 (end-year 2022), so study year 2023
#' is served by the 2022 ACS and flagged provisional/right-censored downstream.
#' @param year integer-coercible study year(s).
#' @return integer ACS data end-year(s), clamped to \[2013, 2022\].
#' @family accessibility-disparity statistics
#' @seealso [tract_vintage_of]
#' @examples
#' acs_year_of(c(2011, 2013, 2020, 2023, 2030))  # 2013 2013 2020 2022 2022
#' @export
acs_year_of <- function(year) pmax(pmin(as.integer(year), 2022L), 2013L)

#' Canonical ACS female-population variable codes.
#'
#' NOTE the footgun: the race-iterated tables (B01001A-I) use `_017` for the
#' FEMALE total, whereas the full B01001 table uses `_026`. Using `_026` on a
#' race table silently returns the wrong cell.
#' @export
TOTAL_FEMALE_VAR <- "B01001_026"
#' @rdname TOTAL_FEMALE_VAR
#' @export
RACE_FEMALE_VARS <- c(white_nh = "B01001H_017", hispanic = "B01001I_017",
                      black = "B01001B_017", aian = "B01001C_017",
                      asian = "B01001D_017", nhpi = "B01001E_017")

#' Monte-Carlo confidence interval for a population-weighted accessibility statistic.
#'
#' Propagates ACS margin-of-error uncertainty in the population weights into the
#' weighted mean (or zero-access share) by redrawing weights ~ Normal(est, se)
#' and recomputing the statistic B times. Draws are NOT clamped and are summed
#' over all elements (see [weighted_mean_all]) so the estimator is unbiased:
#' the point estimate lies inside its own interval.
#' @param access numeric accessibility values (deterministic).
#' @param est numeric weight point estimates (ACS estimates).
#' @param se numeric weight standard errors (ACS MOE / 1.645).
#' @param stat "mean" (weighted mean) or "zero" (zero-access share).
#' @param B number of Monte-Carlo draws.
#' @param probs lower/upper quantiles for the interval.
#' @param seed RNG seed for reproducibility.
#' @return named numeric c(point, lo, hi).
#' @references ACS margin of error is a 90% MOE, so the caller passes se = MOE /
#'   1.645 (U.S. Census Bureau, "Understanding and Using ACS Data", 2020). The
#'   Normal(est, se) redraw is a parametric Monte-Carlo propagation of that
#'   sampling uncertainty into the weighted statistic. See module header.
#' @family accessibility-disparity statistics
#' @seealso [weighted_mean_all], [annual_trend]
#' @examples
#' # Three tracts; access is deterministic, the population weights carry ACS MOE.
#' acc <- c(2.0, 0.0, 5.0)             # tract accessibility (per-100k)
#' est <- c(500, 20, 800)              # ACS female-population estimates
#' se  <- c(60, 15, 90) / 1.645        # ACS 90% MOE converted to SE
#' mc_weighted_ci(acc, est, se, stat = "mean", B = 500)  # c(point, lo, hi)
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

#' Ordinary-least-squares temporal trend of an annual series.
#'
#' @param year integer years, @param value numeric annual estimates.
#' @return named numeric c(slope, lo, hi, p) (95% CI on the slope).
#' @references Plain OLS with a t-interval. The PUBLISHED trends instead use
#'   Newey-West HAC standard errors (Newey WK, West KD (1987) Econometrica
#'   55(3):703-708, doi:10.2307/1913610), dropping the right-censored final year,
#'   in scripts/inferential_stats_access.R / trend_hac.rds (manuscript eMethods S1).
#' @family accessibility-disparity statistics
#' @seealso [mc_weighted_ci]
#' @examples
#' annual_trend(2013:2022, c(10, 11, 10, 12, 13, 12, 14, 15, 14, 16))
#' # slope ~ +0.6/yr with a 95% t-interval and p value
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
