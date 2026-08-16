# =============================================================================
# E2SFCA mathematical invariants, randomized adversarial fixtures, and an
# independent reference implementation.
# =============================================================================
# The class of bug this targets is the one no amount of "does it run" testing
# finds: code that is fast, internally consistent, and mathematically wrong. A
# vectorised dplyr pipeline that drops a join key, powers the wrong weight
# vector, or divides by the wrong denominator still returns a tidy tibble of
# plausible accessibility values.
#
# So this file does three things, in increasing order of strength:
#
#   1. INVARIANTS   properties that must hold for ANY input, checked on
#                   randomized fixtures rather than hand-picked ones.
#   2. REFERENCE    a deliberately slow, obvious triple-loop implementation of
#                   E2SFCA that shares no code with the engine, compared against
#                   production on random fixtures.
#   3. MUTANTS      plausible wrong implementations, each shown to be DETECTABLE
#                   by the checks above. A mutant that cannot be distinguished
#                   marks an untested behaviour.
#
# The reference implements the method from the module header of
# R/two_step_floating_catchment.R, not the shape of its code:
#
#   Step 1   R_j = S_j / SUM_{i,b} w'_b * f_jbi * pop_i
#   Step 2   A_i = SUM_{j,b} w'a_b * f_jbi * R_j
#
#   w'_b = W_b - W_{b+1}                  (Step 1, always power 1)
#   w'a_b = W_b^p - W_{b+1}^p             (Step 2, p = step2_power)
#   with W beyond the last band = 0.
suppressWarnings(suppressMessages(library(testthat)))
source(file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                        rprojroot::is_git_root),
                 "R", "two_step_floating_catchment.R"))

# -----------------------------------------------------------------------------
# Independent reference: base R only. No dplyr, no engine helpers.
# -----------------------------------------------------------------------------
ref_incremental <- function(W, power = 1) {
  W <- W[order(as.integer(names(W)))]
  wp <- as.numeric(W)^power
  inc <- wp - c(wp[-1L], 0)
  stats::setNames(inc, names(W))
}

ref_e2sfca <- function(overlap, tract_pop, supply, W, step2_power = 1,
                       pop_col = "female_pop", per_capita_scale = 1e5) {
  inc_d <- ref_incremental(W, 1)
  inc_a <- ref_incremental(W, step2_power)

  pop <- stats::setNames(as.numeric(tract_pop[[pop_col]]),
                         as.character(tract_pop$GEOID))
  pop[is.na(pop)] <- 0
  sup <- stats::setNames(as.numeric(supply$supply), as.character(supply$coord_id))

  # Step 1: weighted demand per provider, by explicit accumulation.
  demand <- stats::setNames(rep(0, length(sup)), names(sup))
  for (r in seq_len(nrow(overlap))) {
    j <- as.character(overlap$coord_id[r])
    if (!j %in% names(sup)) next                    # inner join semantics
    g <- as.character(overlap$GEOID[r])
    b <- as.character(overlap$band[r])
    if (!b %in% names(inc_d)) next
    p <- if (g %in% names(pop)) pop[[g]] else 0
    demand[[j]] <- demand[[j]] + inc_d[[b]] * overlap$overlap_fraction[r] * p
  }

  ratio <- ifelse(demand > 0, sup / demand, 0)      # ratio_for_surface
  names(ratio) <- names(sup)

  # Step 2: accessibility per tract.
  geoids <- unique(as.character(overlap$GEOID))
  access <- stats::setNames(rep(0, length(geoids)), geoids)
  for (r in seq_len(nrow(overlap))) {
    j <- as.character(overlap$coord_id[r])
    if (!j %in% names(sup)) next
    b <- as.character(overlap$band[r])
    if (!b %in% names(inc_a)) next
    g <- as.character(overlap$GEOID[r])
    access[[g]] <- access[[g]] + inc_a[[b]] * overlap$overlap_fraction[r] * ratio[[j]]
  }

  data.frame(GEOID = names(access),
             access = as.numeric(access),
             access_scaled = as.numeric(access) * per_capita_scale,
             stringsAsFactors = FALSE)[order(names(access)), ]
}

