# Adversarial + semantic tests for R/accessibility_stratification.R — the
# population-weighted accessibility-disparity statistics behind the E2SFCA
# manuscript (rurality/race stratification + Monte-Carlo confidence intervals).
#
# The centerpiece is a REGRESSION GUARD for the clamp/filter bug caught
# 2026-07-13, in which the Monte-Carlo estimator dropped negative draws (or
# clamped them to zero), injecting spurious weight into the many zero-estimate
# tracts of sparse groups (American Indian/Alaska Native, Native Hawaiian/Pacific
# Islander) and pushing the point estimate OUTSIDE its own confidence interval.

suppressWarnings({ library(testthat) })
source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))

# ==============================================================================
# ADVERSARIAL — weighted_mean_all / zero_access_share
# ==============================================================================

test_that("weighted_mean_all sums over ALL elements (does NOT filter w>0)", {
  a <- c(1, 2, 3); w <- c(-1, 1, 1)
  # correct: (1*-1 + 2*1 + 3*1) / (-1+1+1) = 4 / 1 = 4
  expect_equal(weighted_mean_all(a, w), 4)
  # the OLD buggy version filtered w>0 -> (2+3)/2 = 2.5; guard against regressing to it
  expect_false(isTRUE(all.equal(weighted_mean_all(a, w), 2.5)))
})

test_that("weighted_mean_all equals the naive point mean for non-negative weights", {
  a <- c(0.1, 0.5, 0.9); w <- c(0, 100, 300)     # a zero-weight element must not matter
  expect_equal(weighted_mean_all(a, w), (0.5*100 + 0.9*300)/400)
})

test_that("weighted_mean_all is bounded by [min(a), max(a)] under non-negative weights", {
  set.seed(1)
  for (i in 1:50) {
    a <- runif(20); w <- runif(20, 0, 10)
    m <- weighted_mean_all(a, w)
    expect_gte(m, min(a) - 1e-12); expect_lte(m, max(a) + 1e-12)
  }
})

test_that("degenerate weights return NA, never Inf/NaN/error", {
  expect_true(is.na(weighted_mean_all(c(1, 2), c(0, 0))))
  expect_true(is.na(zero_access_share(c(0, 1), c(0, 0))))
  expect_true(is.na(weighted_mean_all(c(1, 2), c(1, -1))))   # weights sum to 0
})

test_that("zero_access_share counts EXACT zeros only (tiny positive access is not zero)", {
  access <- c(0, 1e-9, 0.5)
  w <- c(100, 100, 100)
  # only the first tract is zero-access
  expect_equal(zero_access_share(access, w), 100 * 100 / 300)
  expect_true(zero_access_share(c(1e-12, 1e-12), c(1, 1)) == 0)   # no exact zeros
  expect_true(zero_access_share(c(0, 0), c(5, 5)) == 100)         # all zero
})

test_that("zero_access_share stays within [0,100] for non-negative weights", {
  set.seed(2)
  for (i in 1:50) {
    access <- rbinom(30, 1, 0.3) * runif(30)      # ~30% exact zeros
    w <- runif(30, 0, 1000)
    z <- zero_access_share(access, w)
    expect_gte(z, 0); expect_lte(z, 100)
  }
})

# ==============================================================================
# ADVERSARIAL — Monte-Carlo estimator (the bug that motivated this file)
# ==============================================================================

# Synthetic "sparse group" that reproduces the failure mode: 70% of tracts have a
# ZERO ACS estimate but a positive MOE (the ACS minimum-MOE artifact), and those
# zero-estimate tracts are the HIGH-access (urban) ones; the group's actual
# population sits in the 30% of tracts that are ZERO-access (rural). Truth:
# weighted mean access = 0, zero-access share = 100%.
make_sparse_group <- function(n_zero = 70, n_pos = 30, se_zero = 8, est_pos = 50, se_pos = 10) {
  access <- c(rep(1, n_zero), rep(0, n_pos))       # zero-est tracts are high-access
  est    <- c(rep(0, n_zero), rep(est_pos, n_pos)) # population lives in zero-access tracts
  se     <- c(rep(se_zero, n_zero), rep(se_pos, n_pos))
  list(access = access, est = est, se = se)
}

