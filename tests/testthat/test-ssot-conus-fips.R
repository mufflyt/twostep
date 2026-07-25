# ==============================================================================
# SSOT guard: the CONUS state/DC FIPS scope vector.
#
# Canonical: CONUS_STATE_FIPS in scripts/manuscript_e2sfca_values.R = the 48
# contiguous states + DC (49 two-digit FIPS). The `conus()`/`conus_states()` helper
# was copy-pasted identically in 12 analysis scripts; a drifted copy would silently
# add/drop a state from the study scope. Four loader-sourcing scripts are wired to the
# constant; the rest keep an SSOT-anchored literal. This guard pins the canonical set,
# its exclusions, and that every remaining conus literal equals it.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

EXPECTED <- sprintf("%02d", c(1, 4:6, 8:13, 16:42, 44:51, 53:56))

test_that("CONUS_STATE_FIPS is the 48 states + DC (49 codes), no AK/HI/territories", {
  expect_type(CONUS_STATE_FIPS, "character")
  expect_length(CONUS_STATE_FIPS, 49L)
  expect_identical(CONUS_STATE_FIPS, EXPECTED)
  expect_true(all(grepl("^[0-9]{2}$", CONUS_STATE_FIPS)))
  for (ex in c("02", "15", "60", "66", "69", "72", "78"))  # AK, HI, territories
    expect_false(ex %in% CONUS_STATE_FIPS, info = ex)
  expect_true("11" %in% CONUS_STATE_FIPS)                  # DC included
})

test_that("the four wired scripts reference the canonical, not a conus() literal", {
  for (f in c("map_allsubspec_allyears_access_surface.R", "stratify_go_2020_access.R",
              "map_go_2020_access_surface.R", "map_fpmrs_allyears_access_surface.R")) {
    txt <- readLines(file.path(root, "scripts", f), warn = FALSE)
    expect_true(any(grepl("conus <- function() CONUS_STATE_FIPS", txt, fixed = TRUE)),
                info = f)
    expect_false(any(grepl("conus <- function() sprintf", txt, fixed = TRUE)), info = f)
  }
})

test_that("every remaining conus/conus_states literal equals the canonical set", {
  files <- list.files(file.path(root, "scripts"), pattern = "[.]R$",
                      full.names = TRUE, recursive = TRUE)
  bad <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    hits <- grep("conus(_states)? <- function\\(\\) sprintf", lines, value = TRUE)
    for (h in hits) {
      spec <- sub('.*sprintf\\("%02d", *(c\\([^)]*\\))\\).*', "\\1", h)
      fips <- sprintf("%02d", eval(parse(text = spec)))
      if (!setequal(fips, EXPECTED)) bad <- c(bad, sprintf("%s: %s", basename(f), h))
    }
  }
  expect_identical(bad, character(0))
})
