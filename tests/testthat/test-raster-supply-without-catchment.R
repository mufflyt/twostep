# =============================================================================
# A provider with SUPPLY but no CATCHMENT must not vanish silently
# =============================================================================
# Found by attempting to reproduce the frozen run from its own recorded supply
# table. The national mean came out 0.786% BELOW the published value, and the
# engine reported success. The cause: 5 of 516 origins carried 7 of 890 supply
# units (0.787%) and had no isochrone in the local artifacts. Every band in
# compute_e2sfca_raster subsets isochrones to origins with supply, so an origin
# with supply and no isochrone is filtered out at every step -- contributing no
# demand, receiving no ratio, reaching no cell.
#
# The arithmetic matched to three decimal places, which is what makes this
# dangerous: the surface looks complete and every number is quietly too low.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "two_step_floating_catchment.R"))

mk <- function(x0, y0, d = 0.1) sf::st_polygon(list(cbind(
  c(x0, x0 + d, x0 + d, x0, x0), c(y0, y0, y0 + d, y0 + d, y0))))

fixture <- function() {
  tr <- sf::st_sf(GEOID = c("T1", "T2"),
                  geometry = sf::st_sfc(mk(-105, 39.7), mk(-104.9, 39.7), crs = 4326))
  tr$female_pop <- c(1000, 2000)
  g <- build_e2sfca_raster_grid(tr, "female_pop", resolution = 1000)
  iso <- sf::st_sf(coord_id = c("P1", "P1"), drive_time_minutes = c(30, 60),
                   geometry = sf::st_sfc(sf::st_geometry(tr)[[1]], sf::st_geometry(tr)[[1]],
                                         crs = 4326))
  list(grid = g, iso = prepare_e2sfca_iso(iso),
       W = c(`30` = 1, `60` = 0.68, `120` = 0.22, `180` = 0.09))
}

test_that("supply with no isochrone FAILS CLOSED and names the origins", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  f <- fixture()
  # P2 has supply but appears in no band -- the exact shape of the real defect.
  sup <- data.frame(coord_id = c("P1", "P2"), supply = c(4, 6))
  expect_error(compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W),
               "no match in isochrone bands")
  expect_error(compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W), "P2")
})

test_that("the error quantifies how much supply would have vanished", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  f <- fixture()
  sup <- data.frame(coord_id = c("P1", "P2"), supply = c(4, 6))
  # 6 of 10 supply units = 60%. Reporting the SHARE is what makes the failure
  # actionable: 0.787% reads as a rounding artefact until it is named.
  expect_error(compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W), "60\\.000%")
  expect_error(compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W), "6 of 10 supply")
})

test_that("the loss can be accepted, but only by declaring it", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  f <- fixture()
  sup <- data.frame(coord_id = c("P1", "P2"), supply = c(4, 6))
  expect_warning(
    r <- compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W,
                               unmatched_supply_policy = "drop"),
    "no isochrone and are dropped")
  # It proceeds, and the surface reflects only the origin that has a catchment.
  expect_true(is.list(r))
})

test_that("a complete supply/isochrone pairing is unaffected", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  f <- fixture()
  sup <- data.frame(coord_id = "P1", supply = 4)
  expect_silent(compute_e2sfca_raster(f$grid, f$iso, sup, weights = f$W))
})

test_that("the guard does not fire on the reverse case", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  # An isochrone with no supply is a DIFFERENT situation and is legitimate:
  # catchments are computed for many origins and only some carry supply in a
  # given subspecialty-year. That direction must stay quiet.
  tr <- sf::st_sf(GEOID = c("T1", "T2"),
                  geometry = sf::st_sfc(mk(-105, 39.7), mk(-104.9, 39.7), crs = 4326))
  tr$female_pop <- c(1000, 2000)
  g <- build_e2sfca_raster_grid(tr, "female_pop", resolution = 1000)
  iso <- sf::st_sf(coord_id = c("P1", "P1", "P9", "P9"),
                   drive_time_minutes = c(30, 60, 30, 60),
                   geometry = sf::st_sfc(sf::st_geometry(tr)[[1]], sf::st_geometry(tr)[[1]],
                                         sf::st_geometry(tr)[[2]], sf::st_geometry(tr)[[2]],
                                         crs = 4326))
  expect_silent(compute_e2sfca_raster(g, prepare_e2sfca_iso(iso),
                                      data.frame(coord_id = "P1", supply = 4),
                                      weights = c(`30` = 1, `60` = 0.68, `120` = 0.22, `180` = 0.09)))
})