# -----------------------------------------------------------------------------
# Randomized fixture generator. Deterministic given a seed, and deliberately
# nasty: zero-supply providers, zero-population tracts, providers that reach no
# tract, tracts reached by nobody, and partial overlaps.
# -----------------------------------------------------------------------------
make_fixture <- function(seed, n_prov = 4, n_tract = 6,
                         bands = c(30, 60, 120, 180)) {
  set.seed(seed)
  coord <- paste0("P", seq_len(n_prov))
  geo   <- sprintf("%011d", seq_len(n_tract))
  rows <- expand.grid(coord_id = coord, GEOID = geo, band = bands,
                      KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  # Cumulative bands: a tract's overlap fraction is non-decreasing in band.
  base_f <- stats::runif(n_prov * n_tract)
  base_f[sample.int(length(base_f), size = max(1L, length(base_f) %/% 4L))] <- 0
  key <- paste(rows$coord_id, rows$GEOID)
  ukey <- unique(key)
  f0 <- stats::setNames(base_f[seq_along(ukey)], ukey)
  band_scale <- stats::setNames(seq_along(bands) / length(bands), as.character(bands))
  rows$overlap_fraction <- pmin(1, f0[key] * band_scale[as.character(rows$band)])
  rows <- rows[rows$overlap_fraction > 0, , drop = FALSE]
  rownames(rows) <- NULL

  pop <- data.frame(GEOID = geo,
                    female_pop = round(stats::runif(n_tract, 0, 5000)),
                    stringsAsFactors = FALSE)
  pop$female_pop[sample.int(n_tract, 1)] <- 0          # a zero-population tract

  sup <- data.frame(coord_id = coord,
                    supply = round(stats::runif(n_prov, 0, 20)),
                    stringsAsFactors = FALSE)
  sup$supply[sample.int(n_prov, 1)] <- 0               # a zero-supply provider

  list(overlap = rows, tract_pop = pop, supply = sup)
}

W4 <- E2SFCA_DEFAULT_WEIGHTS

prod_access <- function(fx, ...) {
  r <- compute_e2sfca(fx$overlap, fx$tract_pop, fx$supply, weights = W4, ...)
  a <- as.data.frame(r$access)
  a[order(a$GEOID), c("GEOID", "access")]
}

# =============================================================================
# 1. INVARIANTS
# =============================================================================
test_that("zero supply everywhere gives exactly zero accessibility", {
  for (s in c(11L, 12L, 13L)) {
    fx <- make_fixture(s)
    fx$supply$supply <- 0
    a <- prod_access(fx)
    expect_true(all(a$access == 0))
    expect_false(any(is.na(a$access)))
  }
})

test_that("accessibility is homogeneous of degree one in supply", {
  # R_j = S_j / D_j and D_j does not depend on S, so scaling every supply by k
  # must scale every tract's accessibility by exactly k. A bug that pushes
  # supply through the demand denominator breaks this.
  for (s in c(21L, 22L, 23L)) {
    fx <- make_fixture(s)
    base <- prod_access(fx)
    k <- 3.5
    fx2 <- fx; fx2$supply$supply <- fx2$supply$supply * k
    scaled <- prod_access(fx2)
    expect_equal(scaled$access, base$access * k, tolerance = 1e-10)
  }
})

test_that("accessibility is monotone non-decreasing in any single provider's supply", {
  for (s in c(31L, 32L)) {
    fx <- make_fixture(s)
    base <- prod_access(fx)
    for (j in fx$supply$coord_id) {
      fx2 <- fx
      fx2$supply$supply[fx2$supply$coord_id == j] <-
        fx2$supply$supply[fx2$supply$coord_id == j] + 10
      bumped <- prod_access(fx2)
      expect_true(all(bumped$access >= base$access - 1e-10),
                  info = paste("raising supply of", j, "lowered some tract's access"))
    }
  }
})

test_that("results are invariant to row order of every input", {
  # Section 32's row-order metamorphism. A join that silently relies on
  # positional order rather than keys fails here and nowhere else.
  for (s in c(41L, 42L, 43L)) {
    fx <- make_fixture(s)
    base <- prod_access(fx)
    set.seed(s * 7L)
    sh <- fx
    sh$overlap   <- fx$overlap[sample.int(nrow(fx$overlap)), , drop = FALSE]
    sh$tract_pop <- fx$tract_pop[sample.int(nrow(fx$tract_pop)), , drop = FALSE]
    sh$supply    <- fx$supply[sample.int(nrow(fx$supply)), , drop = FALSE]
    expect_equal(prod_access(sh)$access, base$access, tolerance = 1e-12)
  }
})

test_that("accessibility is never negative, NaN or infinite", {
  for (s in 51:56) {
    a <- prod_access(make_fixture(s))$access
    expect_true(all(is.finite(a)))
    expect_true(all(a >= 0))
  }
})

test_that("a provider reaching no population contributes nothing and is not a divide-by-zero", {
  fx <- make_fixture(61L)
  # Give one provider supply but strip every overlap row it appears in.
  ghost <- fx$supply$coord_id[1]
  fx$supply$supply[fx$supply$coord_id == ghost] <- 99
  fx$overlap <- fx$overlap[fx$overlap$coord_id != ghost, , drop = FALSE]
  r <- compute_e2sfca(fx$overlap, fx$tract_pop, fx$supply, weights = W4)
  expect_true(all(is.finite(r$access$access)))
  expect_true(ghost %in% r$audit$zero_demand_coord_ids)
  expect_equal(r$audit$supply_zero_demand, 99)
})

test_that("CONSERVATION: population-weighted accessibility recovers total usable supply", {
  # SUM_i pop_i * A_i
  #   = SUM_i pop_i SUM_{j,b} w'_b f_jbi R_j
  #   = SUM_j R_j SUM_{i,b} w'_b f_jbi pop_i
  #   = SUM_j R_j * D_j
  #   = SUM_j S_j        over providers with positive weighted demand.
  # Exact for step2_power = 1. This is the single strongest structural check
  # here: it ties the two steps together and fails if either the weights, the
  # denominator, or the join is wrong.
  for (s in c(71L, 72L, 73L, 74L)) {
    fx <- make_fixture(s)
    r  <- compute_e2sfca(fx$overlap, fx$tract_pop, fx$supply, weights = W4)
    acc <- as.data.frame(r$access)
    pop <- stats::setNames(fx$tract_pop$female_pop, fx$tract_pop$GEOID)
    lhs <- sum(acc$access * pop[acc$GEOID], na.rm = TRUE)
    usable <- r$provider_ratios$supply[!r$provider_ratios$zero_demand]
    expect_equal(lhs, sum(usable), tolerance = 1e-8,
                 info = "population-weighted access did not recover usable supply")
  }
})

test_that("M2SFCA never scores higher than E2SFCA", {
  # step2_power > 1 applies the distance penalty a second time, so it can only
  # discount. If a fixture ever scored higher under M2SFCA the powering is
  # being applied to the wrong vector.
  for (s in c(81L, 82L, 83L)) {
    fx <- make_fixture(s)
    e2 <- prod_access(fx, step2_power = 1)
    m2 <- prod_access(fx, step2_power = 2)
    expect_true(all(m2$access <= e2$access + 1e-10))
  }
})

# =============================================================================
# 2. INDEPENDENT REFERENCE CROSS-CHECK
# =============================================================================
test_that("the engine agrees with an independent triple-loop implementation", {
  for (s in 101:112) {
    fx <- make_fixture(s, n_prov = sample(2:5, 1), n_tract = sample(3:8, 1))
    prod <- prod_access(fx)
    ref  <- ref_e2sfca(fx$overlap, fx$tract_pop, fx$supply, W4)
    ref  <- ref[match(prod$GEOID, ref$GEOID), ]
    expect_equal(prod$access, ref$access, tolerance = 1e-10,
                 info = paste("engine and reference disagree on seed", s))
  }
})

test_that("the engine agrees with the reference under M2SFCA too", {
  for (s in 121:128) {
    fx <- make_fixture(s)
    prod <- prod_access(fx, step2_power = 2)
    ref  <- ref_e2sfca(fx$overlap, fx$tract_pop, fx$supply, W4, step2_power = 2)
    ref  <- ref[match(prod$GEOID, ref$GEOID), ]
    expect_equal(prod$access, ref$access, tolerance = 1e-10)
  }
})

# =============================================================================
# 3. MUTANTS -- each must be DETECTABLE by the checks above
# =============================================================================
test_that("plausible wrong E2SFCA implementations are all detectable", {
  fx <- make_fixture(201L)
  truth <- ref_e2sfca(fx$overlap, fx$tract_pop, fx$supply, W4)$access

  mutants <- list(
    "Step 2 uses cumulative weights instead of incremental" = {
      W <- W4
      inc_d <- ref_incremental(W, 1)
      # deliberately wrong: use W_b rather than w'_b in step 2
      o <- fx$overlap
      pop <- stats::setNames(fx$tract_pop$female_pop, fx$tract_pop$GEOID)
      sup <- stats::setNames(fx$supply$supply, fx$supply$coord_id)
      dem <- stats::setNames(rep(0, length(sup)), names(sup))
      for (r in seq_len(nrow(o))) dem[[o$coord_id[r]]] <- dem[[o$coord_id[r]]] +
        inc_d[[as.character(o$band[r])]] * o$overlap_fraction[r] * pop[[o$GEOID[r]]]
      ratio <- ifelse(dem > 0, sup / dem, 0); names(ratio) <- names(sup)
      acc <- stats::setNames(rep(0, length(unique(o$GEOID))), sort(unique(o$GEOID)))
      for (r in seq_len(nrow(o))) acc[[o$GEOID[r]]] <- acc[[o$GEOID[r]]] +
        W[[as.character(o$band[r])]] * o$overlap_fraction[r] * ratio[[o$coord_id[r]]]
      as.numeric(acc)
    },
    "demand denominator omits the population weight" = {
      inc_d <- ref_incremental(W4, 1)
      o <- fx$overlap
      pop <- stats::setNames(fx$tract_pop$female_pop, fx$tract_pop$GEOID)
      sup <- stats::setNames(fx$supply$supply, fx$supply$coord_id)
      dem <- stats::setNames(rep(0, length(sup)), names(sup))
      for (r in seq_len(nrow(o))) dem[[o$coord_id[r]]] <- dem[[o$coord_id[r]]] +
        inc_d[[as.character(o$band[r])]] * o$overlap_fraction[r]   # pop dropped
      ratio <- ifelse(dem > 0, sup / dem, 0); names(ratio) <- names(sup)
      acc <- stats::setNames(rep(0, length(unique(o$GEOID))), sort(unique(o$GEOID)))
      for (r in seq_len(nrow(o))) acc[[o$GEOID[r]]] <- acc[[o$GEOID[r]]] +
        inc_d[[as.character(o$band[r])]] * o$overlap_fraction[r] * ratio[[o$coord_id[r]]]
      as.numeric(acc)
    },
    "overlap fraction ignored (treated as full coverage)" = {
      o <- fx$overlap; o$overlap_fraction <- 1
      ref_e2sfca(o, fx$tract_pop, fx$supply, W4)$access
    },
    "diff(W)^2 instead of diff(W^2) for M2SFCA" = {
      wrong <- stats::setNames(ref_incremental(W4, 1)^2, names(W4))
      inc_a <- wrong
      o <- fx$overlap
      inc_d <- ref_incremental(W4, 1)
      pop <- stats::setNames(fx$tract_pop$female_pop, fx$tract_pop$GEOID)
      sup <- stats::setNames(fx$supply$supply, fx$supply$coord_id)
      dem <- stats::setNames(rep(0, length(sup)), names(sup))
      for (r in seq_len(nrow(o))) dem[[o$coord_id[r]]] <- dem[[o$coord_id[r]]] +
        inc_d[[as.character(o$band[r])]] * o$overlap_fraction[r] * pop[[o$GEOID[r]]]
      ratio <- ifelse(dem > 0, sup / dem, 0); names(ratio) <- names(sup)
      acc <- stats::setNames(rep(0, length(unique(o$GEOID))), sort(unique(o$GEOID)))
      for (r in seq_len(nrow(o))) acc[[o$GEOID[r]]] <- acc[[o$GEOID[r]]] +
        inc_a[[as.character(o$band[r])]] * o$overlap_fraction[r] * ratio[[o$coord_id[r]]]
      as.numeric(acc)
    }
  )

  for (nm in names(mutants)) {
    expect_false(isTRUE(all.equal(mutants[[nm]], truth, tolerance = 1e-10)),
                 info = paste0("SURVIVING MUTANT -- indistinguishable from correct ",
                               "E2SFCA: ", nm))
  }
})
