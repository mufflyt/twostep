# ==============================================================================
# SSOT guard: the frozen production run id backing the manuscript.
#
# Canonical: E2SFCA_FROZEN_RUN_ID + e2sfca_run_dir() in
# scripts/manuscript_e2sfca_values.R. Every artifact path derives from the
# constant, and the run manifest's self-declared run_id must match it. A stale or
# copy-pasted path is how wrong numbers silently reach the manuscript, so this
# guard (1) checks the constant agrees with the manifest, (2) checks the resolver
# fails loudly on a missing/mismatched run, and (3) scans the code for any path
# built from a hardcoded run-id literal instead of the constant.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

LITERAL <- "e2sfca_20260712_190734"

test_that("E2SFCA_FROZEN_RUN_ID is a single non-empty run id", {
  expect_type(E2SFCA_FROZEN_RUN_ID, "character")
  expect_length(E2SFCA_FROZEN_RUN_ID, 1L)
  expect_true(nzchar(E2SFCA_FROZEN_RUN_ID))
})

test_that("e2sfca_run_dir() resolves to a dir whose manifest run_id matches the constant", {
  dir <- e2sfca_run_dir(root = root)
  expect_true(dir.exists(dir))
  manifest <- file.path(dir, "e2sfca_run_manifest.json")
  expect_true(file.exists(manifest))
  declared <- jsonlite::read_json(manifest)$run_id
  # canonical constant reaches the artifact, and the artifact agrees with it
  expect_identical(declared, E2SFCA_FROZEN_RUN_ID)
})

test_that("resolver fails loudly on a missing run (no silent fallback)", {
  expect_error(e2sfca_run_dir(run_id = "e2sfca_does_not_exist", root = root),
               "missing")
})

test_that("resolver fails loudly on a manifest whose run_id disagrees (stale pointer)", {
  # Build a fake run dir named X but whose manifest self-declares Y; the resolver
  # must reject the mismatch rather than trust the directory name.
  tmp <- file.path(tempdir(), "ssot-runid-adversarial")
  fake <- file.path(tmp, "artifacts", "2sfca", "ec2", "e2sfca_faked")
  dir.create(fake, recursive = TRUE, showWarnings = FALSE)
  writeLines('{"run_id": "e2sfca_a_totally_different_run"}',
             file.path(fake, "e2sfca_run_manifest.json"))
  expect_error(e2sfca_run_dir(run_id = "e2sfca_faked", root = tmp),
               "run_id mismatch")
  unlink(tmp, recursive = TRUE)
})

test_that("no code builds an artifact path from a hardcoded run-id literal", {
  # The only legitimate appearance of the literal in code is the canonical
  # constant's Sys.getenv default. Any file.path()/path string that embeds the
  # literal is a duplicate SSOT and must instead derive from E2SFCA_FROZEN_RUN_ID.
  code <- list.files(c(file.path(root, "R"), file.path(root, "scripts")),
                     pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  code <- c(code, file.path(root, "manuscript",
                            "e2sfca_accessibility_manuscript.Rmd"))
  offenders <- character(0)
  for (f in code) {
    lines <- readLines(f, warn = FALSE)
    hit <- grepl(LITERAL, lines, fixed = TRUE) &
      grepl("file.path", lines, fixed = TRUE)
    if (any(hit))
      offenders <- c(offenders, sprintf("%s:%d", basename(f), which(hit)))
  }
  expect_true(length(offenders) == 0,
              info = paste("run-id literal used in path construction:",
                           paste(offenders, collapse = " | ")))
})

test_that("exactly one code line assigns the run-id literal (the canonical constant)", {
  code <- list.files(c(file.path(root, "R"), file.path(root, "scripts")),
                     pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  assigns <- character(0)
  for (f in code) {
    lines <- readLines(f, warn = FALSE)
    # an assignment of the literal: `<name> <- ...<literal>...` (captions use `=`
    # inside plot_annotation and are display strings, not run pointers)
    hit <- grepl(LITERAL, lines, fixed = TRUE) & grepl("<-", lines, fixed = TRUE)
    if (any(hit)) assigns <- c(assigns, basename(f))
  }
  # the sole `<-` assignment of the literal is the canonical constant
  expect_identical(assigns, "manuscript_e2sfca_values.R")
})
