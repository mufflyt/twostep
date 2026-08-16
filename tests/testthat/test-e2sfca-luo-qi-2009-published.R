# =============================================================================
# External methodological reference: Luo & Qi (2009), the paper that DEFINES E2SFCA.
# =============================================================================
# Every other scientific test in this repository checks twostep against
# twostep's own reading of the method: invariants derived from the engine's
# stated equations, references implemented from its module header. That is
# self-referential. If the module header itself misread the method, all of it
# would agree on the wrong answer.
#
# This file closes that loop. It encodes the PUBLISHED formulation -- discrete
# travel-time zones with zone weights, exactly as Luo & Qi state it -- computes
# the expected values by hand from their equations, freezes them in
# tests/fixtures/luo_qi_2009_e2sfca.json, and requires twostep to reproduce
# them.
#
#   Step 1   R_j = S_j / SUM_r SUM_{k in zone r} P_k W_r
#   Step 2   A_i = SUM_r SUM_{j in zone r} R_j W_r
#
# The interesting part is that twostep does NOT implement it that way. Its
# isochrone artifacts are cumulative, so it applies incremental weights
# w'_b = W_b - W_{b+1} to cumulative bands and appeals to Abel summation for
# equivalence. That equivalence is the central mathematical claim of
# R/two_step_floating_catchment.R. Here it is checked against the published
# ring definition rather than asserted.
#
# Erratum note: the fixture records the published erratum to weight set 2
# (reported 0.09, should be 0.03 to follow the Gaussian strictly; the authors
# used 0.09, so the paper's own results are internally consistent). It is not
# used in these assertions -- weight set 1 is -- but anyone reproducing the
# paper's tables needs to know which value was actually used.

fx_path <- file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                            rprojroot::is_git_root),
                     "tests", "fixtures", "luo_qi_2009_e2sfca.json")

test_that("the published fixture is present and parses", {
  expect_true(file.exists(fx_path))
  expect_silent(jsonlite::fromJSON(fx_path, simplifyVector = FALSE))
})

LQ <- jsonlite::fromJSON(fx_path, simplifyVector = FALSE)

# --- the published method, implemented directly from the equations -----------
# Discrete zones, no cumulative bands, no twostep helpers.
luo_qi_e2sfca <- function(zone_of_tract, pop, supply, zone_weights) {
  # Step 1
  demand <- 0
  for (g in names(zone_of_tract))
    demand <- demand + pop[[g]] * zone_weights[[as.character(zone_of_tract[[g]])]]
  R <- supply / demand
  # Step 2 (single provider: A_i = W_{r(i)} * R)
  acc <- vapply(names(zone_of_tract),
                function(g) zone_weights[[as.character(zone_of_tract[[g]])]] * R,
                numeric(1))
  list(demand = demand, R = R, access = acc)
}

test_that("the published weight set 1 is what twostep's canonical weights use", {
  w1 <- as.numeric(unlist(LQ$weight_set_1$weights))
  expect_equal(w1, c(1.00, 0.68, 0.22))
  # twostep's canonical vector extends the published three-zone set with a
  # fourth, wider band. The first three must remain the published values.
  expect_equal(unname(E2SFCA_DEFAULT_WEIGHTS)[1:3], w1, tolerance = 1e-12)
})

test_that("hand-derived Step 1 and Step 2 values match the frozen fixture", {
  we  <- LQ$worked_example
  zt  <- vapply(we$tracts, function(t) t$zone_minutes, numeric(1))
  names(zt) <- vapply(we$tracts, function(t) t$GEOID, character(1))
  pop <- vapply(we$tracts, function(t) t$population, numeric(1))
  names(pop) <- names(zt)
  zw  <- stats::setNames(as.list(c(1.00, 0.68, 0.22)), c("10", "20", "30"))

  got <- luo_qi_e2sfca(as.list(zt), as.list(pop), we$supply$P1, zw)

  expect_equal(got$demand, we$step1_provider_to_population_ratio$weighted_demand,
               tolerance = 1e-12)
  expect_equal(got$R, we$step1_provider_to_population_ratio$R_P1, tolerance = 1e-12)
  for (g in c("T1", "T2", "T3"))
    expect_equal(unname(got$access[[g]]), we$step2_accessibility[[g]], tolerance = 1e-12)
})

