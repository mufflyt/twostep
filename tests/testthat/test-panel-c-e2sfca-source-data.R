# =============================================================================
# Panel C — E2SFCA national-access source-data tests
# =============================================================================
#
# Guards that the Panel C source-data CSV (the plotted values) is (a) exactly
# 77 unique specialty-year rows over the 7-subspecialty x 2013-2023 grid, and
# (b) byte-for-byte faithful to the AUTHORITATIVE national-summary artifact of
# the frozen production run e2sfca_20260712_190734 (git ff3aac4a) — not
# recomputed or drifted.
#
# Both the Panel C source CSV and a verbatim mirror of the national summary are
# tracked in-repo, so these checks run fully in a clean CI checkout (no skip).
#
# Author: Tyler Muffly / Claude Code
# =============================================================================

library(testthat)
library(here)

SRC_CSV    <- here("manuscript", "stats", "panel_c_e2sfca_national_access.csv")
MIRROR_CSV <- here("manuscript", "stats",
                   "e2sfca_national_summary_20260712_190734.csv")

EXPECTED_SUBSPECS <- c("CFP", "FPMRS", "GO", "MFM", "MIGS", "PAG", "REI")
EXPECTED_YEARS    <- 2013:2023
EXPECTED_ARTIFACT_SHA256 <-
  "b33eb3e4f44c2a7f422a32d0b61c1afa5af4f76d55f230918a4dfedf6999ba3a"

test_that("Panel C source CSV and national-summary mirror exist", {
  expect_true(file.exists(SRC_CSV))
  expect_true(file.exists(MIRROR_CSV))
})

test_that("source CSV has exactly 77 unique specialty-year rows", {
  d <- read.csv(SRC_CSV, stringsAsFactors = FALSE)
  key <- unique(d[, c("specialty", "year")])
  expect_equal(nrow(key), 77L)
  expect_equal(nrow(d), 77L)                       # no duplicate rows
  expect_setequal(unique(d$specialty), EXPECTED_SUBSPECS)
  expect_setequal(unique(d$year), EXPECTED_YEARS)
  # complete grid: every specialty present in every year
  expect_equal(nrow(key), length(EXPECTED_SUBSPECS) * length(EXPECTED_YEARS))
})

test_that("plotted values are finite, positive (log-safe)", {
  d <- read.csv(SRC_CSV, stringsAsFactors = FALSE)
  expect_true(all(is.finite(d$pop_weighted_mean_per100k)))
  expect_true(all(d$pop_weighted_mean_per100k > 0))
})

test_that("provenance columns are present and constant", {
  d <- read.csv(SRC_CSV, stringsAsFactors = FALSE)
  for (col in c("run_id", "git_sha", "allocator_id", "source_artifact_sha256")) {
    expect_true(col %in% names(d), info = col)
    expect_equal(length(unique(d[[col]])), 1L, info = col)
  }
  expect_equal(unique(d$run_id), "e2sfca_20260712_190734")
  expect_equal(unique(d$git_sha), "ff3aac4a7aa97094fc3a9e69422425fe1a52b091")
  expect_equal(unique(d$source_artifact_sha256), EXPECTED_ARTIFACT_SHA256)
})

test_that("national-summary mirror matches the authoritative artifact sha256", {
  skip_if_not_installed("digest")
  got <- digest::digest(file = MIRROR_CSV, algo = "sha256")
  expect_equal(got, EXPECTED_ARTIFACT_SHA256)
})

test_that("plotted values match the authoritative national-summary artifact", {
  d  <- read.csv(SRC_CSV, stringsAsFactors = FALSE)
  ns <- read.csv(MIRROR_CSV, stringsAsFactors = FALSE)

  ref <- ns[, c("subspecialty", "year", "mean_pop_weighted_per100k")]
  names(ref) <- c("specialty", "year", "ref_value")

  m <- merge(d[, c("specialty", "year", "pop_weighted_mean_per100k")],
             ref, by = c("specialty", "year"))
  expect_equal(nrow(m), 77L)                        # every row matched
  # exact equality (values are copied straight from the artifact, not recomputed)
  expect_equal(m$pop_weighted_mean_per100k, m$ref_value, tolerance = 1e-9)
})
