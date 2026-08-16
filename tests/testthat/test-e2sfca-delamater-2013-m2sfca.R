# =============================================================================
# External methodological reference: Delamater (2013), which DEFINES M2SFCA.
# =============================================================================
# The second external oracle in this repository. Luo & Qi pins E2SFCA; this pins
# the M2SFCA variant that twostep exposes through `step2_power = 2`.
#
# It exists for a specific reason. The mutation corpus
# (tools/ci/mutation_corpus.R) reported that `m2_exponent_removed` -- M2SFCA
# silently collapsing into E2SFCA -- was killed by exactly ONE suite, although
# four had the chance. That mutant is the most dangerous kind: every model still
# converges, every table still renders, every number stays plausible, and the
# paper's sensitivity analysis quietly becomes a duplicate of its primary
# analysis. One suite standing between that and publication was too few, and a
# second copy of the same assertion would not have helped. An independent
# derivation from the published equations is a different kind of evidence.
#
#   Step 1   D_ij = S_j * W_ij / SUM_i ( P_i * W_ij )     <- weight in the NUMERATOR
#   Step 2   A_i  = SUM_j ( D_ij * W_ij )                 <- and again here
#   =>       A_i  = SUM_j ( W_ij^2 * S_j / SUM_i P_i W_ij )
#
# The denominator keeps a SINGLE W. That asymmetry is the entire method: it
# discounts access that exists only across distance, which is what
# "suboptimally configured" means. M2SFCA differs from E2SFCA by exactly one
# term, which is why the two are so easy to confuse in output.

fx_path <- file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                            rprojroot::is_git_root),
                     "tests", "fixtures", "delamater_2013_m2sfca.json")

test_that("the Delamater fixture is present and parses", {
  expect_true(file.exists(fx_path))
  expect_silent(jsonlite::fromJSON(fx_path, simplifyVector = FALSE))
})

DM <- jsonlite::fromJSON(fx_path, simplifyVector = FALSE)

# --- the published method, implemented straight from the equations -----------
# Discrete zones, no cumulative bands, no twostep helpers.
delamater_m2sfca <- function(zone_of_tract, pop, supply, zone_weights) {
  den <- 0
  for (g in names(zone_of_tract))
    den <- den + pop[[g]] * zone_weights[[as.character(zone_of_tract[[g]])]]
  vapply(names(zone_of_tract), function(g) {
    w <- zone_weights[[as.character(zone_of_tract[[g]])]]
    (supply * w / den) * w                       # Eq. 4 then Eq. 5
  }, numeric(1))
}

.fixture_inputs <- function() {
  we  <- DM$worked_example
  zt  <- vapply(we$tracts, function(t) t$zone_minutes, numeric(1))
  names(zt) <- vapply(we$tracts, function(t) t$GEOID, character(1))
  pop <- vapply(we$tracts, function(t) t$population, numeric(1)); names(pop) <- names(zt)
  zw  <- stats::setNames(as.list(c(1.00, 0.68, 0.22)), c("10", "20", "30"))
  list(we = we, zt = zt, pop = pop, zw = zw)
}

test_that("hand-derived M2SFCA values match the frozen fixture", {
  x <- .fixture_inputs()
  got <- delamater_m2sfca(as.list(x$zt), as.list(x$pop), x$we$supply$P1, x$zw)
  for (g in c("T1", "T2", "T3"))
    expect_equal(unname(got[[g]]), x$we$m2sfca_accessibility[[g]], tolerance = 1e-14,
                 info = paste("tract", g))
})

test_that("twostep with step2_power = 2 reproduces the published M2SFCA exactly", {
  x <- .fixture_inputs()
  zones <- c(10, 20, 30)
  W <- c("10" = 1.00, "20" = 0.68, "30" = 0.22)

  # Translate the published RING system into twostep's CUMULATIVE representation.
  g <- names(x$zt)
  ov <- do.call(rbind, lapply(seq_along(g), function(i)
    data.frame(coord_id = "P1", GEOID = g[i],
               band = zones[zones >= x$zt[[i]]],
               overlap_fraction = 1, stringsAsFactors = FALSE)))
  res <- compute_e2sfca(ov,
    data.frame(GEOID = g, female_pop = unname(x$pop), stringsAsFactors = FALSE),
    data.frame(coord_id = "P1", supply = x$we$supply$P1, stringsAsFactors = FALSE),
    weights = W, step2_power = 2)

  # The denominator is NOT squared -- it must equal the E2SFCA one.
  expect_equal(res$provider_ratios$weighted_demand[1],
               x$we$shared_denominator$value, tolerance = 1e-9)

  acc <- as.data.frame(res$access)
  for (gg in c("T1", "T2", "T3"))
    expect_equal(acc$access[acc$GEOID == gg], x$we$m2sfca_accessibility[[gg]],
                 tolerance = 1e-14, info = paste("tract", gg))

  expect_identical(res$method, "M2SFCA")
})