test_that("MC point estimate lies INSIDE its own CI for a sparse group (regression: clamp/filter bug)", {
  g <- make_sparse_group()
  ci_mean <- mc_weighted_ci(g$access, g$est, g$se, stat = "mean", B = 3000, seed = 42)
  ci_zero <- mc_weighted_ci(g$access, g$est, g$se, stat = "zero", B = 3000, seed = 42)
  # point estimates are the deterministic truth
  expect_equal(unname(ci_mean["point"]), 0)
  expect_equal(unname(ci_zero["point"]), 100)
  # THE GUARD: the point must fall within [lo, hi]. The buggy estimator returned
  # a CI shifted away from 0 / below 100, excluding the point.
  expect_gte(unname(ci_mean["point"]), unname(ci_mean["lo"]) - 1e-9)
  expect_lte(unname(ci_mean["point"]), unname(ci_mean["hi"]) + 1e-9)
  expect_gte(unname(ci_zero["point"]), unname(ci_zero["lo"]) - 1e-9)
  expect_lte(unname(ci_zero["point"]), unname(ci_zero["hi"]) + 1e-9)
})

test_that("MC estimator is unbiased: mean of draws ~ point estimate for a sparse group", {
  g <- make_sparse_group()
  f <- get("weighted_mean_all")
  set.seed(7); B <- 4000
  draws <- vapply(seq_len(B), function(b) f(g$access, rnorm(length(g$est), g$est, g$se)), numeric(1))
  # unbiased: E[draw] ~ point (0). A clamp/filter would push this strongly positive.
  expect_lt(abs(mean(draws, na.rm = TRUE) - 0), 0.05)
})

test_that("MC CI is reproducible under a fixed seed and widens with larger SE", {
  g <- make_sparse_group()
  a <- mc_weighted_ci(g$access, g$est, g$se, "mean", B = 1000, seed = 99)
  b <- mc_weighted_ci(g$access, g$est, g$se, "mean", B = 1000, seed = 99)
  expect_identical(a, b)                                   # deterministic under seed
  narrow <- mc_weighted_ci(c(0.4, 0.6), c(1e6, 1e6), c(50, 50), "mean", B = 800, seed = 1)
  wide   <- mc_weighted_ci(c(0.4, 0.6), c(1e6, 1e6), c(5e5, 5e5), "mean", B = 800, seed = 1)
  expect_gt((wide["hi"] - wide["lo"]), (narrow["hi"] - narrow["lo"]))
})

# ==============================================================================
# SEMANTIC — rurality, vintage, ACS-year, race variables
# ==============================================================================

test_that("rurality_from_ruca uses the USDA cut at 3|4 (Metro 1-3, Rural 4-10)", {
  expect_equal(rurality_from_ruca(c(1, 2, 3, 4, 7, 10)),
               c("Metropolitan","Metropolitan","Metropolitan","Rural","Rural","Rural"))
  expect_true(is.na(rurality_from_ruca(NA)))
  expect_true(is.na(rurality_from_ruca(99)))               # RUCA 99 = not coded
  expect_equal(rurality_from_ruca("3"), "Metropolitan")    # character input
})

test_that("tract_vintage_of switches at the 2019|2020 boundary", {
  expect_equal(tract_vintage_of(c(2013, 2019, 2020, 2023)), c(2010, 2010, 2020, 2020))
})

test_that("acs_year_of clamps to the 2013-2022 ACS window", {
  expect_equal(acs_year_of(c(2010, 2013, 2019, 2022, 2023)), c(2013, 2013, 2019, 2022, 2022))
})

test_that("race female variables use the _017 suffix, never the full-table _026 (footgun guard)", {
  expect_true(all(grepl("_017$", RACE_FEMALE_VARS)))
  expect_false(any(grepl("_026$", RACE_FEMALE_VARS)))
  expect_equal(unname(TOTAL_FEMALE_VAR), "B01001_026")
  # race codes are the race-iterated tables B01001[B-I], not the base table
  expect_true(all(grepl("^B01001[A-I]_", RACE_FEMALE_VARS)))
  expect_setequal(names(RACE_FEMALE_VARS),
                  c("white_nh","hispanic","black","aian","asian","nhpi"))
})

