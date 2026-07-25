# M2SFCA (Delamater 2013) + Gaussian-derived zonal decay (McGrail 2012) support
# in the E2SFCA engine. Verifies EXACT analytic values, that Step 1 uses W and
# Step 2 uses W^2 via diff(W^2) (not diff(W)^2), backward compatibility, and that
# M2SFCA discounts distant supply WITHOUT losing input population or providers.
suppressWarnings(suppressMessages(library(testthat)))
source(file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                        rprojroot::is_git_root),
                 "R", "two_step_floating_catchment.R"))

# ============================================================================
# WEIGHT CONVERSION: diff(W^power), NOT diff(W)^power
# ============================================================================
test_that("step2_power=2 increments are diff(W^2), never diff(W)^2", {
  w   <- c("30" = 1.0, "60" = 0.5)
  e2  <- e2sfca_incremental_weights(w, step2_power = 1)   # diff(W)
  m2  <- e2sfca_incremental_weights(w, step2_power = 2)   # diff(W^2)
  expect_equal(unname(e2), c(0.5, 0.5))                   # 1-.5 , .5-0
  expect_equal(unname(m2), c(0.75, 0.25))                # 1-.25, .25-0  = diff(W^2)
  expect_false(isTRUE(all.equal(unname(m2), unname(e2)^2)))  # NOT diff(W)^2 = c(.25,.25)
})

test_that("M2SFCA requires cumulative weights <= 1 (else squaring raises access)", {
  expect_error(e2sfca_incremental_weights(c("30" = 1.2, "60" = 0.5), step2_power = 2),
               "weights <= 1")
  expect_silent(e2sfca_incremental_weights(c("30" = 1.0, "60" = 0.5), step2_power = 2))
})

# ============================================================================
# EXACT ANALYTIC FIXTURE (one provider, two equal-pop tracts, W = 1.0, 0.5)
#   demand denom = 100*1.0 + 100*0.5 = 150 -> provider_ratio = 1/150
#   E2SFCA access = (1/150, 0.5/150),  pop-weighted total = 1.0
#   M2SFCA access = (1/150, 0.25/150), pop-weighted total = 5/6
# ============================================================================
# Overlap is CUMULATIVE: near tract inside the 30-min band (and 60); far tract
# inside only the 60-min band.
ov  <- dplyr::tibble(coord_id = "p",
                     band  = c(30L, 60L, 60L),
                     GEOID = c("near", "near", "far"),
                     overlap_fraction = c(1, 1, 1))
pop <- dplyr::tibble(GEOID = c("near", "far"), female_pop = c(100, 100))
sup <- dplyr::tibble(coord_id = "p", supply = 1)
W   <- c("30" = 1.0, "60" = 0.5)
acc_of <- function(r, g) r$access$access[r$access$GEOID == g]
pw_total <- function(r) sum(r$access$access *
                            pop$female_pop[match(r$access$GEOID, pop$GEOID)])

test_that("E2SFCA reproduces the exact analytic access values and is conservative", {
  r <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 1)
  expect_equal(r$provider_ratios$ratio, 1/150, tolerance = 1e-12)
  expect_equal(acc_of(r, "near"), 1/150,   tolerance = 1e-12)
  expect_equal(acc_of(r, "far"),  0.5/150, tolerance = 1e-12)
  expect_equal(pw_total(r), 1.0, tolerance = 1e-12)          # == total supply
})

test_that("M2SFCA reproduces the exact analytic access values (far tract penalized)", {
  r <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 2)
  expect_equal(r$provider_ratios$ratio, 1/150, tolerance = 1e-12)  # Step 1 UNCHANGED
  expect_equal(acc_of(r, "near"), 1/150,    tolerance = 1e-12)     # near (W=1) unchanged
  expect_equal(acc_of(r, "far"),  0.25/150, tolerance = 1e-12)     # far  (0.5 -> 0.25)
  expect_equal(pw_total(r), 5/6, tolerance = 1e-12)                # < total supply
})

# ============================================================================
# DELAMATER'S CONFIGURATION TEST: identical relative distances, different absolute.
#   A: both demand nodes near (bands 30 & 60).  B: both far (band 60 only).
#   E2SFCA is scale-invariant (A == B). M2SFCA(B) < M2SFCA(A): absolute penalty.
# ============================================================================
ovA <- dplyr::tibble(coord_id = "p",
                     band  = c(30L, 60L, 30L, 60L),
                     GEOID = c("n1", "n1", "n2", "n2"),
                     overlap_fraction = 1)
