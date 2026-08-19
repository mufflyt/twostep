# ==============================================================================
# SSOT guard: the equal-area CRS used for E2SFCA area math.
#
# Canonical: E2SFCA_AREA_CRS <- 5070L in R/two_step_floating_catchment.R (seam
# validated in scripts/seam_test_2sfca.R). Area/overlap math in the wrong CRS is a
# SILENT error (plausible but wrong areas), so every equal-area transform in the
# E2SFCA path must use the canonical, not a copy.
#
# DELIBERATE second CRS (NOT unified): EPSG:9311 (NAD83(2011) US National Atlas
# Equal Area) is used by the older subspecialty-accessibility / bivariate-ADI modules
# (inst/scripts/calculate_subspecialty_accessibility.R,
# inst/scripts/create_bivariate_map_access_x_adi.R).
# The engine header documents that both 5070 and 9311 are used for equal-area work.
# The drift scan below allows BOTH; it only fails on an unrecognised projected EPSG.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))

engine <- readLines(file.path(root, "R", "two_step_floating_catchment.R"),
                    warn = FALSE)

test_that("E2SFCA_AREA_CRS is defined exactly once, in the engine, as 5070L", {
  defs <- grep("E2SFCA_AREA_CRS\\s*<-", engine, value = TRUE)
  expect_length(defs, 1L)
  expect_match(defs, "5070L")
  # cross-check other files do not re-define the canonical
  other <- list.files(c(file.path(root, "R"), file.path(root, "scripts"),
                        file.path(root, "inst", "scripts")),
                      pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  redefs <- character(0)
  for (f in other) {
    if (normalizePath(f) == normalizePath(file.path(root, "R",
        "two_step_floating_catchment.R"))) next
    if (any(grepl("E2SFCA_AREA_CRS\\s*<-", readLines(f, warn = FALSE))))
      redefs <- c(redefs, basename(f))
  }
  expect_identical(redefs, character(0))
})

test_that("the coverage map references the canonical CRS, not a 5070 literal", {
  f <- readLines(file.path(root, "scripts", "map_2sfca_coverage_by_year.R"),
                 warn = FALSE)
  expect_false(any(grepl("CRS5070\\s*<-\\s*5070L", f)))
  expect_true(any(grepl("CRS5070\\s*<-\\s*E2SFCA_AREA_CRS", f)))
})

test_that("no code uses an unrecognised projected EPSG literal (drift scan)", {
  # Known-good CRSs in this repo: 4326 (WGS84 geographic, leaflet), 3857 (web
  # mercator), 5070 + 9311 (the two deliberate equal-area CRSs). Any other 4-5 digit
  # EPSG in an st_transform()/crs= position is suspicious (typo / foreign CRS).
  ALLOW <- c(4326L, 3857L, 5070L, 9311L)
  # inst/scripts holds the relocated bivariate-ADI module; keep it in the scan so
  # moving it out of R/ did not silently shrink this guard's coverage.
  files <- list.files(c(file.path(root, "R"), file.path(root, "scripts"),
                        file.path(root, "inst", "scripts")),
                      pattern = "[.]R$", full.names = TRUE, recursive = TRUE)
  offenders <- character(0)
  # Three positions: st_transform(x, EPSG), the PIPED st_transform(EPSG), and
  # crs = EPSG.
  #
  # `[^,\n]*` (not `[^,]*`) matters: with `[^,]*` a single match could run from
  # one line's `st_transform(5070)` across the newline to the next line's
  # `st_transform(acs$geom, 5070)`. Combined with the old `gsub("\\D","",m)` --
  # which stripped non-digits from the WHOLE match rather than reading the
  # captured group -- that produced the phantom EPSG "50705070" out of two
  # perfectly legal 5070s. It also meant the first st_transform() on such a pair
  # was never checked at all, so the bug hid real offenders as well as inventing
  # fake ones. Read the capture group, and never let a match cross a line.
  pat <- paste0("(?:st_transform\\([^,\n]*,\\s*|st_transform\\(\\s*|crs\\s*=\\s*)",
                "([0-9]{4,5})L?")
  for (f in files) {
    txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
    m <- regmatches(txt, gregexpr(pat, txt, perl = TRUE))[[1]]
    epsg <- suppressWarnings(as.integer(sub("^.*?([0-9]{4,5})L?$", "\\1", m)))
    bad <- setdiff(unique(epsg[!is.na(epsg)]), ALLOW)
    if (length(bad)) offenders <- c(offenders,
                                    sprintf("%s: %s", basename(f),
                                            paste(bad, collapse = ",")))
  }
  expect_true(length(offenders) == 0,
              info = paste("unrecognised EPSG literals:",
                           paste(offenders, collapse = " | ")))
})
