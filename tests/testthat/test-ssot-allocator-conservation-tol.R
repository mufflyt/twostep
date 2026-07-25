# ==============================================================================
# SSOT guard: the allocator conservation tolerance.
#
# Authority: the engine function default
# allocate_pop_areaweighted(conservation_tol = 1e-6) in
# R/two_step_floating_catchment.R. It is the max relative per-tract/global
# population-allocation error before the allocator stop()s.
#
# The engine file is sha-gated (run_2sfca.R computes its whole-file sha256 and hard
# stop()s on mismatch — the allocator-identity gate), so the tolerance is NOT promoted
# to a separate constant (that would change the file's sha and break the gate).
# Instead the producer records the tolerance by reading the engine's live default via
# formals(), so the run manifest can never restate a value that disagrees with the
# engine. This guard pins that wiring.
#
# NOT unified (deliberately distinct): the NATIONAL conservation tolerance is a
# separate run-level knob (E2SFCA_NATIONAL_CONS_TOL, default 0.005); the codebase's
# float-guard epsilons (1e-9, 1e-12, .Machine$double.eps, seam gate 0.02/0.01) are
# independent numerical guards.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "two_step_floating_catchment.R"))

test_that("the engine allocator default is the single 1e-6 conservation tolerance", {
  tol <- eval(formals(allocate_pop_areaweighted)$conservation_tol)
  expect_identical(tol, 1e-6)
  expect_gt(tol, 0); expect_lt(tol, 1)
  # both allocator entry points share the one default
  expect_identical(formals(allocate_pop_areaweighted)$conservation_tol,
                   formals(attach_e2sfca_population)$conservation_tol)
})

test_that("the producer records the tolerance from the engine default, not a literal", {
  run <- readLines(file.path(root, "scripts", "run_2sfca.R"), warn = FALSE)
  # no restated literal in the manifest tolerances block
  expect_false(any(grepl("allocator_conservation_tol = 1e-6", run, fixed = TRUE)))
  # it reads the engine default live
  expect_true(any(grepl(
    "allocator_conservation_tol =", run, fixed = TRUE) &
    grepl("formals(allocate_pop_areaweighted)", run, fixed = TRUE)) ||
    any(grepl("formals(allocate_pop_areaweighted)$conservation_tol", run,
              fixed = TRUE)))
})

test_that("allocator tol stays DISTINCT from the national conservation tol", {
  run <- readLines(file.path(root, "scripts", "run_2sfca.R"), warn = FALSE)
  natl <- grep("NATIONAL_CONSERVATION_TOL <- as.numeric", run, value = TRUE)
  expect_length(natl, 1L)
  expect_match(natl, '"0.005"', fixed = TRUE)   # national default 0.5%, != 1e-6
  tol <- eval(formals(allocate_pop_areaweighted)$conservation_tol)
  expect_false(isTRUE(all.equal(tol, 0.005)))
})