ovB <- dplyr::tibble(coord_id = "p",
                     band  = c(60L, 60L),
                     GEOID = c("n1", "n2"),
                     overlap_fraction = 1)
pop2 <- dplyr::tibble(GEOID = c("n1", "n2"), female_pop = c(100, 100))
pwt2 <- function(r) sum(r$access$access * pop2$female_pop[match(r$access$GEOID, pop2$GEOID)])

test_that("E2SFCA is configuration-invariant; M2SFCA penalizes the farther config", {
  eA <- compute_e2sfca(ovA, pop2, sup, weights = W, step2_power = 1)
  eB <- compute_e2sfca(ovB, pop2, sup, weights = W, step2_power = 1)
  expect_equal(pwt2(eA), pwt2(eB), tolerance = 1e-12)     # E2SFCA: A == B (1.0)
  mA <- compute_e2sfca(ovA, pop2, sup, weights = W, step2_power = 2)
  mB <- compute_e2sfca(ovB, pop2, sup, weights = W, step2_power = 2)
  expect_equal(pwt2(mA), pwt2(eA), tolerance = 1e-12)     # all near -> M2 == E2
  expect_lt(pwt2(mB), pwt2(mA))                            # farther config -> lower
  expect_equal(pwt2(mB), 0.5, tolerance = 1e-12)          # exact
})

# ============================================================================
# REGRESSION SUITE
# ============================================================================
test_that("step2_power=1 reproduces the existing E2SFCA output exactly (default)", {
  a <- compute_e2sfca(ov, pop, sup, weights = W)               # default power 1
  b <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 1)
  expect_equal(a$access, b$access)
})

test_that("all weights == 1 makes M2SFCA identical to E2SFCA", {
  W1 <- c("30" = 1.0, "60" = 1.0)
  e  <- compute_e2sfca(ov, pop, sup, weights = W1, step2_power = 1)
  m  <- compute_e2sfca(ov, pop, sup, weights = W1, step2_power = 2)
  expect_equal(e$access$access, m$access$access, tolerance = 1e-12)
})

test_that("M2SFCA access is never greater than E2SFCA access (0<=W<=1)", {
  e <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 1)
  m <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 2)
  j <- merge(e$access, m$access, by = "GEOID", suffixes = c("_e", "_m"))
  expect_true(all(j$access_m <= j$access_e + 1e-12))
})

test_that("Step-1 provider ratios are identical between E2SFCA and M2SFCA", {
  e <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 1)
  m <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 2)
  expect_equal(e$provider_ratios, m$provider_ratios)          # only Step 2 differs
})

# 'q' has positive supply but reaches only a zero-population tract -> undefined
# ratio (NA), zero surface contribution, supply accounted as excluded.
ov2z  <- dplyr::bind_rows(ov,
           dplyr::tibble(coord_id = "q", band = 60L, GEOID = "empty", overlap_fraction = 1))
pop2z <- dplyr::bind_rows(pop, dplyr::tibble(GEOID = "empty", female_pop = 0))
sup2z <- dplyr::tibble(coord_id = c("p", "q"), supply = c(1, 1))

test_that("positive-supply zero-demand origins are audited (ratio NA, surface 0)", {
  r <- compute_e2sfca(ov2z, pop2z, sup2z, weights = W, step2_power = 2)
  q <- dplyr::filter(r$provider_ratios, coord_id == "q")
  expect_equal(nrow(q), 1L)
  expect_gt(q$supply, 0)
  expect_equal(q$weighted_demand, 0)
  expect_true(is.na(q$ratio))                    # UNDEFINED, not 0
  expect_equal(q$ratio_for_surface, 0)           # adds no modeled access
  expect_true(q$zero_demand)
  expect_equal(q$excluded_supply, q$supply)
  expect_equal(r$audit$n_zero_demand_origins, 1L)
  expect_equal(r$audit$supply_zero_demand, q$supply)
  expect_true("q" %in% r$audit$zero_demand_coord_ids)
})

