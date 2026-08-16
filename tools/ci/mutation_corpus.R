#!/usr/bin/env Rscript
# =============================================================================
# Persistent scientific mutation corpus for the E2SFCA engine.
# =============================================================================
# A mutation experiment run once during development proves nothing next month.
# This keeps the mutants NAMED and CHECKED IN, and fails if any of them survives
# the scientific test suites.
#
# Each mutant is a plausible wrong implementation that still runs, still returns
# a tidy tibble, and still produces numbers a reviewer would accept. The claim
# under test is not "the code is covered" but "if someone made this specific
# scientific mistake, at least one test would notice".
#
# A surviving mutant is a release-blocking failure regardless of coverage.
#
# Usage:  Rscript tools/ci/mutation_corpus.R [--quick]
#         --quick runs only the two fast suites (skips the Monte Carlo file)

args   <- commandArgs(trailingOnly = TRUE)
quick  <- "--quick" %in% args
ENGINE <- "R/two_step_floating_catchment.R"
URPS   <- "R/urps_accessibility_scenarios.R"
# Every file the corpus may touch. All are backed up before any mutation and
# restored afterwards, whatever happens.
TARGETS <- c(ENGINE, URPS)

# The corpus stops at the first suite that kills a mutant, so a broader list
# costs little: allocator and URPS mutants simply fall through the E2SFCA suites
# to the ones that cover them.
SUITES <- c("tests/testthat/test-e2sfca-luo-qi-2009-published.R",
            "tests/testthat/test-e2sfca-invariants-and-reference.R",
            "tests/testthat/test-e2sfca-metamorphic-and-algebra.R",
            "tests/testthat/test-e2sfca-allocator-semantic-adversarial-2026-07-19.R",
            "tests/testthat/test-two-step-floating-catchment.R",
            "tests/testthat/test-urps-accessibility-scenarios.R",
            "tests/testthat/test-urps-accessibility-e2sfca-adapter.R",
            if (!quick) "tests/testthat/test-e2sfca-simulation-null-and-signal.R")

# --- the corpus ---------------------------------------------------------------
# name -> list(old, new, why). `old` must appear EXACTLY ONCE in the engine, so
# that a refactor which moves the code makes this corpus fail loudly rather than
# silently stop mutating anything.
MUTANTS <- list(
  wrong_denominator = list(
    old = "weighted_demand = sum(wf * pop),",
    new = "weighted_demand = sum(wf * pop) * 2,",
    why = "Step 1 denominator inflated: every provider looks half as available."),
  denominator_drops_population = list(
    old = "weighted_demand = sum(wf * pop),",
    new = "weighted_demand = sum(wf),",
    why = "Demand counts catchments instead of people."),
  ignore_overlap_step1 = list(
    old = "base <- dplyr::mutate(base, wf = w_inc * overlap_fraction,",
    new = "base <- dplyr::mutate(base, wf = w_inc,",
    why = "Step 1 treats every partial catchment as full coverage."),
  ignore_overlap_step2 = list(
    old = "                        wf_a = w_acc * overlap_fraction)",
    new = "                        wf_a = w_acc)",
    why = "Step 2 credits a tract for a provider that barely reaches it."),
  m2_exponent_removed = list(
    old = "w_acc = as.numeric(inc_a))",
    new = "w_acc = as.numeric(inc_d))",
    why = "M2SFCA silently collapses into E2SFCA; every model still converges."),
  weight_applied_twice = list(
    old = "                        wf_a = w_acc * overlap_fraction)",
    new = "                        wf_a = w_acc * w_acc * overlap_fraction)",
    why = "Step 2 decay applied twice, mimicking an M2SFCA that was never asked for."),
  provider_ratio_pooled = list(
    # Anchored on the following line too: the ratio_for_surface expression alone
    # appears in BOTH the vector and raster paths, and the corpus refuses to
    # mutate an ambiguous anchor.
    old = "    ratio_for_surface = dplyr::if_else(weighted_demand > 0, supply / weighted_demand, 0),\n    excluded_supply   = dplyr::if_else(weighted_demand > 0, 0, supply)\n  )",
    new = "    ratio_for_surface = dplyr::if_else(weighted_demand > 0, sum(supply) / sum(weighted_demand), 0),\n    excluded_supply   = dplyr::if_else(weighted_demand > 0, 0, supply)\n  )",
    why = "All providers share one pooled ratio: supply leaks between unrelated regions."),
  # --- allocator: mass conservation is the whole point of this function --------
  allocator_drops_area_share = list(
    old = "    contrib <- popc[locid] * (area / tot[as.character(locid)])",
    new = "    contrib <- popc[locid] * area",
    suites = "tests/testthat/test-e2sfca-allocator-semantic-adversarial-2026-07-19.R",
    why = "Area-weighted allocation loses its normaliser: population is multiplied by raw area, so the tract total no longer conserves."),
  allocator_conservation_check_disabled = list(
    old = "  if (worst > conservation_tol) {",
    new = "  if (FALSE) {",
    suites = "tests/testthat/test-e2sfca-allocator-semantic-adversarial-2026-07-19.R",
    why = "The per-tract conservation guard is switched off, so a non-conserving allocation passes silently."),
  # NOT INCLUDED: allocator_global_check_disabled.
  # The global guard (`global_rel > conservation_tol`) is a redundant aggregate
  # cross-check that cannot be reached while the per-tract guard is intact:
  # global_rel is an aggregate of the same residuals, so it is never larger than
  # the worst per-tract error, and the per-tract guard therefore always fires
  # first. No test can kill a mutant of it without also disabling the per-tract
  # guard. Established by analysis after it survived the corpus, and recorded
  # here rather than quietly dropped -- it is defence in depth, not dead code,
  # but it is untestable in isolation and this corpus does not pretend otherwise.

  # --- URPS scenario supply ----------------------------------------------------
  urps_scale_inverted = list(
    old = "  scale <- ifelse(base_tot > 0, tgt / base_tot, 0)",
    new = "  scale <- ifelse(base_tot > 0, base_tot / tgt, 0)",
    file = URPS,
    suites = c("tests/testthat/test-urps-accessibility-scenarios.R",
               "tests/testthat/test-urps-accessibility-e2sfca-adapter.R"),
    why = "Workforce-projection rescaling inverted: a scenario that should grow supply shrinks it."),
  urps_reached_counts_all_tracts = list(
    old = "    n_reached_tracts      = sum(a > 0),",
    new = "      n_reached_tracts      = length(a),",
    file = URPS,
    suites = c("tests/testthat/test-urps-accessibility-scenarios.R",
               "tests/testthat/test-urps-accessibility-e2sfca-adapter.R"),
    why = "Every tract counts as reached regardless of access, inflating the SPAR denominator."),

  abel_tail_not_zero = list(
    old = "  next_w <- c(wp[-1L], 0)                       # W beyond the last band = 0",
    new = "  next_w <- c(wp[-1L], wp[length(wp)])          # W beyond the last band = 0",
    why = "The Abel identity requires W beyond the last band to be 0; setting it to the last weight silently deletes the outermost band's contribution."),
  normalize_weights_accidentally = list(
    old = "  inc[inc < 0 & inc > -1e-9] <- 0               # clamp float error",
    new = "  inc <- inc / sum(inc)                        # clamp float error",
    # Access is INERT to a common rescaling of the incremental weights: demand
    # scales by c, the ratio by 1/c, and the two cancel in Step 2. So this mutant
    # cannot be caught by any accessibility assertion, and it survived the first
    # corpus run for exactly that reason. What it DOES corrupt is the reported
    # provider-to-population ratio R_j and the returned weight vector, which are
    # outputs consumers read. It is killed by the provider-ratio test.
    why = "Incremental weights renormalised: accessibility is unchanged, but every REPORTED provider ratio R_j is wrong by a constant factor.")
)

