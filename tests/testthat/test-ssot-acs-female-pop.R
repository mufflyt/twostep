# ==============================================================================
# SSOT guard: the national ACS female-population denominator (2020).
#
# Canonical: E2SFCA_ACS_FEMALE_POP_2020 + e2sfca_acs_female_pop() in
# scripts/manuscript_e2sfca_values.R. This is the denominator that divides national
# coverage into fractions/percentages, so a stale or mistyped copy silently rescales
# every "% of ACS" number. Authority = the frozen run's national summary
# (`acs_pop_source`, 2020). This guard pins the constant to the artifact, checks the
# accessor fails loudly on missing/ambiguous years, and forbids any other hardcoded
# copy of the literal.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

LITERAL <- "164690617"

test_that("E2SFCA_ACS_FEMALE_POP_2020 is a plausible positive integer denominator", {
  expect_true(is.numeric(E2SFCA_ACS_FEMALE_POP_2020))
  expect_length(E2SFCA_ACS_FEMALE_POP_2020, 1L)
  expect_identical(E2SFCA_ACS_FEMALE_POP_2020, 164690617L)
  # a national female-population count must be a large positive integer, not a
  # fraction, per-100k rate, or millions-scaled number
  expect_gt(E2SFCA_ACS_FEMALE_POP_2020, 1e8)
  expect_lt(E2SFCA_ACS_FEMALE_POP_2020, 2.5e8)
  expect_equal(E2SFCA_ACS_FEMALE_POP_2020 %% 1, 0)
})

test_that("the constant is pinned to the frozen artifact (constant == derived)", {
  derived <- e2sfca_acs_female_pop(2020L, run_dir = e2sfca_run_dir(root = root))
  expect_identical(derived, E2SFCA_ACS_FEMALE_POP_2020)
})

test_that("accessor fails loudly for a year absent from the summary", {
  expect_error(
    e2sfca_acs_female_pop(1999L, run_dir = e2sfca_run_dir(root = root)),
    "not a single value")
})

test_that("accessor fails loudly when the year's denominator is not unique", {
  # Adversarial: a summary where 2020 carries two different acs_pop_source values
  # must be rejected, never silently reduced to one.
  tmp <- file.path(tempdir(), "ssot-acs-adversarial")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("subspecialty,year,acs_pop_source",
               "GO,2020,164690617",
               "MFM,2020,999999999"),
             file.path(tmp, "e2sfca_national_summary.csv"))
  expect_error(e2sfca_acs_female_pop(2020L, run_dir = tmp), "not a single value")
  unlink(tmp, recursive = TRUE)
})

test_that("no code file hardcodes the denominator literal except the canonical constant", {
  code <- list.files(c(file.path(root, "R"), file.path(root, "scripts")),
                     pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  # The literal is VENDORED (mufflyaccess is private) and now lives in exactly ONE
  # twostep file: manuscript_e2sfca_values.R defines E2SFCA_ACS_FEMALE_POP_2020.
  # That single canonical home is exempt; no OTHER code file may hardcode it.
  CANONICAL <- "manuscript_e2sfca_values.R"
  offenders <- character(0)
  for (f in code) {
    if (basename(f) == CANONICAL) next
    lines <- readLines(f, warn = FALSE)
    hit <- grepl(LITERAL, lines, fixed = TRUE)
    if (any(hit)) offenders <- c(offenders, basename(f))
  }
  expect_identical(offenders, character(0))
})
