# ==============================================================================
# SSOT guard: base E2SFCA distance-decay band weights.
#
# The canonical value is E2SFCA_DEFAULT_WEIGHTS in R/two_step_floating_catchment.R.
# These weights define the distance decay used in every access computation, so a
# drifted copy silently changes published numbers. This guard pins the canonical
# vector and detects any file that defines a BASE band-weight vector (one built
# around 0.68) that disagrees with it. The deliberate sharper/slower sensitivity
# variants do not contain 0.68 and are intentionally out of scope.
# ==============================================================================
library(testthat)
source(testthat::test_path("..", "..", "R", "two_step_floating_catchment.R"))

CANON <- c("30" = 1.00, "60" = 0.68, "120" = 0.22, "180" = 0.09)

test_that("canonical E2SFCA_DEFAULT_WEIGHTS is the documented base vector", {
  expect_identical(names(E2SFCA_DEFAULT_WEIGHTS), names(CANON))
  expect_equal(unname(E2SFCA_DEFAULT_WEIGHTS), unname(CANON))
  # nearest band is normalized to 1 and weights are monotone non-increasing
  expect_equal(unname(E2SFCA_DEFAULT_WEIGHTS["30"]), 1.00)
  expect_true(all(diff(E2SFCA_DEFAULT_WEIGHTS) <= 0))
})

test_that("desjardins7 module's DJ7_WC_BASE agrees with the engine canonical", {
  # The desjardins7 recreation keeps its own base-R copy (DJ7_WC_BASE) so it can run
  # standalone; it must never drift from the engine's E2SFCA_DEFAULT_WEIGHTS. Assert
  # the two named in-code constants are identical in names and values.
  source(testthat::test_path("..", "..", "R", "desjardins7_e2sfca.R"))
  expect_identical(names(DJ7_WC_BASE), names(E2SFCA_DEFAULT_WEIGHTS))
  expect_equal(unname(DJ7_WC_BASE), unname(E2SFCA_DEFAULT_WEIGHTS))
})

test_that("no R file defines a base band-weight vector that drifts from the canonical", {
  root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
  canonical_file <- normalizePath(file.path(root, "R", "two_step_floating_catchment.R"))
  files <- list.files(c(file.path(root, "R"), file.path(root, "scripts")),
                      pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  drifted <- character(0)
  for (f in files) {
    if (normalizePath(f) == canonical_file) next
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    # A BASE weight vector is a c(...) literal that mentions 0.68 (the 60-min weight).
    frags <- regmatches(txt, gregexpr("c\\([^)]*0\\.68[^)]*\\)", txt))[[1]]
    for (frag in frags) {
      nums <- suppressWarnings(as.numeric(
        regmatches(frag, gregexpr("[0-9]+\\.[0-9]+", frag))[[1]]))
      nums <- round(nums, 2)
      # Only a full FOUR-band vector is a base copy; deliberate scenario variants
      # that drop a band (e.g. drop180, three weights) are intentionally excluded.
      if (length(nums) == 4 && !setequal(nums, unname(CANON)))
        drifted <- c(drifted, sprintf("%s: %s", basename(f), frag))
    }
  }
  expect_true(length(drifted) == 0,
              info = paste("base-weight copies that drift from the canonical:",
                           paste(drifted, collapse = " | ")))
})
