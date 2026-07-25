# ==============================================================================
# SSOT guard: the production E2SFCA raster resolution (metres).
#
# Canonical: E2SFCA_PRODUCTION_RESOLUTION_M <- 500L in
# scripts/manuscript_e2sfca_values.R, pinned to the frozen manifest `resolution_m`.
# The grid resolution sets how demand is rasterised; a production script silently
# built at the wrong resolution would produce a surface that disagrees with the
# frozen run.
#
# DELIBERATE other resolutions (NOT unified): the engine functions default to 250 m
# (a fallback production always overrides); the all-subspecialty DISPLAY
# small-multiples use 1000 m on purpose; the sensitivity sweep uses a res500/1000 m
# pair; tigris cartographic boundaries use "20m" (a map SCALE, unrelated). This guard
# pins only the production value + the wired production scripts.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "scripts", "manuscript_e2sfca_values.R"))

test_that("E2SFCA_PRODUCTION_RESOLUTION_M is a plausible positive metre value", {
  expect_type(E2SFCA_PRODUCTION_RESOLUTION_M, "integer")
  expect_length(E2SFCA_PRODUCTION_RESOLUTION_M, 1L)
  expect_identical(E2SFCA_PRODUCTION_RESOLUTION_M, 500L)
  expect_gt(E2SFCA_PRODUCTION_RESOLUTION_M, 0L)
})

test_that("the constant matches the frozen manifest resolution_m", {
  run_dir <- e2sfca_run_dir(root = root)
  manifest <- jsonlite::read_json(file.path(run_dir, "e2sfca_run_manifest.json"))
  expect_identical(as.integer(manifest$resolution_m), E2SFCA_PRODUCTION_RESOLUTION_M)
})

test_that("load validator rejects a manifest whose resolution_m disagrees", {
  # Adversarial: patch a manifest to 250 m and confirm the loader stops. Copy the
  # frozen run to a temp dir, rewrite resolution_m, point the loader at it.
  run_dir <- e2sfca_run_dir(root = root)
  tmp <- file.path(tempdir(), "ssot-res-adversarial",
                   "artifacts", "2sfca", "ec2", "e2sfca_20260712_190734")
  dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(run_dir, "e2sfca_national_summary.csv"),
            file.path(tmp, "e2sfca_national_summary.csv"), overwrite = TRUE)
  man <- jsonlite::read_json(file.path(run_dir, "e2sfca_run_manifest.json"))
  man$resolution_m <- 250
  jsonlite::write_json(man, file.path(tmp, "e2sfca_run_manifest.json"),
                       auto_unbox = TRUE)
  expect_error(load_e2sfca_national_summary(tmp))   # stopifnot on resolution_m
  unlink(file.path(tempdir(), "ssot-res-adversarial"), recursive = TRUE)
})

test_that("production surface scripts reference the constant, not a 500 literal", {
  for (f in c("map_go_2020_access_surface.R",
              "map_fpmrs_allyears_access_surface.R")) {
    txt <- readLines(file.path(root, "scripts", f), warn = FALSE)
    expect_false(any(grepl("RES\\s*<-\\s*500", txt)),
                 info = paste("500 literal resolution still in", f))
    expect_true(any(grepl("E2SFCA_PRODUCTION_RESOLUTION_M", txt, fixed = TRUE)),
                info = f)
  }
})

test_that("the deliberate non-production resolutions are left intact", {
  # engine default 250 (fallback) still present
  eng <- readLines(file.path(root, "R", "two_step_floating_catchment.R"), warn = FALSE)
  expect_true(any(grepl("resolution = 250", eng, fixed = TRUE)))
  # the 1000 m DISPLAY grid env-default is preserved
  disp <- readLines(file.path(root, "scripts",
                              "map_allsubspec_allyears_access_surface.R"), warn = FALSE)
  expect_true(any(grepl('E2SFCA_MAP_RES", "1000"', disp, fixed = TRUE)))
})
