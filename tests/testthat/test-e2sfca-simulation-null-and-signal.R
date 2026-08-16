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
# =============================================================================
# SCIENTIFIC AUDIT RECORD
# =============================================================================
# The weekly job keeps this file's stdout as its forensic artifact. testthat's
# own output is progress counters: it records that 34 assertions passed, never
# WHAT was computed, so a green run and a subtly biased one produce identical
# logs. Everything below exists so the run can be audited after the fact.
#
# The assertions remain in test_that(); this block is EVIDENCE, not a gate.
# Thresholds are constants fixed BEFORE any simulation runs -- they are never
# derived from what the run happened to produce.

MC_THRESHOLDS <- list(
  null_abs_z_max          = 4,      # |mean contrast / SE| under the null
  null_sign_test_p_min    = 0.001,  # binomial test on the sign of the contrast
  perm_reject_rate_max    = 0.20,   # empirical rejection rate at nominal 0.05
  dose_recovery_abs_max   = 1e-9,   # |recovered dose - injected dose|
  signal_exact_tolerance  = 1e-10   # exact-scaling tolerance for A_i * (1 + d)
)

MC_FIXTURE <- list(
  version        = "1.0.0",
  generator      = "make_two_component() / make_fixture() in helper-e2sfca.R",
  null_scenario  = paste("labels assigned BY TRACT POSITION (first 5/12 = A) while",
                         "geography is generated independently of them; under a",
                         "correct engine position and access are unrelated"),
  signal_scenario = paste("two mutually unreachable components; component A's supply",
                          "multiplied by (1 + d) for d in 0.10, 0.25, 0.50, so A's",
                          "access must scale by exactly (1 + d) and B must not move"),
  seed_scheme    = "deterministic: null replicate i uses set.seed(i); signal seeds 301-303, 311, 401",
  rng_kind       = paste(RNGkind(), collapse = "/")
)

.mc_audit <- new.env(parent = emptyenv())
.mc_audit$failures <- character(0)
.mc_note <- function(key, value) assign(key, value, envir = .mc_audit)
.mc_fail <- function(msg) .mc_audit$failures <- c(.mc_audit$failures, msg)

.git_sha <- tryCatch(trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE,
                                    stderr = FALSE)), error = function(e) NA_character_)

cat("\n=== MONTE CARLO SCIENTIFIC AUDIT RECORD ============================\n")
cat("  git SHA:              ", if (length(.git_sha)) .git_sha[1] else "unknown", "\n", sep = "")
cat("  run timestamp (UTC):  ", format(Sys.time(), tz = "UTC", usetz = TRUE), "\n", sep = "")
cat("  run timestamp (local):", format(Sys.time(), usetz = TRUE), "\n", sep = "")
cat("  R version:            ", paste0(R.version$major, ".", R.version$minor), "\n", sep = "")
cat("  fixture version:      ", MC_FIXTURE$version, "\n", sep = "")
cat("  fixture generator:    ", MC_FIXTURE$generator, "\n", sep = "")
cat("  RNG kind:             ", MC_FIXTURE$rng_kind, "\n", sep = "")
cat("  seed scheme:          ", MC_FIXTURE$seed_scheme, "\n", sep = "")
cat("  replicates requested: ", N_REP, "\n", sep = "")
cat("\n  null scenario:   ", MC_FIXTURE$null_scenario, "\n", sep = "")
cat("  signal scenario: ", MC_FIXTURE$signal_scenario, "\n", sep = "")
cat("\n  PRESPECIFIED ACCEPTANCE THRESHOLDS (fixed before simulation):\n")
for (k in names(MC_THRESHOLDS))
  cat(sprintf("    %-24s %s\n", k, format(MC_THRESHOLDS[[k]])))
