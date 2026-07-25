# ==============================================================================
# SSOT guard: the seam-test allocation-method vocabulary.
#
# Canonical: SEAM_METHODS in scripts/seam_test_2sfca.R — the four allocation methods
# (raw, equal_total, mass_conserving, mass_conserving_eqtot) in reporting order.
# EXPECTED_METHODS (run-contract validation) and METHOD_ORDER (output row order) were
# byte-identical duplicates; both now derive from SEAM_METHODS. A drifted copy would
# validate against one list while ordering output by another.
#
# The seam script is the relaunch-gate runner (heavy top-level code), so it cannot be
# sourced in a unit test; this guard parses it textually. Distinctions preserved:
# mass_conserving = production allocator (E2SFCA_ALLOCATOR_METHOD_ID);
# mass_conserving_eqtot = total-fixed gate-basis diagnostic (a different method).
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
seam <- readLines(file.path(root, "scripts", "seam_test_2sfca.R"), warn = FALSE)
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))  # E2SFCA_ALLOCATOR_METHOD_ID

CANON <- c("raw", "equal_total", "mass_conserving", "mass_conserving_eqtot")

parse_vec <- function(varname) {
  line <- grep(sprintf("^%s\\s*<-\\s*c\\(", varname), seam, value = TRUE)
  if (!length(line)) return(NULL)
  gsub('"', "", regmatches(line, gregexpr('"[a-z_]+"', line))[[1]])
}

test_that("SEAM_METHODS is the four documented methods in reporting order", {
  sm <- parse_vec("SEAM_METHODS")
  expect_identical(sm, CANON)
  expect_false(any(duplicated(sm)))
})

test_that("EXPECTED_METHODS and METHOD_ORDER derive from SEAM_METHODS, not literals", {
  expect_true(any(grepl("^EXPECTED_METHODS\\s*<-\\s*SEAM_METHODS", seam)))
  expect_true(any(grepl("^METHOD_ORDER\\s*<-\\s*SEAM_METHODS", seam)))
  # neither is re-defined as its own 4-string literal any more
  expect_length(grep('^(EXPECTED_METHODS|METHOD_ORDER)\\s*<-\\s*c\\(', seam), 0L)
})

test_that("production and gate-basis methods are both present and distinct", {
  sm <- parse_vec("SEAM_METHODS")
  expect_true("mass_conserving" %in% sm)          # production allocator
  expect_true("mass_conserving_eqtot" %in% sm)    # gate-basis diagnostic
  expect_false(identical("mass_conserving", "mass_conserving_eqtot"))
  # cross-tie: the production method equals the canonical allocator id (iteration 5)
  expect_true(E2SFCA_ALLOCATOR_METHOD_ID %in% sm)
  expect_identical(E2SFCA_ALLOCATOR_METHOD_ID, "mass_conserving")
})

test_that("every by_method$<name> access refers to a canonical method", {
  accessed <- unique(gsub("by_method\\$", "",
    regmatches(seam, gregexpr("by_method\\$[a-z_]+", seam)) |> unlist()))
  expect_true(all(accessed %in% CANON),
              info = paste("unknown by_method access:",
                           paste(setdiff(accessed, CANON), collapse = ", ")))
})
