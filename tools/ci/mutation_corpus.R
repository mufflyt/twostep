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

SUITES <- c("tests/testthat/test-e2sfca-luo-qi-2009-published.R",
            "tests/testthat/test-e2sfca-invariants-and-reference.R",
            "tests/testthat/test-e2sfca-metamorphic-and-algebra.R",
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
original <- readLines(ENGINE, warn = FALSE)
restore  <- function() writeLines(original, ENGINE)
on.exit(restore(), add = TRUE)   # never leave a mutated engine behind

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
  txt <- paste(original, collapse = "\n")
  hits <- lengths(regmatches(txt, gregexpr(m$old, txt, fixed = TRUE)))
  if (hits != 1L) {
    cat(sprintf("  %-32s ANCHOR ERROR (%d matches)\n", nm, hits))
    results[[nm]] <- list(killed = NA, by = NA_character_, hits = hits)
    next
  }
  writeLines(strsplit(sub(m$old, m$new, txt, fixed = TRUE), "\n")[[1]], ENGINE)

  killed_by <- NA_character_
  for (s in SUITES) if (run_suite(s)) { killed_by <- basename(s); break }
  restore()

  results[[nm]] <- list(killed = !is.na(killed_by), by = killed_by, hits = 1L)
  cat(sprintf("  %-32s %s%s\n", nm,
              if (!is.na(killed_by)) "KILLED  " else "SURVIVED",
              if (!is.na(killed_by)) paste0("by ", killed_by) else ""))
}

restore()
stopifnot(identical(readLines(ENGINE, warn = FALSE), original))
cat("\nengine restored byte-identical\n")

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
