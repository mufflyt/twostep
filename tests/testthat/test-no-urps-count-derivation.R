# tests/testthat/test-no-urps-count-derivation.R
# CONSUMER GUARD: twostep must CONSUME canonical URPS counts from mufflyaccess
# (mufflyaccess::urps_count()), never DERIVE or hardcode them. This static scan
# fails if any forbidden URPS workforce scalar appears in twostep PRODUCTION code
# (R/ + scripts/): the SSOT symbol family URPS_COUNT*, or the workforce-count
# literals enumerated below. tests/ and docs/ are NOT scanned (they legitimately
# reference expected, retired, and rejected values).
#
# Bug-fixed vs the naive version:
#   (1) numeric literals use perl word-boundary look-arounds, so 308 is NOT
#       falsely matched inside 13082, 0.308, or 3080; and
#   (2) the exclusion is achieved by scanning only R/ + scripts/ (not "."), so the
#       guard never scans the test files that legitimately hold these literals.
library(testthat)

test_that("twostep production code does not derive or hardcode canonical URPS counts", {
  root  <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
  dirs  <- file.path(root, c("R", "scripts"))
  files <- list.files(dirs[dir.exists(dirs)], pattern = "\\.[Rr]$",
                      recursive = TRUE, full.names = TRUE)

  # Canonical URPS workforce scalars must be obtained through
  # mufflyaccess::urps_count(), never derived or hardcoded in twostep production.
  #   CURRENT (contract 3.0.0):
  #     1306 = 2023 board_certified_active, national, with urology
  #     1303 = 2023 board_certified_active, CONUS,    with urology
  #   RETIRED (contract v2.1.0) -- must NEVER appear as current expected values:
  #     1332 / 1329 = the superseded 2023 national / CONUS cells
  #   ROSTER SNAPSHOT (unconfirmed until contract 3.0.0 exposes it):
  #     1339 = 2025 roster_snapshot (NOT a 2023 active count)
  #   CLIFF LEGACY frozen projection cohort:
  #     1295
  # A literal is allowed ONLY when it is obtained via the canonical API, explicitly
  # labeled a retired historical cell, explicitly labeled Cliff's legacy frozen
  # projection, or used in a test that verifies rejection / historical lineage.
  num_forbidden <- c("1306", "1303", "1332", "1329", "1339", "1295")
  sym_forbidden <- c("URPS_COUNT")

  offenders <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
    for (lit in num_forbidden) {
      pat <- paste0("(?<![0-9.])", lit, "(?![0-9.])")       # standalone number only
      hit <- grep(pat, lines, perl = TRUE)
      if (length(hit))
        offenders <- c(offenders, sprintf("%s:%d  literal %s", basename(f), hit[1], lit))
    }
    for (sym in sym_forbidden) {
      hit <- grep(paste0("\\b", sym), lines, perl = TRUE)
      if (length(hit))
        offenders <- c(offenders, sprintf("%s:%d  symbol %s", basename(f), hit[1], sym))
    }
  }

  expect_identical(
    offenders, character(0),
    info = paste0(
      "twostep must consume mufflyaccess::urps_count(), not derive/hardcode counts:\n  ",
      paste(offenders, collapse = "\n  ")))
})