# ==============================================================================
# SEMANTIC — population-weighting and trend behave meaningfully
# ==============================================================================

test_that("a group concentrated in high-access tracts has higher weighted access", {
  access <- c(0.1, 0.1, 0.9, 0.9)
  urban_grp <- c(1, 1, 100, 100)      # lives where access is high
  rural_grp <- c(100, 100, 1, 1)      # lives where access is low
  expect_gt(weighted_mean_all(access, urban_grp), weighted_mean_all(access, rural_grp))
})

test_that("a group entirely in zero-access tracts has 100% zero share; none -> 0%", {
  access <- c(0, 0, 0.5, 0.7)
  expect_equal(zero_access_share(access, c(10, 10, 0, 0)), 100)
  expect_equal(zero_access_share(access, c(0, 0, 10, 10)), 0)
})

test_that("annual_trend recovers the sign and magnitude of a synthetic trend", {
  yr <- 2013:2022
  declining <- 10 - 0.2 * (yr - 2013)         # slope -0.2/yr
  tr <- annual_trend(yr, declining)
  expect_equal(unname(tr["slope"]), -0.2, tolerance = 1e-8)
  expect_lt(unname(tr["p"]), 1e-6)            # a perfect line is highly significant
  flat <- annual_trend(yr, rep(5, length(yr)))
  expect_equal(unname(flat["slope"]), 0, tolerance = 1e-8)
})

test_that("annual_trend returns NA (not an error) with too few points", {
  tr <- annual_trend(c(2013, 2014), c(1, 2))
  expect_true(all(is.na(tr)))
})

# ==============================================================================
# ADVERSARIAL — input validation & numerical edge cases
# ==============================================================================

test_that("length-mismatched inputs error rather than silently recycling", {
  expect_error(weighted_mean_all(c(1, 2), c(1, 2, 3)))
  expect_error(zero_access_share(c(0, 1, 0), c(1, 2)))
  expect_error(mc_weighted_ci(c(0, 1), c(1, 1, 1), c(1, 1), "mean", B = 10))
})

test_that("non-finite weights collapse to NA, never Inf/NaN", {
  expect_true(is.na(weighted_mean_all(c(1, 2), c(Inf, 1))))     # sum(w) = Inf
  expect_true(is.na(weighted_mean_all(c(1, 2), c(Inf, -Inf))))  # sum(w) = NaN
  expect_true(is.na(zero_access_share(c(0, 1), c(NaN, 1))))
})

test_that("single-element input returns that element's value", {
  expect_equal(weighted_mean_all(0.7, 1000), 0.7)
  expect_equal(zero_access_share(0, 1000), 100)
  expect_equal(zero_access_share(0.5, 1000), 0)
})

test_that("zero_access_share never miscounts NEGATIVE access as zero", {
  # only the EXACT zero counts; a negative value is not "no access == 0"
  expect_equal(zero_access_share(c(-1, 0, 1), c(1, 1, 1)), 100 / 3)
  expect_equal(zero_access_share(c(-3, -2, -1), c(1, 1, 1)), 0)
})

# ==============================================================================
# ADVERSARIAL — mc_weighted_ci robustness
# ==============================================================================

test_that("mc_weighted_ci rejects invalid stat and negative standard errors", {
  expect_error(mc_weighted_ci(c(0, 1), c(1, 1), c(1, 1), stat = "banana", B = 10))
  expect_error(mc_weighted_ci(c(0, 1), c(1, 1), c(-1, 1), stat = "mean", B = 10))
})

test_that("mc_weighted_ci with zero SE returns a zero-width interval at the point", {
  ci <- mc_weighted_ci(c(0, 1, 0.5), c(100, 200, 300), c(0, 0, 0), "mean", B = 200, seed = 3)
  expect_equal(unname(ci["lo"]), unname(ci["point"]))
  expect_equal(unname(ci["hi"]), unname(ci["point"]))
})

test_that("mc_weighted_ci treats NA standard errors as zero uncertainty (not an error)", {
  # NA SE -> that weight is drawn with sd 0, i.e. fixed at its estimate
  ci_na  <- mc_weighted_ci(c(0, 1), c(100, 200), c(NA, NA), "mean", B = 300, seed = 5)
  ci_zero<- mc_weighted_ci(c(0, 1), c(100, 200), c(0,  0),  "mean", B = 300, seed = 5)
  expect_equal(unname(ci_na["lo"]), unname(ci_na["hi"]))            # zero-width
  expect_equal(ci_na, ci_zero)                                      # NA behaves as 0
})