test_that("M2SFCA sits strictly below E2SFCA except where the weight is 1", {
  x <- .fixture_inputs()
  m2 <- x$we$m2sfca_accessibility
  e2 <- x$we$e2sfca_accessibility_for_comparison
  expect_equal(m2$T1, e2$T1, tolerance = 1e-14)   # W = 1, so squaring changes nothing
  expect_lt(m2$T2, e2$T2)                          # W = 0.68 -> discounted
  expect_lt(m2$T3, e2$T3)                          # W = 0.22 -> discounted hard
})

test_that("the Step 2 increments are diff(W^2), NOT diff(W)^2", {
  # This is the specific confusion the method invites, and both candidates are
  # plausible-looking vectors. The fixture freezes both so the wrong one cannot
  # pass as the right one.
  tr <- DM$cumulative_band_translation
  W  <- c("10" = 1.00, "20" = 0.68, "30" = 0.22)

  right <- as.numeric(unlist(tr$incremental_weights_step2))
  wrong <- as.numeric(unlist(tr$wrong_diff_then_square))
  expect_false(isTRUE(all.equal(right, wrong)))    # they really are different

  expect_equal(as.numeric(e2sfca_incremental_weights(W, step2_power = 2)),
               right, tolerance = 1e-12)
  expect_equal(as.numeric(e2sfca_incremental_weights(W, step2_power = 1)),
               as.numeric(unlist(tr$incremental_weights_step1)), tolerance = 1e-12)
  # And the wrong construction is exactly diff(W) squared, so the fixture's
  # "wrong" vector is the real trap rather than an invented one.
  expect_equal(as.numeric(e2sfca_incremental_weights(W, step2_power = 1))^2,
               wrong, tolerance = 1e-12)
})

test_that("ABEL EQUIVALENCE holds for M2SFCA on random ring systems", {
  # As with Luo & Qi: the worked example is one system. If the squared-weight
  # Abel identity were misapplied, these would diverge.
  zones <- c(10, 20, 30)
  zw_v  <- c("10" = 1.00, "20" = 0.68, "30" = 0.22)
  zw_l  <- stats::setNames(as.list(unname(zw_v)), names(zw_v))
  for (s in 801:812) {
    set.seed(s)
    n <- sample(3:9, 1)
    g <- sprintf("T%02d", seq_len(n))
    z <- sample(zones, n, replace = TRUE)
    p <- round(stats::runif(n, 50, 5000))
    S <- round(stats::runif(1, 1, 30))

    ring <- delamater_m2sfca(as.list(stats::setNames(z, g)),
                             as.list(stats::setNames(p, g)), S, zw_l)

    ov <- do.call(rbind, lapply(seq_len(n), function(i)
      data.frame(coord_id = "P1", GEOID = g[i], band = zones[zones >= z[i]],
                 overlap_fraction = 1, stringsAsFactors = FALSE)))
    res <- compute_e2sfca(ov,
      data.frame(GEOID = g, female_pop = p, stringsAsFactors = FALSE),
      data.frame(coord_id = "P1", supply = S, stringsAsFactors = FALSE),
      weights = zw_v, step2_power = 2)
    acc <- as.data.frame(res$access)
    expect_equal(acc$access[match(g, acc$GEOID)], unname(ring[g]), tolerance = 1e-12,
                 info = paste("M2SFCA ring vs cumulative diverged, seed", s))
  }
})

# =============================================================================
# Cross-implementation and metamorphic checks against the published values.
# =============================================================================
# Everything below compares against the FROZEN numbers in the fixture, never
# against production output regenerated during the test.

