# =============================================================================
# The exported raster-grid functions that no test had ever called
# =============================================================================
# The other half of the scientific-coverage finding. build_e2sfca_grid_geometry,
# prepare_e2sfca_iso and attach_e2sfca_population are the three functions that
# BUILD the inputs the raster accessibility surface is computed on, and covr
# measured all three at 0% executed lines: the raster suite tested
# compute_e2sfca_raster() against hand-built inputs and never once constructed
# those inputs the way production does.
#
# That gap hid a real defect, fixed alongside these tests:
# attach_e2sfca_population() zero-filled every tract missing from `pop_vals`.
# A tract set and a population table that disagreed therefore produced a
# complete-looking surface with a hole in the demand denominator -- and a hole
# in the denominator INFLATES accessibility, which is the direction that makes a
# study look better than the data supports.
#
# source() rather than library(twostep): the nightly testthat job deliberately
# does NOT install the package, so every suite reaches the code through the
# working tree. A file that relies on an attached package passes under
# devtools::load_all() locally and errors with "could not find function" there.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "two_step_floating_catchment.R"))
source(file.path(.root, "R", "desjardins7_e2sfca.R"))

make_tracts <- function() {
  # Four 0.1-degree square tracts in a row near Denver. Small, exactly known,
  # and large enough at 250 m to contain many cell centres.
  mk <- function(x0, y0) sf::st_polygon(list(cbind(
    c(x0, x0 + 0.1, x0 + 0.1, x0, x0),
    c(y0, y0, y0 + 0.1, y0 + 0.1, y0))))
  sf::st_sf(
    GEOID = c("T1", "T2", "T3", "T4"),
    geometry = sf::st_sfc(mk(-105.0, 39.7), mk(-104.9, 39.7),
                          mk(-105.0, 39.8), mk(-104.9, 39.8), crs = 4326))
}

test_that("build_e2sfca_grid_geometry returns an aligned template and per-tract cell counts", {
  skip_if_not_installed("terra")
  tr <- make_tracts()
  g <- build_e2sfca_grid_geometry(tr, resolution = 1000)

  expect_named(g, c("template", "tracts", "area_crs", "resolution"),
               ignore.order = TRUE)
  expect_equal(g$resolution, 1000)
  expect_s4_class(g$template, "SpatRaster")

  # Reprojected to the equal-area CRS the whole raster path works in. If this
  # silently stayed in 4326, every area weight downstream would be computed in
  # degrees and the allocation would be latitude-biased.
  expect_equal(sf::st_crs(g$tracts), sf::st_crs(g$area_crs))
  # terra shrinks the requested resolution slightly so the cells tile the
  # extent exactly, so this is "the grid is at the requested scale", not an
  # exact equality. A silent order-of-magnitude change would still be caught.
  expect_equal(terra::res(g$template), c(1000, 1000), tolerance = 0.01)

  # Every tract carries a working id and a cell count.
  expect_true(all(c(".tid", ".ncell") %in% names(g$tracts)))
  expect_equal(sort(g$tracts$.tid), seq_len(4))
  expect_equal(nrow(g$tracts), 4L)
  expect_true(all(g$tracts$.ncell > 0))
  expect_type(g$tracts$GEOID, "character")

  # The four tracts are congruent squares, so their cell counts must be within
  # a cell-boundary rounding of each other -- a sanity check that .ncell tracks
  # geometry rather than row order.
  expect_lt(max(g$tracts$.ncell) / min(g$tracts$.ncell), 1.2)
})

test_that("build_e2sfca_grid_geometry honours a supplied template so vintages share cells", {
  skip_if_not_installed("terra")
  tr <- make_tracts()
  g1 <- build_e2sfca_grid_geometry(tr, resolution = 1000)

  # The seam test compares 2010 and 2020 tract sets. If each built its own
  # extent, the two surfaces would live on different grids and any difference
  # between them would be partly an artefact of the cells, not of the tracts.
  # Passing a template must force identical geometry.
  tr_subset <- tr[1:2, ]
  g2 <- build_e2sfca_grid_geometry(tr_subset, resolution = 1000,
                                   template = g1$template)

  # as.vector(): terra::ext objects compare by pointer identity, so comparing
  # them directly would pass for any two distinct extents.
  expect_equal(as.vector(terra::ext(g2$template)), as.vector(terra::ext(g1$template)))
  expect_equal(terra::res(g2$template), terra::res(g1$template))
  expect_equal(dim(g2$template)[1:2], dim(g1$template)[1:2])
  expect_equal(nrow(g2$tracts), 2L)

  # The subset's own extent is strictly smaller, so without the template this
  # would NOT have matched -- which is what makes the assertion meaningful.
  g3 <- build_e2sfca_grid_geometry(tr_subset, resolution = 1000)
  expect_false(isTRUE(all.equal(as.vector(terra::ext(g3$template)),
                                as.vector(terra::ext(g1$template)))))
})