test_that("mc_weighted_ci narrows as the requested probability mass shrinks", {
  g <- make_sparse_group()
  wide   <- mc_weighted_ci(g$access, g$est, g$se, "mean", B = 3000, seed = 11, probs = c(0.025, 0.975))
  narrow <- mc_weighted_ci(g$access, g$est, g$se, "mean", B = 3000, seed = 11, probs = c(0.25, 0.75))
  expect_gt((wide["hi"] - wide["lo"]), (narrow["hi"] - narrow["lo"]))
})

test_that("MC zero-access share for a sparse group is unbiased and brackets its point", {
  g <- make_sparse_group()
  ci <- mc_weighted_ci(g$access, g$est, g$se, stat = "zero", B = 4000, seed = 13)
  expect_equal(unname(ci["point"]), 100)                           # truth: 100% zero-access
  expect_gte(unname(ci["point"]), unname(ci["lo"]) - 1e-9)
  expect_lte(unname(ci["point"]), unname(ci["hi"]) + 1e-9)
})

# ==============================================================================
# SEMANTIC — metamorphic invariances of the weighted estimators
# ==============================================================================

test_that("weighted_mean_all is invariant to positive rescaling of the weights", {
  set.seed(20)
  for (i in 1:40) {
    a <- runif(25); w <- runif(25, 0, 8); k <- runif(1, 0.01, 100)
    expect_equal(weighted_mean_all(a, k * w), weighted_mean_all(a, w))
  }
})

test_that("weighted_mean_all is permutation-invariant", {
  set.seed(21)
  a <- runif(30); w <- runif(30, 0, 5); p <- sample(seq_along(a))
  expect_equal(weighted_mean_all(a[p], w[p]), weighted_mean_all(a, w))
})

test_that("weighted_mean_all shifts by exactly c when access shifts by c", {
  set.seed(22)
  a <- runif(15); w <- runif(15, 0, 5)
  expect_equal(weighted_mean_all(a + 4.2, w), weighted_mean_all(a, w) + 4.2)
})

test_that("a pooled weighted mean lies between the two group means (pooling law)", {
  set.seed(23)
  for (i in 1:40) {
    a1 <- runif(10, 0, 1); w1 <- runif(10, 1, 5)
    a2 <- runif(10, 2, 3); w2 <- runif(10, 1, 5)   # group 2 strictly higher access
    m1 <- weighted_mean_all(a1, w1); m2 <- weighted_mean_all(a2, w2)
    pooled <- weighted_mean_all(c(a1, a2), c(w1, w2))
    expect_gte(pooled, min(m1, m2) - 1e-12)
    expect_lte(pooled, max(m1, m2) + 1e-12)
  }
})

test_that("zero_access_share is invariant to positive weight rescaling and is monotone", {
  set.seed(24)
  access <- c(0, 0, 0.3, 0.8, 0)
  w <- c(100, 50, 200, 300, 10)
  expect_equal(zero_access_share(access, 7 * w), zero_access_share(access, w))
  # adding a NEW zero-access tract with positive weight cannot lower the share
  before <- zero_access_share(access, w)
  after  <- zero_access_share(c(access, 0), c(w, 500))
  expect_gte(after, before - 1e-12)
})

# ==============================================================================
# SEMANTIC — race-code assignment (a swap silently inverts the headline finding)
# ==============================================================================

test_that("each race key maps to its EXACT ACS B01001 female code", {
  # A swap of C<->D would silently turn the manuscript's American Indian/Alaska
  # Native deficit into an Asian one (and vice versa). Pin every code.
  expect_equal(unname(RACE_FEMALE_VARS["white_nh"]), "B01001H_017")
  expect_equal(unname(RACE_FEMALE_VARS["black"]),    "B01001B_017")
  expect_equal(unname(RACE_FEMALE_VARS["aian"]),     "B01001C_017")
  expect_equal(unname(RACE_FEMALE_VARS["asian"]),    "B01001D_017")
  expect_equal(unname(RACE_FEMALE_VARS["nhpi"]),     "B01001E_017")
  expect_equal(unname(RACE_FEMALE_VARS["hispanic"]), "B01001I_017")
  expect_false(anyDuplicated(RACE_FEMALE_VARS) > 0)               # no code reused
})

