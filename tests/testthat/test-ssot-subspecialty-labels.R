# ==============================================================================
# SSOT guard: the subspecialty figure/map label map.
#
# Canonical: E2SFCA_SUBSPECIALTY_LABELS in scripts/manuscript_e2sfca_values.R (Title
# Case, abbreviated). Three map scripts previously held byte-identical copies; a
# drifted copy would relabel a figure differently from its siblings. This guard pins
# the canonical map, confirms the three scripts reference it, and forbids en-dash /
# em-dash in ANY subspecialty label map (the equity heatmap carried an en-dash,
# "Maternal–fetal medicine", now fixed — and the user's style rule bans those glyphs).
#
# Deliberate variants preserved (NOT unified): the equity heatmap keeps a
# SENTENCE-case rendering (a mechanical transform would corrupt the FPMRS acronym);
# the manuscript Rmd keeps FULL lowercase formal names for inline prose.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

EN_EM <- "–|—"   # en-dash or em-dash

test_that("E2SFCA_SUBSPECIALTY_LABELS is a complete keyed label map", {
  expect_type(E2SFCA_SUBSPECIALTY_LABELS, "character")
  expect_length(E2SFCA_SUBSPECIALTY_LABELS, 7L)
  expect_false(any(is.na(E2SFCA_SUBSPECIALTY_LABELS)))
  expect_true(all(nzchar(E2SFCA_SUBSPECIALTY_LABELS)))
  # keyed by exactly the canonical subspecialty code set
  expect_setequal(names(E2SFCA_SUBSPECIALTY_LABELS), E2SFCA_SUBSPECIALTIES)
})

test_that("canonical label values are the expected Title-Case abbreviated strings", {
  expect_identical(E2SFCA_SUBSPECIALTY_LABELS[["MFM"]], "Maternal-Fetal Medicine")
  expect_identical(E2SFCA_SUBSPECIALTY_LABELS[["GO"]], "Gynecologic Oncology")
  expect_identical(E2SFCA_SUBSPECIALTY_LABELS[["FPMRS"]], "Urogynecology (FPMRS)")
})

test_that("canonical labels contain no en-dash or em-dash", {
  expect_false(any(grepl(EN_EM, E2SFCA_SUBSPECIALTY_LABELS)))
})

test_that("the three map scripts reference the canonical map, not a literal", {
  for (f in c("map_2sfca_coverage_by_year.R",
              "map_allsubspec_allyears_access_surface.R",
              "map_fpmrs_allyears_access_surface.R")) {
    txt <- readLines(file.path(root, "scripts", f), warn = FALSE)
    expect_false(any(grepl("full_name\\s*<-\\s*c\\(", txt)),
                 info = paste("literal full_name map still present in", f))
    expect_true(any(grepl("E2SFCA_SUBSPECIALTY_LABELS", txt, fixed = TRUE)),
                info = paste(f, "does not reference the canonical label map"))
  }
})

test_that("no subspecialty label map anywhere contains an en-dash or em-dash", {
  files <- c(
    list.files(c(file.path(root, "R"), file.path(root, "scripts")),
               pattern = "[.]R$", full.names = TRUE, recursive = TRUE),
    file.path(root, "manuscript", "e2sfca_accessibility_manuscript.Rmd"))
  offenders <- character(0)
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    # a full_name <- c(...) block, allowing one level of nested parens like "(FPMRS)"
    blocks <- regmatches(
      txt, gregexpr("full_name\\s*<-\\s*c\\((?:[^()]|\\([^()]*\\))*\\)",
                    txt, perl = TRUE))[[1]]
    for (b in blocks) if (grepl(EN_EM, b)) offenders <- c(offenders, basename(f))
  }
  expect_true(length(offenders) == 0,
              info = paste("subspecialty label maps with en/em dash:",
                           paste(offenders, collapse = ", ")))
})