test_that("build_e2sfca_grid_geometry rejects inputs that are not tract geometry", {
  skip_if_not_installed("terra")
  expect_error(build_e2sfca_grid_geometry(data.frame(GEOID = "T1")))
  tr <- make_tracts()
  tr$GEOID <- NULL
  expect_error(build_e2sfca_grid_geometry(tr))
})

test_that("prepare_e2sfca_iso splits isochrones into bands keyed by drive time", {
  tr <- make_tracts()
  iso <- sf::st_sf(
    coord_id = c("39.7_-105.0", "39.7_-105.0", "39.8_-104.9"),
    drive_time_minutes = c(30, 60, 30),
    geometry = sf::st_geometry(tr)[c(1, 2, 3)])

  p <- prepare_e2sfca_iso(iso)
  expect_named(p, c("bands", "area_crs"), ignore.order = TRUE)

  # Bands are named by INTEGER minutes, sorted ascending, and are the keys the
  # weight vector is looked up by downstream. A band named "30.0" or arriving
  # out of order would silently fail to match a weight.
  expect_equal(names(p$bands), c("30", "60"))
  expect_equal(nrow(p$bands[["30"]]), 2L)
  expect_equal(nrow(p$bands[["60"]]), 1L)
  expect_true("coord_id" %in% names(p$bands[["30"]]))
  expect_type(p$bands[["30"]]$coord_id, "character")

  # Reprojected to the equal-area CRS, like the grid.
  expect_equal(sf::st_crs(p$bands[["30"]]), sf::st_crs(p$area_crs))

  # Non-integer drive times round to a band rather than creating a new one.
  iso2 <- iso; iso2$drive_time_minutes <- c(29.6, 60, 30.2)
  p2 <- prepare_e2sfca_iso(iso2)
  expect_equal(names(p2$bands), c("30", "60"))
  expect_equal(nrow(p2$bands[["30"]]), 2L)

  # Empty geometries are dropped, not carried as zero-area catchments.
  iso3 <- iso
  sf::st_geometry(iso3)[2] <- sf::st_sfc(sf::st_polygon(), crs = sf::st_crs(iso3))[[1]]
  p3 <- prepare_e2sfca_iso(iso3)
  expect_false("60" %in% names(p3$bands))

  expect_error(prepare_e2sfca_iso(data.frame(coord_id = "a")))
  bad <- iso; bad$drive_time_minutes <- NULL
  expect_error(prepare_e2sfca_iso(bad))
})

test_that("prepare_e2sfca_iso output feeds compute_e2sfca_raster unchanged", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  # The contract that matters: the two functions were written to compose, and
  # nothing checked that they still do.
  tr <- make_tracts()
  iso <- sf::st_sf(
    coord_id = c("O1", "O1"),
    drive_time_minutes = c(30, 60),
    geometry = sf::st_sfc(sf::st_geometry(tr)[[1]], sf::st_geometry(tr)[[2]],
                          crs = 4326))
  p <- prepare_e2sfca_iso(iso)
  expect_true(is.list(p$bands))
  expect_true(all(vapply(p$bands, inherits, logical(1), "sf")))
  expect_true(all(vapply(p$bands, function(b) "coord_id" %in% names(b), logical(1))))
})

