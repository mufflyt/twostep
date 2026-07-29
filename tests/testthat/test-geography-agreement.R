# tests/testthat/test-geography-agreement.R
# Contract for assert_matching_geography(): the E2SFCA workforce numerator and the
# population/access denominator must share one geography (boundary enforcement).
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "geography_agreement.R"))

test_that("matching geographies pass and return TRUE invisibly", {
  expect_true(assert_matching_geography("national", "national"))
  expect_true(assert_matching_geography("conus", "conus"))
  expect_true(assert_matching_geography("08", "08"))          # state FIPS
})

test_that("mismatched geographies fail loudly (numerator vs denominator)", {
  expect_error(assert_matching_geography("national", "conus"), "geography mismatch")
  expect_error(assert_matching_geography("conus", "national"), "geography mismatch")
  expect_error(assert_matching_geography("08", "national"), "geography mismatch")
})

test_that("degenerate geography labels are rejected", {
  expect_error(assert_matching_geography(c("national", "conus"), "national"), "single")
  expect_error(assert_matching_geography(NA_character_, "national"), "missing")
  expect_error(assert_matching_geography("", "national"), "single|missing")
})
