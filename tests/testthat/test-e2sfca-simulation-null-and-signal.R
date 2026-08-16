# =============================================================================
# Monte Carlo null and known-signal recovery for the E2SFCA pipeline.
# =============================================================================
# The invariant suite proves the engine is internally consistent. This file asks
# a different question: run end to end, does the pipeline MANUFACTURE a
# difference where none exists, and does it RECOVER one that does?
#
# Design note on the null. Group labels are assigned BY TRACT POSITION, not at
# random, while the geography is generated independently of them. Under a
# correct engine there is no relationship between a tract's position and its
# accessibility, so the expected contrast is zero. Under an order-dependent bug
# -- a join that pairs by position, a group_by that silently sorts, an
# accumulation that leaks across rows -- position and access become correlated
# and the contrast drifts off zero. Random labels would average that bug away;
# positional labels expose it.
#
# Replicate counts are deliberately modest (see the spec: 100-250 nightly,
# 1000+ for a weekly deep run). What matters is reproducibility and sensitivity
# to injected defects, not brute-force runtime. Every seed is fixed.

# Replicate count. 200 nightly; the weekly deep job raises it to 1000 via
# E2SFCA_MC_REPLICATES. What matters is reproducibility and sensitivity to
# injected defects, not brute-force runtime -- every seed is fixed either way, so
# raising this makes the same tests SHARPER rather than making them different
# tests. The Monte Carlo standard error scales as 1/sqrt(N_REP), so 1000
# replicates tighten the null's detectable bias by rather more than a factor of
# two versus 200.
N_REP <- {
  v <- suppressWarnings(as.integer(Sys.getenv("E2SFCA_MC_REPLICATES", "200")))
  if (is.na(v) || v < 20L) 200L else v
}
# Run banner. The weekly job captures this file's stdout as its forensic
# artifact, and testthat's own output is nothing but progress counters -- it
# records that 34 assertions passed, not WHAT was computed. Without the numbers
# below, a green log and a subtly-biased log look identical after the fact.
.mc_seeds <- list(null_contrast = "1..N_REP", permutation = 99L,
                  known_signal = c(301, 302, 303), dose = 311L, convergence = 401L)
cat("\n--- Monte Carlo run parameters -------------------------------------\n")
cat("  replicates (E2SFCA_MC_REPLICATES): ", N_REP, "\n", sep = "")
cat("  null-contrast seeds:                ", .mc_seeds$null_contrast, "\n", sep = "")
cat("  permutations per replicate:         ", .mc_seeds$permutation, "\n", sep = "")
cat("  known-signal seeds:                 ", paste(.mc_seeds$known_signal, collapse = ", "), "\n", sep = "")
cat("  acceptance thresholds:              |z| < 4; sign-test p > 0.001;\n")
cat("                                      false-positive rate < 0.20 at nominal 0.05;\n")
cat("                                      dose recovery |err| < 1e-9\n")
cat("--------------------------------------------------------------------\n\n")

# Population-weighted contrast between the two label groups.
null_contrast <- function(seed, n_tract = 24L, n_prov = 7L) {
  fx <- make_fixture(seed, n_prov = n_prov, n_tract = n_tract)
  # Unequal group sizes on purpose: 5/12 vs 7/12.
  k <- floor(n_tract * 5 / 12)
  gid <- fx$tract_pop$GEOID
  gA <- gid[seq_len(k)]; gB <- gid[(k + 1L):n_tract]
  acc <- prod_access(fx)
  pw_mean_access(acc, fx$tract_pop, gA) - pw_mean_access(acc, fx$tract_pop, gB)
}

test_that("MONTE CARLO NULL: the pipeline does not manufacture a group difference", {
  contrasts <- vapply(seq_len(N_REP), null_contrast, numeric(1))
  expect_true(all(is.finite(contrasts)))

  # Scale-free: contrasts are compared against their own spread, so the test
  # does not depend on the arbitrary units of the synthetic fixtures.
  se <- stats::sd(contrasts) / sqrt(N_REP)
  z  <- mean(contrasts) / se
  cat(sprintf("  [null] mean contrast %+.6e  sd %.6e  SE %.6e  z %+.3f\n",
              mean(contrasts), stats::sd(contrasts), se, z))
  cat(sprintf("  [null] positive contrasts %d/%d  sign-test p %.4f\n",
              sum(contrasts > 0), N_REP,
              stats::binom.test(sum(contrasts > 0), N_REP, 0.5)$p.value))
  expect_lt(abs(z), 4,
            label = sprintf("mean null contrast is %.4g SEs from zero", abs(z)))

  # And no systematic favouring of either label.
  pos <- sum(contrasts > 0)
  expect_gt(stats::binom.test(pos, N_REP, 0.5)$p.value, 0.001)
})

