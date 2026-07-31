# tests/testthat/test-access-language-guard.R
# Guard: accessibility outputs must not be labeled with normative adequacy/shortage
# language (E2SFCA is a modeled supply-to-demand ratio, not a measure of need).
# The accessibility analogue of test-ssot-figure-dashes.R and the no-hardcoded-count
# guard. Scans the Access Explorer's user-facing strings; unit-tests the helper.
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "access_language.R"))

test_that("the helper passes descriptive labels and rejects normative ones", {
  expect_true(assert_access_language("modeled accessibility"))
  expect_true(assert_access_language(c("mean access", "change from baseline")))
  expect_error(assert_access_language("provider shortage in rural areas"), "normative")
  expect_error(assert_access_language("the workforce is adequate"), "normative")
  expect_error(assert_access_language("unmet need for urogynecology"), "normative")
  expect_error(assert_access_language("apparent surplus of providers"), "normative")
})

test_that("case-insensitive and word-boundary aware", {
  expect_error(assert_access_language("SHORTAGE"), "normative")
  # 'surplusage' or 'sufficiency' embedded words should NOT trip a whole-word match
  expect_true(assert_access_language("the sufficiency analysis is separate"))  # 'sufficiency' != 'sufficient'
})

test_that("the Access Explorer app uses no normative adequacy/shortage language", {
  app_dir <- file.path(root, "inst", "shiny", "access_explorer")
  skip_if(!dir.exists(app_dir), "app not present")
  files <- list.files(app_dir, pattern = "\\.(R|md)$", full.names = TRUE)
  offenders <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    hit <- grepl(paste0("\\b(", paste(gsub("([-])", "\\\\\\1", ACCESS_FORBIDDEN_TERMS), collapse = "|"), ")\\b"),
                 lines, ignore.case = TRUE, perl = TRUE)
    # allow the guard's own documentation to name the terms it forbids
    hit <- hit & !grepl("forbidden|do not|never|must not|normative|guard", lines, ignore.case = TRUE)
    if (any(hit)) offenders <- c(offenders, sprintf("%s:%d  %s", basename(f), which(hit)[1], trimws(lines[which(hit)[1]])))
  }
  expect_identical(offenders, character(0),
                   info = paste("normative access language in the app:\n ", paste(offenders, collapse = "\n  ")))
})