# ==============================================================================
# SEMANTIC — RUCA 99 exclusion (the 2026-07-14 change)
# ==============================================================================

test_that("rurality_from_ruca returns NA for RUCA 99 and other uncoded values", {
  expect_true(is.na(rurality_from_ruca(99)))                      # the zero-pop 'not coded' bucket
  expect_true(is.na(rurality_from_ruca(0)))                       # below the valid 1-10 range
  expect_true(is.na(rurality_from_ruca(11)))                      # above it
  expect_true(is.na(rurality_from_ruca(-5)))
  expect_true(is.na(rurality_from_ruca("not-a-number")))
  # a mixed vector keeps the valid codes and NAs the rest
  expect_equal(rurality_from_ruca(c(1, 99, 7, 0, 3)),
               c("Metropolitan", NA, "Rural", NA, "Metropolitan"))
})

test_that("dropping zero-weight (RUCA-99-style) tracts leaves weighted stats unchanged", {
  # RUCA-99 tracts carry zero female population; excluding them must not move any
  # weighted number -- the invariant behind 'exclude RUCA 99' being a no-op.
  access <- c(0.2, 0.0, 0.9, 0.5)
  w      <- c(100, 300, 200, 400)
  # append two zero-weight "uncoded" tracts, then drop them
  access2 <- c(access, 1.0, 0.0)
  w2      <- c(w, 0, 0)
  expect_equal(weighted_mean_all(access2, w2), weighted_mean_all(access, w))
  expect_equal(zero_access_share(access2, w2), zero_access_share(access, w))
})

# ==============================================================================
# REGRESSION — production wiring equivalence (stratify_allyears_access.R)
# ==============================================================================
# stratify_allyears_access.R wraps the module estimators with NA-zeroing so its
# point estimates are byte-identical to the historical inline `!is.na & w>0`
# filter. This test PINS that equivalence: it fails if anyone reintroduces the
# w>0 filter in the module, or changes the module in a way that breaks the
# number-preservation guarantee proved when the script was wired (2026-07-14).

test_that("wired wmean/zshare reproduce the historical inline estimators (non-negative ACS weights)", {
  # exact copies of the pre-wiring inline helpers
  wmean_old  <- function(x, w){ ok <- !is.na(x) & !is.na(w) & w > 0
    if (!any(ok)) return(NA_real_); sum(x[ok] * w[ok]) / sum(w[ok]) }
  zshare_old <- function(a, w){ ok <- !is.na(w) & w > 0
    if (!any(ok)) return(NA_real_); sum(w[ok][a[ok] == 0]) / sum(w[ok]) }
  # the wrappers as defined in scripts/stratify_allyears_access.R
  wmean_new  <- function(x, w){ bad <- is.na(x) | is.na(w); x[bad] <- 0; w[bad] <- 0; weighted_mean_all(x, w) }
  zshare_new <- function(a, w){ bad <- is.na(a) | is.na(w); a[bad] <- 0; w[bad] <- 0; zero_access_share(a, w) / 100 }

  set.seed(4242); mism <- 0L
  for (i in 1:3000) {
    n <- sample(1:60, 1)
    a <- ifelse(runif(n) < 0.30, 0, runif(n, 0, 3))     # access: script sets NA->0 first, so never NA
    w <- pmax(0, round(rnorm(n, 500, 800)))             # non-negative ACS counts
    w[runif(n) < 0.06] <- NA                             # some tracts missing from ACS
    ow <- wmean_old(a, w);  nw <- wmean_new(a, w)
    oz <- zshare_old(a, w); nz <- zshare_new(a, w)
    eqw <- (is.na(ow) && is.na(nw)) || isTRUE(all.equal(ow, nw, tolerance = 1e-12))
    eqz <- (is.na(oz) && is.na(nz)) || isTRUE(all.equal(oz, nz, tolerance = 1e-12))
    if (!eqw || !eqz) mism <- mism + 1L
  }
  expect_equal(mism, 0L)
})
