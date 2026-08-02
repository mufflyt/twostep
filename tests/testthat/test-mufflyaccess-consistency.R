# Shared-SSOT contract guard: the accessibility-disparity statistics live in the
# shared mufflyaccess package (now public + pinned) and are sourced LIVE by
# R/accessibility_stratification.R (a shim). This test fails loudly if (a) the shim
# stops re-exporting a promoted symbol, or (b) a boundary behavior drifts from the
# frozen contract. It is the twostep analogue of isochrones' consistency test.
suppressWarnings(suppressMessages(library(testthat)))

test_that("the shim re-exports every promoted symbol", {
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  for (fn in c("weighted_mean_all", "zero_access_share", "rurality_from_ruca",
               "tract_vintage_of", "acs_year_of", "mc_weighted_ci", "annual_trend"))
    expect_true(is.function(get(fn)), info = fn)
  expect_identical(TOTAL_FEMALE_VAR, "B01001_026")
  expect_true(all(c("white_nh","hispanic","black","aian","asian","nhpi") %in% names(RACE_FEMALE_VARS)))
})

test_that("the promoted symbols are the mufflyaccess SSOT (no local drift)", {
  skip_if_not(requireNamespace("mufflyaccess", quietly = TRUE),
              "mufflyaccess (>= 0.10.0) is required")
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  # sourced symbols must be identical to the package's (live, not a local copy)
  for (fn in c("weighted_mean_all", "rurality_from_ruca", "mc_weighted_ci"))
    expect_identical(get(fn), getExportedValue("mufflyaccess", fn), info = fn)
})

test_that("rurality boundary contract is frozen (metro 1-3, rural 4-10, else NA)", {
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  expect_equal(rurality_from_ruca(c(1, 3, 4, 10, 0, 11, NA)),
               c("Metropolitan","Metropolitan","Rural","Rural", NA, NA, NA))
})

test_that("tract vintage + acs year boundary contracts are frozen", {
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  expect_equal(tract_vintage_of(c(2019, 2020)), c(2010L, 2020L))
  expect_equal(acs_year_of(c(2010, 2013, 2020, 2025)), c(2013L, 2013L, 2020L, 2022L))
})
