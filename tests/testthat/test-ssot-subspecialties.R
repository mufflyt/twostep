# ==============================================================================
# SSOT guard: the seven-subspecialty analysis code set.
#
# Canonical: E2SFCA_SUBSPECIALTIES in scripts/manuscript_e2sfca_values.R. The set of
# seven codes is repeated in ~15 vectors across the engine, scripts, and the
# manuscript; a drifted MEMBER (a misspelling, a dropped/added subspecialty) would
# silently change which specialties are analysed or labelled. This guard pins the
# canonical set + order and checks every subspecialty code-vector in the repo is
# set-equal to it.
#
# Deliberate variants that are preserved (checked by SET, not order): the seam test
# and some scripts hold the set ALPHABETICALLY (order-agnostic membership lists), and
# scripts/manuscript_catalog/ labels FPMRS as the synonym "URPS". The scan maps
# URPS->FPMRS and ignores order, so those intentional differences pass.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

CANON <- c("MFM", "GO", "REI", "FPMRS", "MIGS", "PAG", "CFP")
UNIVERSE <- c(CANON, "URPS")   # URPS is the manuscript_catalog synonym for FPMRS

test_that("E2SFCA_SUBSPECIALTIES is the 7-code set in manuscript display order", {
  expect_type(E2SFCA_SUBSPECIALTIES, "character")
  expect_length(E2SFCA_SUBSPECIALTIES, 7L)
  expect_false(any(duplicated(E2SFCA_SUBSPECIALTIES)))
  expect_identical(E2SFCA_SUBSPECIALTIES, CANON)   # exact order (factor levels rely on it)
})

test_that("the base-R engine module's DJ7_SUBS agrees with the canonical", {
  source(file.path(root, "R", "desjardins7_e2sfca.R"))
  expect_identical(DJ7_SUBS, E2SFCA_SUBSPECIALTIES)   # same set AND order
})

test_that("the manuscript references the constant, not a literal code vector", {
  rmd <- readLines(file.path(root, "manuscript",
                             "e2sfca_accessibility_manuscript.Rmd"), warn = FALSE)
  # no bare 7-code literal vector should remain in the Rmd
  literal <- grepl('"MFM"', rmd, fixed = TRUE) & grepl('"CFP"', rmd, fixed = TRUE)
  expect_false(any(literal),
               info = paste("literal subspec vector still in Rmd at lines:",
                            paste(which(literal), collapse = ", ")))
  expect_true(any(grepl("E2SFCA_SUBSPECIALTIES", rmd, fixed = TRUE)))
})

test_that("every subspecialty code-vector in the repo is set-equal to the canonical", {
  files <- c(
    list.files(c(file.path(root, "R"), file.path(root, "scripts")),
               pattern = "[.]R$", full.names = TRUE, recursive = TRUE),
    file.path(root, "manuscript", "e2sfca_accessibility_manuscript.Rmd"))
  offenders <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    for (i in seq_along(lines)) {
      blocks <- regmatches(lines[i], gregexpr("c\\([^()]*\\)", lines[i]))[[1]]
      for (b in blocks) {
        toks <- gsub('"', "", regmatches(b, gregexpr('"[A-Za-z]+"', b))[[1]])
        codes <- toks[toks %in% UNIVERSE]
        if (length(unique(codes)) < 4L) next   # not a subspecialty vector
        mapped <- ifelse(codes == "URPS", "FPMRS", codes)
        if (!setequal(unique(mapped), CANON))
          offenders <- c(offenders, sprintf("%s:%d %s", basename(f), i, b))
      }
    }
  }
  expect_true(length(offenders) == 0,
              info = paste("subspec vectors that drift from the canonical set:",
                           paste(offenders, collapse = " | ")))
})
