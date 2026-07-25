# SSOT guards for the access constants ported from isochrones (behavior-neutral).
# Standardizes twostep on the same single-source-of-truth modules:
#   R/contour_bands.R      PRIMARY_ACCESS_BAND_SEC (60 min / 3600 s)
#   R/access_categories.R  DENOMINATOR_CATEGORY ("total_female")
#   R/access_thresholds.R  TRACT_REACHED_COVERAGE_PCT (50% majority "reached")
suppressWarnings(suppressMessages(library(testthat)))
root <- tryCatch(here::here(), error = function(e) getwd())
source(file.path(root, "R", "contour_bands.R"))
source(file.path(root, "R", "access_categories.R"))
source(file.path(root, "R", "access_thresholds.R"))

test_that("canonical values match the isochrones SSOTs", {
  expect_equal(PRIMARY_ACCESS_BAND_SEC, 3600L)
  expect_equal(PRIMARY_ACCESS_BAND_MIN, 60L)
  expect_identical(DENOMINATOR_CATEGORY, "total_female")
  expect_equal(TRACT_REACHED_COVERAGE_PCT, 50L)
})

test_that("seconds are derived from minutes; reached cut is a percent", {
  expect_identical(PRIMARY_ACCESS_BAND_SEC, PRIMARY_ACCESS_BAND_MIN * 60L)
  expect_true(TRACT_REACHED_COVERAGE_PCT > 0L && TRACT_REACHED_COVERAGE_PCT <= 100L)
  expect_false(grepl("^total_female_", DENOMINATOR_CATEGORY))
})

test_that("no wired manuscript_catalog producer re-hardcodes the literals", {
  dir <- file.path(root, "scripts", "manuscript_catalog")
  skip_if(!dir.exists(dir), "no manuscript_catalog dir")
  offenders <- character(0)
  for (f in list.files(dir, pattern = "\\.R$", full.names = TRUE)) {
    code <- sub("#.*$", "", readLines(f, warn = FALSE))               # strip comments
    hits <- grep('BAND\\s*<-\\s*3600|range\\s*==\\s*3600|category\\s*[=!]=\\s*"total_female"|percent\\s*>=\\s*50\\b',
                 code, value = TRUE)
    if (length(hits)) offenders <- c(offenders, sprintf("%s: %s", basename(f), hits[1]))
  }
  expect_identical(offenders, character(0),
                   info = paste("stale literal still present:\n ", paste(offenders, collapse = "\n  ")))
})

test_that("the intentional 4-band SET map is preserved (NOT collapsed)", {
  aee <- file.path(root, "scripts", "manuscript_catalog", "build_access_equity_executive.R")
  skip_if(!file.exists(aee))
  code <- readLines(aee, warn = FALSE)
  expect_true(any(grepl('"60"\\s*=\\s*3600L', code)),
              info = "the 4-band generation set map must remain a literal set")
})

test_that("repo SSOT values equal the shared mufflyaccess package (no cross-repo drift)", {
  skip_if_not(requireNamespace("mufflyaccess", quietly = TRUE))
  expect_identical(PRIMARY_ACCESS_BAND_SEC,     mufflyaccess::PRIMARY_ACCESS_BAND_SEC)
  expect_identical(DENOMINATOR_CATEGORY,        mufflyaccess::DENOMINATOR_CATEGORY)
  expect_identical(TRACT_REACHED_COVERAGE_PCT,  mufflyaccess::TRACT_REACHED_COVERAGE_PCT)
})