test_that("twostep reproduces the published worked example exactly", {
  we <- LQ$worked_example
  # Translate the published RING system into the CUMULATIVE representation
  # twostep consumes: a tract is inside every band at least as wide as its zone.
  memb <- LQ$cumulative_band_translation$cumulative_overlap
  memb <- memb[!startsWith(names(memb), "_")]   # drop the fixture's _comment key
  ov <- do.call(rbind, lapply(names(memb), function(g)
    data.frame(coord_id = "P1", GEOID = g,
               band = as.integer(unlist(memb[[g]])),
               overlap_fraction = 1, stringsAsFactors = FALSE)))
  pop <- data.frame(
    GEOID = vapply(we$tracts, function(t) t$GEOID, character(1)),
    female_pop = vapply(we$tracts, function(t) t$population, numeric(1)),
    stringsAsFactors = FALSE)
  sup <- data.frame(coord_id = "P1", supply = we$supply$P1, stringsAsFactors = FALSE)

  W <- c("10" = 1.00, "20" = 0.68, "30" = 0.22)
  res <- compute_e2sfca(ov, pop, sup, weights = W)

  # Step 1: the weighted demand must equal the published ring computation.
  expect_equal(res$provider_ratios$weighted_demand[1],
               we$step1_provider_to_population_ratio$weighted_demand, tolerance = 1e-9)
  expect_equal(res$provider_ratios$ratio[1],
               we$step1_provider_to_population_ratio$R_P1, tolerance = 1e-12)

  # Step 2: every tract's accessibility, and the per-100k scaling.
  acc <- as.data.frame(res$access)
  for (g in c("T1", "T2", "T3")) {
    expect_equal(acc$access[acc$GEOID == g], we$step2_accessibility[[g]],
                 tolerance = 1e-12, info = paste("tract", g))
    expect_equal(acc$access_scaled[acc$GEOID == g],
                 we$step2_accessibility_per_100k[[g]], tolerance = 1e-9)
  }
})

test_that("the incremental weights are the published cumulative weights differenced", {
  tr <- LQ$cumulative_band_translation
  W  <- unlist(tr$cumulative_weights)
  expect_equal(as.numeric(e2sfca_incremental_weights(W)),
               as.numeric(unlist(tr$incremental_weights)), tolerance = 1e-12)
  # Telescoping: the increments sum to the innermost cumulative weight.
  expect_equal(sum(as.numeric(unlist(tr$incremental_weights))), 1.00, tolerance = 1e-12)
})

test_that("ABEL EQUIVALENCE: cumulative bands reproduce the published ring method in general", {
  # The worked example is one system. This is the general claim: for RANDOM ring
  # systems, twostep's cumulative-band formulation must equal the published
  # ring-based one exactly. If Abel summation were misapplied -- differencing the
  # wrong direction, dropping the outermost term, or treating W beyond the last
  # band as anything but 0 -- these would diverge.
  zones <- c(10, 20, 30)
  zw    <- c("10" = 1.00, "20" = 0.68, "30" = 0.22)
  for (s in 701:712) {
    set.seed(s)
    n <- sample(3:9, 1)
    g <- sprintf("T%02d", seq_len(n))
    z <- sample(zones, n, replace = TRUE)
    p <- round(stats::runif(n, 50, 5000))
    S <- round(stats::runif(1, 1, 30))

    ring <- luo_qi_e2sfca(as.list(stats::setNames(z, g)),
                          as.list(stats::setNames(p, g)), S,
                          stats::setNames(as.list(unname(zw)), names(zw)))

    ov <- do.call(rbind, lapply(seq_len(n), function(i)
      data.frame(coord_id = "P1", GEOID = g[i],
                 band = zones[zones >= z[i]],       # cumulative membership
                 overlap_fraction = 1, stringsAsFactors = FALSE)))
    res <- compute_e2sfca(ov,
                          data.frame(GEOID = g, female_pop = p, stringsAsFactors = FALSE),
                          data.frame(coord_id = "P1", supply = S, stringsAsFactors = FALSE),
                          weights = zw)
    acc <- as.data.frame(res$access)
    expect_equal(acc$access[match(g, acc$GEOID)], unname(ring$access[g]),
                 tolerance = 1e-12,
                 info = paste("ring and cumulative formulations diverged, seed", s))
  }
})
