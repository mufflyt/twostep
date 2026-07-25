# ==============================================================================
# SSOT guard: the per-100k access thresholds (share_ge_* cut points).
#
# Canonical: E2SFCA_DEFAULT_THRESHOLDS <- c(0, 1, 5, 10, 20, 50) in
# R/two_step_floating_catchment.R. These are the provider-per-100k cut points that
# define the frozen national summary's share_ge_<k> columns.
#
# Status: the thresholds are ALREADY fully SSOT — every consumer (seam_test THRESHOLDS,
# the three map scripts, the engine functions) references the constant. The only
# literal restatement, scripts/seam_test_2sfca.R:80
# `identical(as.numeric(THRESHOLDS), c(0,1,5,10,20,50))`, is a DELIBERATE
# prespecified-value LOCK (the seam header: "fixed BEFORE any national result was
# examined; DO NOT tune") — an intentional independent cross-check, NOT drift, so it is
# preserved. This guard pins the canonical value, confirms consumers reference the
# constant, cross-checks the seam lock against the constant, and ties the frozen CSV
# columns to the thresholds.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "two_step_floating_catchment.R"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))  # e2sfca_run_dir

CANON <- c(0, 1, 5, 10, 20, 50)

test_that("E2SFCA_DEFAULT_THRESHOLDS is the canonical monotone-increasing cut points", {
  expect_identical(as.numeric(E2SFCA_DEFAULT_THRESHOLDS), CANON)
  expect_true(all(diff(E2SFCA_DEFAULT_THRESHOLDS) > 0))
  eng <- readLines(file.path(root, "R", "two_step_floating_catchment.R"), warn = FALSE)
  expect_length(grep("E2SFCA_DEFAULT_THRESHOLDS\\s*<-", eng), 1L)   # defined once
})

test_that("consumers reference the constant, not a threshold literal", {
  for (f in c("scripts/seam_test_2sfca.R",
              "scripts/map_go_2020_access_surface.R",
              "scripts/map_fpmrs_allyears_access_surface.R",
              "scripts/map_allsubspec_allyears_access_surface.R")) {
    txt <- readLines(file.path(root, f), warn = FALSE)
    expect_true(any(grepl("E2SFCA_DEFAULT_THRESHOLDS", txt, fixed = TRUE)),
                info = paste(f, "does not reference E2SFCA_DEFAULT_THRESHOLDS"))
  }
})

test_that("the seam prespecified LOCK literal still matches the canonical", {
  # Intentional independent restatement (a contract lock). If the engine default ever
  # changes, both this test AND the seam runtime assertion must fail on purpose.
  seam <- readLines(file.path(root, "scripts", "seam_test_2sfca.R"), warn = FALSE)
  lock <- grep("prespecified set", seam, value = TRUE)
  expect_length(lock, 1L)
  nums <- as.numeric(regmatches(lock, gregexpr("[0-9]+", lock))[[1]])
  expect_identical(nums, CANON)
})

test_that("the frozen CSV share_ge_<k> columns are exactly the canonical thresholds", {
  run_dir <- e2sfca_run_dir(root = root)
  hdr <- strsplit(readLines(file.path(run_dir, "e2sfca_national_summary.csv"),
                            n = 1L), ",")[[1]]
  suffixes <- as.integer(gsub("[^0-9]", "",
                              grep("share_ge", hdr, value = TRUE)))
  expect_identical(sort(suffixes), sort(as.integer(CANON)))
})
