# ==============================================================================
# SSOT guard: the allocator method_id the manuscript run was validated against.
#
# Canonical: E2SFCA_ALLOCATOR_METHOD_ID in scripts/manuscript_e2sfca_values.R.
# This provenance string asserts WHICH allocator produced the frozen numbers; if it
# silently disagrees with the manifest the manuscript would claim a run it did not
# use. Authority = the frozen manifest allocator$method_id (written by the producer
# scripts/run_2sfca.R). This guard pins the constant to the manifest, checks it is a
# real member of the seam-test method vocabulary, and confirms the loader assertion
# references the constant rather than a second literal.
#
# NOTE (out of scope): the allocator module_sha256 (2b78718b... frozen vs 11abdec3...
# current-file re-pin, 2026-07-24) is a deliberate two-value provenance distinction
# with the manifest as SSOT for the frozen sha; it is intentionally NOT canonicalized
# here (see docs/SSOT_LEDGER.md iteration 5).
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

test_that("E2SFCA_ALLOCATOR_METHOD_ID is a single non-empty identity string", {
  expect_type(E2SFCA_ALLOCATOR_METHOD_ID, "character")
  expect_length(E2SFCA_ALLOCATOR_METHOD_ID, 1L)
  expect_true(nzchar(E2SFCA_ALLOCATOR_METHOD_ID))
})

test_that("constant matches the frozen manifest allocator method_id", {
  run_dir <- e2sfca_run_dir(root = root)
  manifest <- jsonlite::read_json(file.path(run_dir, "e2sfca_run_manifest.json"))
  expect_identical(manifest$allocator$method_id, E2SFCA_ALLOCATOR_METHOD_ID)
  # the frozen run must have verified its allocator identity
  expect_true(isTRUE(manifest$allocator$identity_verified))
})

test_that("the canonical method is a member of the seam-test method vocabulary", {
  # Parse EXPECTED_METHODS out of the seam test so the production method is checked
  # against the actual controlled vocabulary, not a hand-copied list.
  seam <- readLines(file.path(root, "scripts", "seam_test_2sfca.R"), warn = FALSE)
  # the method vocabulary is the canonical SEAM_METHODS vector (EXPECTED_METHODS and
  # METHOD_ORDER now derive from it; see test-ssot-seam-methods.R)
  line <- grep("^SEAM_METHODS\\s*<-", seam, value = TRUE)
  expect_length(line, 1L)
  vocab <- unlist(regmatches(line, gregexpr('"([^"]+)"', line)))
  vocab <- gsub('"', "", vocab)
  expect_true(E2SFCA_ALLOCATOR_METHOD_ID %in% vocab)
})

test_that("the loader references the constant, not a second method_id literal", {
  # Within the loader, the literal may appear exactly once: the constant definition.
  loader <- readLines(file.path(root, "scripts", "manuscript_e2sfca_values.R"),
                      warn = FALSE)
  hits <- grep('"mass_conserving"', loader, fixed = TRUE)
  expect_length(hits, 1L)
})