test_that("MONTE CARLO NULL: a permutation test holds its nominal false-positive rate", {
  # Labels are irrelevant to the pipeline under the null, so permuting them over
  # the computed accessibility vector is an exact test. If the pipeline induced
  # any label dependence the observed statistic would sit in the tail far more
  # often than 5% of the time.
  set.seed(99L)
  reject <- 0L
  n_tract <- 24L; k <- floor(n_tract * 5 / 12)
  for (s in seq_len(N_REP)) {
    fx  <- make_fixture(s, n_prov = 7L, n_tract = n_tract)
    acc <- prod_access(fx)
    a   <- acc$access[match(fx$tract_pop$GEOID, acc$GEOID)]; a[is.na(a)] <- 0
    p   <- fx$tract_pop$female_pop
    stat <- function(idx) {
      A <- idx[seq_len(k)]; B <- idx[(k + 1L):n_tract]
      wA <- if (sum(p[A]) > 0) sum(a[A] * p[A]) / sum(p[A]) else 0
      wB <- if (sum(p[B]) > 0) sum(a[B] * p[B]) / sum(p[B]) else 0
      wA - wB
    }
    obs  <- stat(seq_len(n_tract))
    perm <- vapply(seq_len(99L), function(i) stat(sample.int(n_tract)), numeric(1))
    if (mean(abs(perm) >= abs(obs)) <= 0.05) reject <- reject + 1L
  }
  # Nominal 5%. Allow a generous band: this must catch a broken pipeline, not
  # flag ordinary Monte Carlo noise.
  cat(sprintf("  [perm] rejections %d/%d = %.4f at nominal 0.05\n",
              reject, N_REP, reject / N_REP))
  expect_lt(reject / N_REP, 0.20,
            label = sprintf("false-positive rate %.3f at nominal 0.05", reject / N_REP))
})

test_that("KNOWN SIGNAL: an exactly-known supply increase is recovered exactly", {
  # Two mutually unreachable components. Because no provider in A touches any
  # tract in B, accessibility is linear in that component's supply alone, so
  # raising A's supply by d multiplies every A tract's access by exactly (1 + d)
  # and leaves B untouched. Direction, magnitude and dose-response all become
  # closed-form rather than approximate.
  for (seed in c(301L, 302L, 303L)) {
    tc   <- make_two_component(seed)
    base <- prod_access(tc$combined)
    gA   <- tc$A$pop$GEOID; gB <- tc$B$pop$GEOID

    for (d in c(0.10, 0.25, 0.50)) {
      fx2 <- tc$combined
      boost <- fx2$supply$coord_id %in% tc$A$sup$coord_id
      fx2$supply$supply[boost] <- fx2$supply$supply[boost] * (1 + d)
      got <- prod_access(fx2)

      aA0 <- base$access[match(gA, base$GEOID)]; aA1 <- got$access[match(gA, got$GEOID)]
      aB0 <- base$access[match(gB, base$GEOID)]; aB1 <- got$access[match(gB, got$GEOID)]

      expect_equal(aA1, aA0 * (1 + d), tolerance = 1e-10,
                   info = sprintf("dose %.2f: component A did not scale exactly", d))
      expect_equal(aB1, aB0, tolerance = 1e-12,
                   info = sprintf("dose %.2f: component B moved, so the components leak", d))
      expect_true(all(aA1 >= aA0 - 1e-12))          # direction
    }
  }
})

test_that("KNOWN SIGNAL: dose-response is monotone and correctly ordered", {
  tc <- make_two_component(311L)
  gA <- tc$A$pop$GEOID
  means <- vapply(c(0, 0.10, 0.25, 0.50), function(d) {
    fx2 <- tc$combined
    boost <- fx2$supply$coord_id %in% tc$A$sup$coord_id
    fx2$supply$supply[boost] <- fx2$supply$supply[boost] * (1 + d)
    pw_mean_access(prod_access(fx2), fx2$tract_pop, gA)
  }, numeric(1))
  cat(sprintf("  [dose] means %s  ratios %s\n",
              paste(sprintf("%.6e", means), collapse = " "),
              paste(sprintf("%.4f", means / means[1]), collapse = " ")))
  expect_true(all(diff(means) > 0))                       # strictly increasing
  expect_equal(means / means[1], c(1, 1.10, 1.25, 1.50), tolerance = 1e-10)
})

test_that("KNOWN SIGNAL: the estimated contrast converges on truth as the fixture grows", {
  # With partial overlap between the components the recovered contrast is no
  # longer exact, so this checks the estimate approaches the injected truth as
  # the system grows rather than matching it outright.
  d <- 0.40
  err <- vapply(c(6L, 12L, 24L, 48L), function(n) {
    tc <- make_two_component(401L, n_each = n, prov_each = max(2L, n %/% 3L))
    gA <- tc$A$pop$GEOID
    b  <- pw_mean_access(prod_access(tc$combined), tc$combined$tract_pop, gA)
    fx2 <- tc$combined
    boost <- fx2$supply$coord_id %in% tc$A$sup$coord_id
    fx2$supply$supply[boost] <- fx2$supply$supply[boost] * (1 + d)
    g <- pw_mean_access(prod_access(fx2), fx2$tract_pop, gA)
    abs((g / b - 1) - d)
  }, numeric(1))
  cat(sprintf("  [conv] |recovered dose - 0.40| by size: %s\n",
              paste(sprintf("%.3e", err), collapse = " ")))
  expect_true(all(err < 1e-9),
              label = "recovered dose drifted from the injected 0.40")
})