test_that("a positive-supply zero-demand origin does not alter the access surface", {
  r0 <- compute_e2sfca(ov,   pop,   sup,   weights = W, step2_power = 2)
  r1 <- compute_e2sfca(ov2z, pop2z, sup2z, weights = W, step2_power = 2)
  a0 <- r0$access$access[match(c("near", "far"), r0$access$GEOID)]
  a1 <- r1$access$access[match(c("near", "far"), r1$access$GEOID)]
  expect_equal(a1, a0, tolerance = 1e-12)
})

test_that("the return object records method + weight metadata", {
  r <- compute_e2sfca(ov, pop, sup, weights = W, step2_power = 2)
  expect_equal(r$method, "M2SFCA")
  expect_equal(r$step2_power, 2)
  expect_equal(unname(r$band_weights), c(1.0, 0.5))
  expect_equal(unname(r$step1_incremental_weights), c(0.5, 0.5))       # diff(W)
  expect_equal(unname(r$step2_incremental_weights), c(0.75, 0.25))     # diff(W^2)
  expect_equal(r$maximum_travel_time, 60L)
  expect_equal(compute_e2sfca(ov, pop, sup, weights = W)$method, "E2SFCA")
})

# ============================================================================
# GAUSSIAN-DERIVED ZONAL WEIGHTS (four-band approximation, NOT continuous)
# ============================================================================
test_that("raw Gaussian decay equals one only at zero and decays monotonically", {
  m   <- c(0, 30, 60, 120, 180)
  raw <- gaussian_decay_weights(m, sigma = 60)
  expect_equal(unname(raw[1]), 1)                           # G(0) == 1 only at zero
  expect_true(all(raw >= 0 & raw <= 1))
  expect_true(all(diff(raw) <= 0))
  expect_lt(unname(raw["30"]), 1)                           # raw G(30) < 1 (un-normalized)
})

test_that("zonal path == raw kernel normalized to the first band, with metadata", {
  bands <- c(30, 60, 120, 180)
  raw   <- gaussian_decay_weights(bands, sigma = 60)
  z     <- gaussian_band_weights(bands, sigma = 60)
  expect_equal(as.numeric(z), unname(raw / raw[1]), tolerance = 1e-12)   # contract
  expect_lt(unname(raw["30"]), 1)                           # raw un-normalized at 30
  expect_equal(unname(z["30"]), 1)                          # zonal normalized to 1
  meta <- attr(z, "decay_meta")
  expect_equal(meta$decay_function, "gaussian")
  expect_equal(meta$decay_type, "zonal")
  expect_equal(meta$normalization, "first_band")
  expect_equal(meta$normalization_minutes, 30L)
  expect_equal(meta$sigma_minutes, 60)
  expect_equal(meta$maximum_minutes, 180L)
})

test_that("gaussian_band_weights are finite, in [0,1], monotone non-increasing", {
  g <- gaussian_band_weights(c(30, 60, 120, 180), sigma = 60)
  expect_true(all(is.finite(g)))
  expect_true(all(g >= 0 & g <= 1))
  expect_true(all(diff(g) <= 0))
})

test_that("gaussian_band_weights requires sigma > 0 and preserves band names/order", {
  expect_error(gaussian_band_weights(c(30, 60), sigma = 0), "sigma")
  expect_error(gaussian_band_weights(c(30, 60), sigma = -5), "sigma")
  g <- gaussian_band_weights(c(180, 30, 60), sigma = 60)     # returns sorted 30/60/180
  expect_equal(names(g), c("30", "60", "180"))
})

test_that("beyond the last band the incremental convention gives the band's own weight (i.e. W_next=0)", {
  g <- gaussian_band_weights(c(30, 60, 120, 180), sigma = 60)
  inc <- e2sfca_incremental_weights(g)
  expect_equal(unname(inc["180"]), unname(g["180"]), tolerance = 1e-12)  # last band: W_180 - 0
})

test_that("default gaussian weights are frozen to their exact values (sigma = 60)", {
  g <- gaussian_band_weights(c(30, 60, 120, 180), sigma = 60)
  raw <- exp(-(c(30, 60, 120, 180)^2) / (2 * 60^2))
  expect_equal(as.numeric(g), unname(raw / raw[1]), tolerance = 1e-12)
  expect_equal(round(as.numeric(g), 4), c(1.0000, 0.6873, 0.1534, 0.0126))  # snapshot
})
