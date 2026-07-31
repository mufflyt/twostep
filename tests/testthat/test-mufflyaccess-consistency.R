# Vendored-SSOT contract guard: the accessibility-disparity statistics were
# promoted to the shared (private) mufflyaccess package and are now VENDORED back
# into twostep in R/accessibility_stratification.R so the repo is self-contained.
# This test fails loudly if (a) the vendored file stops defining the promoted
# symbols, or (b) a boundary behavior drifts from the frozen contract. It is the
# twostep analogue of isochrones' test-mufflyaccess-consistency.R.
suppressWarnings(suppressMessages(library(testthat)))

test_that("the vendored module defines every promoted symbol", {
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  for (fn in c("weighted_mean_all", "zero_access_share", "rurality_from_ruca",
               "tract_vintage_of", "acs_year_of", "mc_weighted_ci", "annual_trend"))
    expect_true(is.function(get(fn)), info = fn)
  expect_identical(TOTAL_FEMALE_VAR, "B01001_026")
  expect_true(all(c("white_nh","hispanic","black","aian","asian","nhpi") %in% names(RACE_FEMALE_VARS)))
})

test_that("the promoted functions are vendored locally (self-contained, no package dependency)", {
  source(testthat::test_path("..", "..", "R", "accessibility_stratification.R"))
  # vendoring means twostep must NOT depend on the private package being installed
  expect_false("mufflyaccess" %in% loadedNamespaces())
  for (fn in c("weighted_mean_all", "rurality_from_ruca", "mc_weighted_ci"))
    expect_true(is.function(get(fn)), info = fn)
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
