# Guard: NAMESPACE must match the @export tags.
#
# roxygen2 is not in this project's renv library, so `document()` never runs and
# NAMESPACE was maintained by hand. It drifted: DJ7_SUBS / DJ7_BANDS / DJ7_WC_BASE
# carried @export tags that never reached NAMESPACE, so the tags were ignored.
# tools/sync_namespace.R is the stand-in generator; this test fails the suite if
# NAMESPACE and the tags disagree again.
suppressWarnings(suppressMessages(library(testthat)))

root <- tryCatch(here::here(), error = function(e) getwd())

test_that("NAMESPACE is in sync with the @export tags", {
  script <- file.path(root, "tools", "sync_namespace.R")
  expect_true(file.exists(script))

  status <- system2(
    file.path(R.home("bin"), "Rscript"),
    c(shQuote(script), "--check"),
    stdout = FALSE, stderr = FALSE
  )

  expect_identical(
    status, 0L,
    info = "NAMESPACE drifted from the @export tags. Run: Rscript tools/sync_namespace.R"
  )
})

test_that("no @export tag sits in an R/ subdirectory, where R would ignore it", {
  # R collates only top-level R/*.R. An @export under R/utils/ can never take
  # effect, so it must not be written in the first place.
  top <- list.files(file.path(root, "R"), pattern = "\\.(R|r|S|s|q)$", full.names = TRUE)
  all <- list.files(file.path(root, "R"), pattern = "\\.(R|r|S|s|q)$", full.names = TRUE,
                    recursive = TRUE)
  nested <- setdiff(all, top)

  offenders <- Filter(
    function(f) any(grepl("^#'\\s*@export\\b", readLines(f, warn = FALSE))),
    nested
  )

  expect_identical(
    offenders, character(0),
    info = "Move the file to R/ to export it, or mark it @keywords internal."
  )
})
