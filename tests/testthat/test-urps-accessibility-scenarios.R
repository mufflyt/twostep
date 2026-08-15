# Orchestration-layer tests for the URPS workforce-projection accessibility
# wiring. These exercise the deterministic supply chain
#   projection -> per-state allocation -> per-origin supply -> injected engine
# with NO geospatial stack: base R + mufflyaccess only, a stub accessibility_fn
# standing in for compute_e2sfca(). The projection fixture is mufflyaccess's
# bundled, contract-valid example, so the test needs no cliff artifact on disk.

# This file never sourced the module it tests, so all 7 of its test_that blocks
# errored with "could not find function urps_project_accessibility" and the URPS
# orchestration layer was effectively untested. Same rprojroot idiom the other
# SSOT tests use.
root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
source(file.path(root, "R", "urps_accessibility_scenarios.R"))

skip_if_not_installed("mufflyaccess")

proj_path <- system.file("extdata", "urps_projection_example.csv", package = "mufflyaccess")
skip_if(!nzchar(proj_path) || !file.exists(proj_path),
        "bundled projection example not available")

proj  <- mufflyaccess::read_urps_projection(proj_path, validate = TRUE)
years <- sort(unique(proj$year))
y1    <- years[1]

nat_headcount <- function(scen, yr, col = "supply_headcount") {
  r <- proj[proj$scenario_id == scen & proj$year == yr & proj$geography_type == "national", ]
  r[[col]][1]
}

test_that("urps_scenario_supply allocates the national total across CONUS, mass-conserving", {
  s <- urps_scenario_supply(proj, "baseline", y1)
  expect_true(all(c("scenario_id", "year", "basis", "state_abbr", "state_fips",
                    "supply", "national_supply") %in% names(s)))
  expect_gt(nrow(s), 40)                                   # ~49 CONUS states + DC
  expect_equal(s$national_supply[1], nat_headcount("baseline", y1))
  # allocation conserves the rounded national total
  expect_equal(sum(s$supply), as.integer(round(nat_headcount("baseline", y1))))
  expect_true(all(s$supply >= 0))
})

test_that("urps_scenario_supply validates the scenario id and the year", {
  expect_error(urps_scenario_supply(proj, "not_a_scenario", y1),
               "not_a_scenario|registered|scenario")
  expect_error(urps_scenario_supply(proj, "baseline", 1800L),
               "no projection row")
  expect_error(urps_scenario_supply(proj, c("baseline", "baseline"), y1),
               "single string")
})

test_that("a scenario-year with no supply on the requested basis fails loud", {
  # the bundled example populates headcount only; clinical_fte is NA there
  expect_error(urps_scenario_supply(proj, "baseline", y1, basis = "clinical_fte"),
               "no usable clinical_fte supply|does not populate")
})

test_that("clinical_fte basis allocates the FTE total when the projection populates it", {
  cliff <- "/workspace/cliff/scripts/urps_projection/urps_projection_2023_2040_v1.csv"
  skip_if(!file.exists(cliff), "cliff projection artifact not available in this checkout")
  cp <- mufflyaccess::read_urps_projection(cliff, validate = TRUE)
  fte <- cp$supply_clinical_fte[cp$scenario_id == "baseline" & cp$year == 2023 &
                                cp$geography_type == "national"][1]
  s <- urps_scenario_supply(cp, "baseline", 2023L, basis = "clinical_fte")
  expect_equal(s$national_supply[1], fte)
  expect_equal(sum(s$supply), as.integer(round(fte)))
  # FTE (<= headcount) allocates fewer providers than the headcount basis
  sh <- urps_scenario_supply(cp, "baseline", 2023L, basis = "headcount")
  expect_lte(sum(s$supply), sum(sh$supply))
})

test_that("urps_allocate_origins scales baseline origins within state to the scenario total", {
  state_supply <- data.frame(
    state_abbr = c("AA", "BB"),
    state_fips = c("01", "02"),
    supply     = c(4L, 6L),
    stringsAsFactors = FALSE)
  baseline <- data.frame(
    coord_id   = c("a1", "a2", "b1"),
    state_abbr = c("AA", "AA", "BB"),
    supply     = c(1, 1, 1),           # AA baseline total = 2, BB = 1
    stringsAsFactors = FALSE)

  o <- urps_allocate_origins(state_supply, baseline)
  expect_identical(names(o), c("coord_id", "supply"))     # exact engine contract
  expect_true(all(o$supply > 0))
  # AA: target 4 / baseline 2 => x2  ; BB: target 6 / baseline 1 => x6
  expect_equal(o$supply[o$coord_id == "a1"], 2)
  expect_equal(o$supply[o$coord_id == "b1"], 6)
  # per-state sums equal the scenario targets
  aa <- sum(o$supply[o$coord_id %in% c("a1", "a2")])
  expect_equal(aa, 4)
})

test_that("urps_allocate_origins warns + records states it cannot place providers into", {
  state_supply <- data.frame(state_abbr = c("AA", "CC"), supply = c(2L, 3L),
                             stringsAsFactors = FALSE)
  baseline <- data.frame(coord_id = c("a1", "a2"), state_abbr = c("AA", "AA"),
                         supply = c(1, 1), stringsAsFactors = FALSE)
  expect_warning(o <- urps_allocate_origins(state_supply, baseline),
                 "no baseline provider origin|unplaced")
  expect_equal(as.integer(attr(o, "unplaceable")[["CC"]]), 3L)
  expect_true(all(o$coord_id %in% c("a1", "a2")))          # only placeable state present
})

test_that("urps_project_accessibility runs the grid, keys on scenario_id + year, ties to supply", {
  # stub engine: report the total provider supply handed to it
  stub <- function(supply, scenario_id, year, ...)
    data.frame(metric = "total_supply", value = sum(supply$supply),
               stringsAsFactors = FALSE)

  scen2 <- head(sort(unique(proj$scenario_id)), 2)
  res <- urps_project_accessibility(proj, stub, scenarios = scen2)

  expect_true(all(c("scenario_id", "year", "metric", "value") %in% names(res)))
  expect_equal(nrow(res), length(scen2) * length(years))
  expect_setequal(unique(res$scenario_id), scen2)
  # in state mode the stub sums the allocation, which equals the rounded national total
  chk <- res[res$scenario_id == "baseline" & res$year == y1, ]
  expect_equal(chk$value, as.integer(round(nat_headcount("baseline", y1))))
})

test_that("urps_project_accessibility validates every requested scenario before compute", {
  stub <- function(supply, scenario_id, year, ...)
    data.frame(value = sum(supply$supply))
  expect_error(
    urps_project_accessibility(proj, stub, scenarios = c("baseline", "bogus_scenario")),
    "bogus_scenario|registered|scenario")
})