test_that("attach_e2sfca_population conserves population and reports its allocator", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tr <- make_tracts()
  g <- build_e2sfca_grid_geometry(tr, resolution = 1000)
  pop <- data.frame(GEOID = c("T1", "T2", "T3", "T4"),
                    female_pop = c(1000, 2000, 0, 500))

  a <- attach_e2sfca_population(g, pop)
  expect_named(a, c("pop_rast", "tracts", "template", "pop_col", "resolution",
                    "area_crs", "alloc"), ignore.order = TRUE)
  expect_equal(a$alloc, "area")
  expect_equal(a$pop_col, "female_pop")

  # Global conservation: the area allocator must move all 3500 people onto the
  # grid and invent none. This is the guarantee the whole raster path rests on.
  total <- terra::global(a$pop_rast, "sum", na.rm = TRUE)[[1]]
  expect_equal(total, 3500, tolerance = 1e-6)

  # An EXPLICIT zero stays a zero and is not confused with a missing tract.
  expect_equal(a$tracts$.pop[a$tracts$GEOID == "T3"], 0)
  expect_equal(sum(a$tracts$.pop), 3500)
})

test_that("attach_e2sfca_population fails closed on tracts with no population row", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tr <- make_tracts()
  g <- build_e2sfca_grid_geometry(tr, resolution = 1000)

  # THE SECOND DEFECT THIS COVERAGE PASS FOUND. T4 is in the grid and missing
  # from the population table. The old code made it zero people, silently, and
  # the resulting surface looked complete.
  partial <- data.frame(GEOID = c("T1", "T2", "T3"),
                        female_pop = c(1000, 2000, 300))
  expect_error(attach_e2sfca_population(g, partial), "no match in pop_vals")
  expect_error(attach_e2sfca_population(g, partial), "T4")
  # The message must say WHY, not just that something did not match.
  expect_error(attach_e2sfca_population(g, partial), "inflates access")

  # NA is UNKNOWN, and is refused separately from an absent row.
  na_pop <- data.frame(GEOID = c("T1", "T2", "T3", "T4"),
                       female_pop = c(1000, 2000, 300, NA))
  expect_error(attach_e2sfca_population(g, na_pop), "NA in population column")

  # A duplicated GEOID would make the represented population depend on row
  # order, so it is refused rather than resolved.
  dup <- data.frame(GEOID = c("T1", "T1", "T2", "T3", "T4"),
                    female_pop = c(1000, 9999, 2000, 300, 500))
  expect_error(attach_e2sfca_population(g, dup), "duplicated GEOID")

  # The escape hatch still exists, but it must be asked for by name. This is
  # the historical behaviour, now an explicit and documented imputation.
  quiet <- attach_e2sfca_population(g, partial, na_pop_policy = "zero")
  expect_equal(quiet$tracts$.pop[quiet$tracts$GEOID == "T4"], 0)
  expect_equal(sum(quiet$tracts$.pop), 3300)
})

test_that("dj7_incr_weights inverts cumulative band weights without mangling names", {
  # The roxygen block records a real bug: building the vector with named
  # arithmetic produced the label "30.30", so Wi[["30"]] failed to look up. The
  # names are part of the contract because they are the band keys.
  Wc <- c(`30` = 1.00, `60` = 0.68, `120` = 0.22, `180` = 0.09)
  Wi <- dj7_incr_weights(Wc)

  expect_equal(names(Wi), c("30", "60", "120", "180"))
  expect_equal(unname(Wi), c(0.32, 0.46, 0.13, 0.09))
  expect_equal(Wi[["30"]], 0.32)          # the lookup that used to fail
  expect_equal(Wi[["180"]], 0.09)

  # Abel summation: the incremental weights of a NESTED band structure must sum
  # to the outermost cumulative weight, because every ring is counted once.
  expect_equal(sum(Wi), Wc[["30"]])

  # And the recurrence itself: the tail keeps the outermost cumulative weight
  # rather than differencing against an implied zero-beyond band.
  expect_equal(unname(Wi[4]), unname(Wc[4]))

  # Works on the package's own published weight set, not only a synthetic one.
  expect_equal(sum(dj7_incr_weights(DJ7_WC_BASE)), DJ7_WC_BASE[[1]])

  # A degenerate all-equal cumulative vector means all the weight is in the
  # outermost band and every inner increment is zero.
  flat <- dj7_incr_weights(c(`30` = 1, `60` = 1, `120` = 1, `180` = 1))
  expect_equal(unname(flat), c(0, 0, 0, 1))

  # The length is fixed at four bands by the study design, and a vector of any
  # other length is a caller error rather than something to recycle.
  expect_error(dj7_incr_weights(c(1, 0.5, 0.2)))
  expect_error(dj7_incr_weights(c(1, 0.5, 0.2, 0.1, 0.05)))
})