.fixture_system <- function() {
  x <- .fixture_inputs()
  zones <- c(10, 20, 30)
  g <- names(x$zt)
  ov <- do.call(rbind, lapply(seq_along(g), function(i)
    data.frame(coord_id = "P1", GEOID = g[i], band = zones[zones >= x$zt[[i]]],
               overlap_fraction = 1, stringsAsFactors = FALSE)))
  list(x = x,
       overlap   = ov,
       tract_pop = data.frame(GEOID = g, female_pop = unname(x$pop),
                              stringsAsFactors = FALSE),
       supply    = data.frame(coord_id = "P1", supply = x$we$supply$P1,
                              stringsAsFactors = FALSE),
       W = c("10" = 1.00, "20" = 0.68, "30" = 0.22),
       geoids = g)
}

test_that("BOTH independent reference implementations reproduce the published values", {
  # helper-e2sfca.R holds two implementations that share no code with the engine
  # or with each other: an explicit accumulation loop and a matrix product.
  # Neither has ever been checked against an external oracle for M2SFCA.
  s <- .fixture_system()
  for (impl in list(loop = ref_e2sfca, matrix = ref_e2sfca_matrix)) {
    r <- impl(s$overlap, s$tract_pop, s$supply, s$W, step2_power = 2)
    for (gg in s$geoids)
      expect_equal(r$access[r$GEOID == gg], s$x$we$m2sfca_accessibility[[gg]],
                   tolerance = 1e-14, info = paste("tract", gg))
  }
})

test_that("ordinary E2SFCA does NOT reproduce the M2SFCA values on this fixture", {
  # A fixture on which both methods agree would prove nothing. Two of the three
  # tracts must differ, and by a margin far larger than any tolerance here.
  s <- .fixture_system()
  e2 <- as.data.frame(compute_e2sfca(s$overlap, s$tract_pop, s$supply,
                                     weights = s$W, step2_power = 1)$access)
  m2 <- s$x$we$m2sfca_accessibility

  # T1 sits at W = 1, where squaring is the identity: the methods MUST agree.
  expect_equal(e2$access[e2$GEOID == "T1"], m2$T1, tolerance = 1e-14)

  # T2 and T3 must differ, and substantially.
  for (gg in c("T2", "T3")) {
    got <- e2$access[e2$GEOID == gg]
    expect_false(isTRUE(all.equal(got, m2[[gg]], tolerance = 1e-6)),
                 info = paste("E2SFCA accidentally reproduces M2SFCA at", gg))
    expect_gt(abs(got - m2[[gg]]) / m2[[gg]], 0.3)   # >30% relative separation
  }
})

test_that("published values are invariant to row order, identifiers and irrelevant records", {
  s <- .fixture_system()
  check <- function(ov, pop, sup, map = identity, label = "") {
    r <- as.data.frame(compute_e2sfca(ov, pop, sup, weights = s$W, step2_power = 2)$access)
    for (gg in s$geoids)
      expect_equal(r$access[r$GEOID == map(gg)], s$x$we$m2sfca_accessibility[[gg]],
                   tolerance = 1e-14, info = paste(label, "-", gg))
  }

  # 1. Row order of every input.
  set.seed(4242)
  check(s$overlap[sample.int(nrow(s$overlap)), , drop = FALSE],
        s$tract_pop[sample.int(nrow(s$tract_pop)), , drop = FALSE],
        s$supply, label = "shuffled rows")

  # 2. Provider and tract identifiers replaced with arbitrary tokens.
  gmap <- stats::setNames(paste0("ZZ", seq_along(s$geoids)), s$geoids)
  ov <- s$overlap; ov$GEOID <- gmap[ov$GEOID]; ov$coord_id <- "QQ9"
  pop <- s$tract_pop; pop$GEOID <- gmap[pop$GEOID]
  sup <- s$supply; sup$coord_id <- "QQ9"
  check(ov, pop, sup, map = function(g) unname(gmap[g]), label = "relabelled ids")

  # 3. A completely disconnected extra system: its own provider, its own tracts,
  #    reachable only from each other. It must not perturb the published values
  #    by so much as a rounding step.
  extra_ov <- data.frame(coord_id = "FAR", GEOID = c("FARA", "FARB"),
                         band = 10, overlap_fraction = 1, stringsAsFactors = FALSE)
  check(rbind(s$overlap, extra_ov),
        rbind(s$tract_pop,
              data.frame(GEOID = c("FARA", "FARB"), female_pop = c(9999, 12345),
                         stringsAsFactors = FALSE)),
        rbind(s$supply,
              data.frame(coord_id = "FAR", supply = 77, stringsAsFactors = FALSE)),
        label = "disconnected extra system")
})