cat("====================================================================\n\n")

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
  .mc_note("replicates_completed", length(contrasts))
  .mc_note("null_mean_bias", mean(contrasts)); .mc_note("null_z", z)
  if (abs(z) >= MC_THRESHOLDS$null_abs_z_max)
    .mc_fail(sprintf("null |z| = %.3f exceeds %.3f", abs(z), MC_THRESHOLDS$null_abs_z_max))
  cat(sprintf("  [null] replicates completed %d of %d\n", length(contrasts), N_REP))
  cat(sprintf("  [null] mean contrast %+.6e  sd %.6e  SE %.6e  z %+.3f\n",
              mean(contrasts), stats::sd(contrasts), se, z))
  .sp <- stats::binom.test(sum(contrasts > 0), N_REP, 0.5)$p.value
  .mc_note("null_sign_p", .sp)
  if (.sp <= MC_THRESHOLDS$null_sign_test_p_min)
    .mc_fail(sprintf("sign-test p = %.5f at or below %.5f", .sp, MC_THRESHOLDS$null_sign_test_p_min))
  cat(sprintf("  [null] positive contrasts %d/%d  sign-test p %.4f\n",
              sum(contrasts > 0), N_REP, .sp))
  # Threshold comes from MC_THRESHOLDS, never a literal: the audit block below
  # reports against the same constant, and two copies could silently drift
  # apart -- the audit saying FAIL while the gate said PASS.
  expect_lt(abs(z), MC_THRESHOLDS$null_abs_z_max,
            label = sprintf("mean null contrast is %.4g SEs from zero", abs(z)))

  # And no systematic favouring of either label.
  pos <- sum(contrasts > 0)
  expect_gt(stats::binom.test(pos, N_REP, 0.5)$p.value,
            MC_THRESHOLDS$null_sign_test_p_min)
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
  .mc_note("perm_reject_rate", reject / N_REP)
  if (reject / N_REP >= MC_THRESHOLDS$perm_reject_rate_max)
    .mc_fail(sprintf("false-positive rate %.4f at or above %.4f",
                     reject / N_REP, MC_THRESHOLDS$perm_reject_rate_max))
  cat(sprintf("  [perm] rejections %d/%d = %.4f at nominal 0.05\n",
              reject, N_REP, reject / N_REP))
  expect_lt(reject / N_REP, MC_THRESHOLDS$perm_reject_rate_max,
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
  .ratios <- means / means[1]; .truth <- c(1, 1.10, 1.25, 1.50)
  .mc_note("dose_injected", .truth); .mc_note("dose_recovered", .ratios)
  .mc_note("direction_recovery_rate", mean(diff(means) > 0))
  cat(sprintf("  [dose] injected %s\n", paste(sprintf("%.4f", .truth), collapse = " ")))
  cat(sprintf("  [dose] recovered %s  (max |err| %.3e)\n",
              paste(sprintf("%.4f", .ratios), collapse = " "),
              max(abs(.ratios - .truth))))
  cat(sprintf("  [dose] direction-recovery rate %.4f (%d of %d increases)\n",
              mean(diff(means) > 0), sum(diff(means) > 0), length(diff(means))))
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
  .mc_note("convergence_err", err)
  if (any(err >= MC_THRESHOLDS$dose_recovery_abs_max))
    .mc_fail(sprintf("dose recovery error %.3e at or above %.3e",
                     max(err), MC_THRESHOLDS$dose_recovery_abs_max))
  cat(sprintf("  [conv] injected dose 0.40; |recovered - injected| by size: %s\n",
              paste(sprintf("%.3e", err), collapse = " ")))
  expect_true(all(err < MC_THRESHOLDS$dose_recovery_abs_max),
              label = "recovered dose drifted from the injected 0.40")
})


# =============================================================================
# AUDIT SUMMARY AND SENTINEL
# =============================================================================
# Recomputed from the observed values against the SAME prespecified constants
# the assertions use. This is a second, independent statement of the verdict --
# if it ever disagreed with testthat, that disagreement would itself be the
# finding. The workflow greps for the sentinel, so a run that dies partway
# cannot masquerade as a pass.
cat("\n=== MONTE CARLO AUDIT SUMMARY ======================================\n")
.g <- function(k, d = NA) if (exists(k, envir = .mc_audit)) get(k, envir = .mc_audit) else d
cat(sprintf("  replicates requested / completed:  %d / %s\n",
            N_REP, format(.g("replicates_completed"))))
# Machine-readable twin of the line above. The workflow parses THIS, never the
# prose: the first guard split the human-readable line on "/" and picked up the
# slash in "requested / completed", so it read the completed count as
# "completed:1000" and failed a run whose science was perfect. Prose is for
# people; give the machine its own unambiguous field.
cat(sprintf("MC-REPLICATES requested=%d completed=%s\n",
            N_REP, format(.g("replicates_completed"))))
cat(sprintf("  null mean bias:                    %+.6e\n", .g("null_mean_bias", NA_real_)))
cat(sprintf("  null z (threshold |z| < %g):        %+.3f\n",
            MC_THRESHOLDS$null_abs_z_max, .g("null_z", NA_real_)))
cat(sprintf("  sign-test p (threshold > %g):    %.4f\n",
            MC_THRESHOLDS$null_sign_test_p_min, .g("null_sign_p", NA_real_)))
cat(sprintf("  rejection rate (threshold < %g):   %.4f\n",
            MC_THRESHOLDS$perm_reject_rate_max, .g("perm_reject_rate", NA_real_)))
cat(sprintf("  direction-recovery rate:           %.4f\n",
            .g("direction_recovery_rate", NA_real_)))
cat("  interval coverage:                 N/A -- this suite reports a\n")
cat("                                     permutation false-positive rate, not\n")
cat("                                     confidence-interval coverage; the\n")
cat("                                     engine emits no interval to cover.\n")
if (length(.mc_audit$failures)) {
  cat("\n  TOLERANCE FAILURES:\n")
  for (f in .mc_audit$failures) cat("    - ", f, "\n", sep = "")
} else {
  cat("  tolerance failures:                none\n")
}
.mc_replicates_ok <- identical(as.integer(.g("replicates_completed", -1L)), as.integer(N_REP))
if (!.mc_replicates_ok)
  cat("    - replicate accounting mismatch: requested ", N_REP,
      ", completed ", format(.g("replicates_completed")), "\n", sep = "")
cat("====================================================================\n")
cat("MC-AUDIT-SENTINEL: ",
    if (!length(.mc_audit$failures) && .mc_replicates_ok) "PASS" else "FAIL",
    "\n", sep = "")