# --- harness ------------------------------------------------------------------
originals <- stats::setNames(lapply(TARGETS, readLines, warn = FALSE), TARGETS)
restore <- function() for (f in TARGETS) writeLines(originals[[f]], f)
on.exit(restore(), add = TRUE)   # never leave a mutated source behind

run_suite <- function(path) {
  # Returns TRUE if the suite reported at least one failure or error.
  out <- suppressWarnings(system2(
    file.path(R.home("bin"), "Rscript"),
    c("-e", shQuote(sprintf(
      "testthat::set_max_fails(Inf); r <- as.data.frame(testthat::test_file('%s', reporter='silent')); cat(sum(r$failed), sum(r$error))",
      path))),
    stdout = TRUE, stderr = TRUE))
  nums <- suppressWarnings(as.integer(strsplit(trimws(tail(out, 1)), "\\s+")[[1]]))
  if (length(nums) < 2 || anyNA(nums)) return(TRUE)  # a crash counts as detected
  sum(nums) > 0
}

cat("scientific mutation corpus:", length(MUTANTS), "mutants x",
    length(SUITES), "suite(s)\n\n")

results <- list()
for (nm in names(MUTANTS)) {
  m <- MUTANTS[[nm]]
  target <- if (!is.null(m$file)) m$file else ENGINE
  suites <- if (!is.null(m$suites)) m$suites else SUITES
  txt <- paste(originals[[target]], collapse = "\n")
  hits <- lengths(regmatches(txt, gregexpr(m$old, txt, fixed = TRUE)))
  if (hits != 1L) {
    cat(sprintf("  %-32s ANCHOR ERROR in %s (%d matches)\n", nm, basename(target), hits))
    results[[nm]] <- list(killed = NA, by = NA_character_, hits = hits)
    next
  }
  writeLines(strsplit(sub(m$old, m$new, txt, fixed = TRUE), "\n")[[1]], target)

  killed_by <- NA_character_
  for (s in suites) if (run_suite(s)) { killed_by <- basename(s); break }
  restore()

  results[[nm]] <- list(killed = !is.na(killed_by), by = killed_by, hits = 1L)
  cat(sprintf("  %-32s %s%s\n", nm,
              if (!is.na(killed_by)) "KILLED  " else "SURVIVED",
              if (!is.na(killed_by)) paste0("by ", killed_by) else ""))
}

restore()
for (f in TARGETS)
  stopifnot(identical(readLines(f, warn = FALSE), originals[[f]]))
cat("\nall ", length(TARGETS), " mutated sources restored byte-identical\n", sep = "")

survived <- names(Filter(function(r) isFALSE(r$killed), results))
anchor_err <- names(Filter(function(r) is.na(r$killed), results))

if (length(anchor_err)) {
  message("\nFAIL: anchor no longer matches for: ", paste(anchor_err, collapse = ", "),
          "\n  The engine was refactored and these mutants stopped mutating anything.",
          "\n  A corpus that silently mutates nothing is worse than no corpus.")
}
if (length(survived)) {
  message("\nFAIL: mutant(s) SURVIVED the scientific suites:")
  for (nm in survived) message("  - ", nm, ": ", MUTANTS[[nm]]$why)
  message("  A surviving high-consequence mutant is a release blocker whatever ",
          "the coverage number says.")
}
if (length(survived) || length(anchor_err)) quit(status = 1L, save = "no")

cat("all", length(MUTANTS), "scientific mutants killed\n")
