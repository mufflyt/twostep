# Tests for the Enhanced 2SFCA module (R/two_step_floating_catchment.R).
# The E2SFCA cases below are hand-computed so a regression in the math is caught
# against known-correct values, not just internal consistency.

suppressWarnings({
  library(testthat)
  library(sf)
})

source(testthat::test_path("..", "..", "R", "two_step_floating_catchment.R"))

# --- helpers ------------------------------------------------------------------
# Axis-aligned rectangle [xmin,xmax] x [ymin,ymax] as an sf polygon in EPSG:5070.
.rect <- function(xmin, xmax, ymin, ymax) {
  sf::st_polygon(list(rbind(
    c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
  )))
}

# ==============================================================================
# Weights
# ==============================================================================
test_that("incremental weights are the successive differences of cumulative weights", {
  inc <- e2sfca_incremental_weights(c("30" = 1.00, "60" = 0.68, "120" = 0.22, "180" = 0.09))
  expect_equal(unname(inc["30"]),  0.32, tolerance = 1e-12)
  expect_equal(unname(inc["60"]),  0.46, tolerance = 1e-12)
  expect_equal(unname(inc["120"]), 0.13, tolerance = 1e-12)
  expect_equal(unname(inc["180"]), 0.09, tolerance = 1e-12)   # outermost = own weight
  # Incremental weights must sum to the innermost cumulative weight.
  expect_equal(sum(inc), 1.00, tolerance = 1e-12)
})

test_that("non-monotone (increasing) weights are rejected", {
  expect_error(e2sfca_band_weights(c("30" = 0.5, "60" = 0.9)), "monotone")
})

test_that("unparseable band names are rejected", {
  expect_error(e2sfca_band_weights(c("near" = 1.0, "far" = 0.5)), "band-in-minutes")
})

# ==============================================================================
# Overlap fractions
# ==============================================================================
test_that("overlap_fraction is 1 for a fully-covered tract and 0.5 for half-covered", {
  tracts <- sf::st_sf(
    GEOID = c("T1", "T2"),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(10, 20, 0, 10), crs = 5070)
  )
  iso <- sf::st_sf(
    coord_id = c("A", "A"),
    drive_time_minutes = c(30L, 60L),
    geometry = sf::st_sfc(
      .rect(0, 10, 0, 10),   # 30-min: covers T1 fully
      .rect(0, 15, 0, 10),   # 60-min: T1 full + left half of T2
      crs = 5070
    )
  )
  ov <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  f <- function(cid, b, g) ov$overlap_fraction[ov$coord_id == cid & ov$band == b & ov$GEOID == g]
  expect_equal(f("A", 30L, "T1"), 1.0, tolerance = 1e-9)
  expect_equal(f("A", 60L, "T1"), 1.0, tolerance = 1e-9)
  expect_equal(f("A", 60L, "T2"), 0.5, tolerance = 1e-9)
  # 30-min band does not reach T2 → no row.
  expect_length(f("A", 30L, "T2"), 0)
})

# ==============================================================================
# Supply
# ==============================================================================
test_that("supply counts distinct active NPIs per origin, dropping placeholder rows", {
  ycm <- dplyr::tibble(
    npi           = c("1", "2", "3", "4", "2"),
    analysis_year = c(2018L, 2018L, 2018L, 2018L, 2019L),
    coord_id      = c("A", "A", "B", "A", "A"),
    match_source  = c("spatial", "spatial", "spatial", NA, "spatial")  # row 4 placeholder
  )
  cohort <- dplyr::tibble(
    npi = c("1", "2", "3", "4"),
    subspecialty_normalized = c("GO", "GO", "GO", "MFM")
  )
  s <- compute_provider_supply(ycm, cohort, "GO", 2018L)
  expect_setequal(s$coord_id, c("A", "B"))
  expect_equal(s$supply[s$coord_id == "A"], 2L)  # NPIs 1 & 2 (npi 4 is MFM + placeholder)
  expect_equal(s$supply[s$coord_id == "B"], 1L)  # NPI 3
})

# ==============================================================================
# Full E2SFCA against a hand-computed two-provider / two-tract / two-band world
# ==============================================================================
test_that("compute_e2sfca reproduces the hand-computed ratios and access", {
  # Geometry: T1=[0,10]x[0,10], T2=[10,20]x[0,10].
  tracts <- sf::st_sf(
    GEOID = c("T1", "T2"),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(10, 20, 0, 10), crs = 5070)
  )
  # Provider A: 30-min covers T1; 60-min covers T1 + half of T2.
  # Provider B: 30- and 60-min both cover T2 only.
  iso <- sf::st_sf(
    coord_id = c("A", "A", "B", "B"),
    drive_time_minutes = c(30L, 60L, 30L, 60L),
    geometry = sf::st_sfc(
      .rect(0, 10, 0, 10),
      .rect(0, 15, 0, 10),
      .rect(10, 20, 0, 10),
      .rect(10, 20, 0, 10),
      crs = 5070
    )
  )
  overlap  <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  tractpop <- dplyr::tibble(GEOID = c("T1", "T2"), female_pop = c(100, 200))
  supply   <- dplyr::tibble(coord_id = c("A", "B"), supply = c(3L, 1L))
  weights  <- c("30" = 1.0, "60" = 0.5)   # incremental: w'_30 = 0.5, w'_60 = 0.5

  res <- compute_e2sfca(overlap, tractpop, supply, weights = weights,
                        pop_col = "female_pop", per_capita_scale = 1)

  # --- Step 1: provider-to-population ratios ---
  #   demand_A = 0.5*1*100 (30,T1) + 0.5*1*100 (60,T1) + 0.5*0.5*200 (60,T2) = 150
  #   R_A = 3/150 = 0.02
  #   demand_B = 0.5*1*200 (30,T2) + 0.5*1*200 (60,T2) = 200 ; R_B = 1/200 = 0.005
  rA <- res$provider_ratios$ratio[res$provider_ratios$coord_id == "A"]
  rB <- res$provider_ratios$ratio[res$provider_ratios$coord_id == "B"]
  expect_equal(res$provider_ratios$weighted_demand[res$provider_ratios$coord_id == "A"], 150, tolerance = 1e-9)
  expect_equal(res$provider_ratios$weighted_demand[res$provider_ratios$coord_id == "B"], 200, tolerance = 1e-9)
  expect_equal(rA, 0.02,  tolerance = 1e-9)
  expect_equal(rB, 0.005, tolerance = 1e-9)

  # --- Step 2: tract accessibility ---
  #   A_T1 = 0.5*R_A + 0.5*R_A                       = 0.02
  #   A_T2 = 0.25*R_A + 0.5*R_B + 0.5*R_B            = 0.005 + 0.005 = 0.01
  aT1 <- res$access$access[res$access$GEOID == "T1"]
  aT2 <- res$access$access[res$access$GEOID == "T2"]
  expect_equal(aT1, 0.02, tolerance = 1e-9)
  expect_equal(aT2, 0.01, tolerance = 1e-9)
  expect_equal(res$access$n_providers[res$access$GEOID == "T1"], 1L)
  expect_equal(res$access$n_providers[res$access$GEOID == "T2"], 2L)
})

test_that("ring-based and cumulative-band E2SFCA agree (Abel-summation identity)", {
  # Independent ring-based reference computation vs the module's cumulative math.
  tracts <- sf::st_sf(
    GEOID = c("T1", "T2"),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(10, 20, 0, 10), crs = 5070)
  )
  iso <- sf::st_sf(
    coord_id = c("A", "A"),
    drive_time_minutes = c(30L, 60L),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(0, 20, 0, 10), crs = 5070)
  )
  overlap  <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  tractpop <- dplyr::tibble(GEOID = c("T1", "T2"), female_pop = c(100, 200))
  supply   <- dplyr::tibble(coord_id = "A", supply = 4L)
  W <- c("30" = 1.0, "60" = 0.4)

  mod <- compute_e2sfca(overlap, tractpop, supply, weights = W,
                        pop_col = "female_pop", per_capita_scale = 1)

  # Ring reference: ring30 = 30-min poly; ring60 = 60-min minus 30-min.
  #   T1 fully in ring30 (frac 1, ring60 0); T2 fully in ring60 (frac 1, ring30 0).
  #   demand = W30*(100*1) + W60*(200*1) = 1.0*100 + 0.4*200 = 180 ; R = 4/180
  R_ref <- 4 / 180
  #   A_T1 = W30 * R (T1 only in ring30) ; A_T2 = W60 * R
  aT1_ref <- 1.0 * R_ref
  aT2_ref <- 0.4 * R_ref
  expect_equal(mod$access$access[mod$access$GEOID == "T1"], aT1_ref, tolerance = 1e-9)
  expect_equal(mod$access$access[mod$access$GEOID == "T2"], aT2_ref, tolerance = 1e-9)
})

test_that("raster engine reproduces the exact vector E2SFCA result", {
  skip_if_not_installed("terra")
  skip_if_not_installed("exactextractr")
  tracts <- sf::st_sf(
    GEOID = c("T1", "T2"), female_pop = c(100, 200),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(10, 20, 0, 10), crs = 5070)
  )
  iso <- sf::st_sf(
    coord_id = c("A", "A", "B", "B"),
    drive_time_minutes = c(30L, 60L, 30L, 60L),
    geometry = sf::st_sfc(.rect(0, 10, 0, 10), .rect(0, 15, 0, 10),
                          .rect(10, 20, 0, 10), .rect(10, 20, 0, 10), crs = 5070)
  )
  supply  <- dplyr::tibble(coord_id = c("A", "B"), supply = c(3L, 1L))
  W       <- c("30" = 1.0, "60" = 0.5)

  ov  <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  vec <- compute_e2sfca(ov, dplyr::tibble(GEOID = c("T1", "T2"), female_pop = c(100, 200)),
                        supply, weights = W, per_capita_scale = 1)
  grid <- build_e2sfca_raster_grid(tracts, "female_pop", resolution = 0.05)
  ras  <- compute_e2sfca_raster(grid, iso, supply, weights = W, per_capita_scale = 1)

  key <- function(df, id, val) df[[val]][order(df[[id]])]
  expect_equal(key(ras$provider_ratios, "coord_id", "ratio"),
               key(vec$provider_ratios, "coord_id", "ratio"), tolerance = 1e-6)
  # The vector engine's `access` is area-weighted -> compare to access_mean_area.
  expect_equal(key(ras$access, "GEOID", "access_mean_area"),
               key(vec$access, "GEOID", "access"), tolerance = 1e-6)
})

test_that("a provider with zero weighted demand yields ratio NA (undefined), surface 0, audited", {
  overlap <- dplyr::tibble(
    coord_id = "A", band = 30L, GEOID = "T1", overlap_fraction = 1
  )
  tractpop <- dplyr::tibble(GEOID = "T1", female_pop = 0)   # nobody to serve
  supply   <- dplyr::tibble(coord_id = "A", supply = 5L)
  res <- compute_e2sfca(overlap, tractpop, supply, weights = c("30" = 1.0),
                        pop_col = "female_pop", per_capita_scale = 1)
  # ratio = supply / weighted_demand is UNDEFINED when demand == 0 -> NA, not 0
  # (0 would read as "zero capacity"); the surface contribution is 0 and the
  # excluded supply is audited.
  expect_true(is.na(res$provider_ratios$ratio))
  expect_equal(res$provider_ratios$ratio_for_surface, 0)
  expect_true(res$provider_ratios$zero_demand)
  expect_equal(res$provider_ratios$excluded_supply, 5L)
  expect_equal(res$audit$n_zero_demand_origins, 1L)
  expect_equal(res$audit$supply_zero_demand, 5L)
  expect_true(all(is.finite(res$access$access)))
})

# ==============================================================================
# Population-weighted headline / cell-level summaries (fixes #1-#2, mask #3)
# These guard the partition-invariance and threshold-robustness properties the
# PI review required before any national relaunch.
# ==============================================================================

# Small helper: build a terra raster from a numeric matrix on a unit grid.
.mk_rast <- function(mat) {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = nrow(mat), ncols = ncol(mat),
                   xmin = 0, xmax = ncol(mat), ymin = 0, ymax = nrow(mat),
                   crs = "EPSG:5070")
  terra::values(r) <- as.vector(t(mat))   # row-major fill
  r
}

test_that("geometry mismatch between surface and pop_rast is rejected", {
  skip_if_not_installed("terra")
  s <- .mk_rast(matrix(c(1, 2, 3, 4), 2, 2))
  p_bad <- terra::rast(nrows = 2, ncols = 3, xmin = 0, xmax = 3, ymin = 0, ymax = 2,
                       crs = "EPSG:5070"); terra::values(p_bad) <- 1
  expect_error(e2sfca_cell_summaries(s, p_bad), "share")
})

test_that("area-weighted and population-weighted tract means differ under uneven population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  # Two cells: access 0 and 10; population 1 and 9 (uneven).
  s <- .mk_rast(matrix(c(0, 10), nrow = 1))
  p <- .mk_rast(matrix(c(1, 9),  nrow = 1))
  tract <- sf::st_sf(GEOID = "T", geometry = sf::st_sfc(.rect(0, 2, 0, 1), crs = 5070))
  area_mean <- exactextractr::exact_extract(s, tract, "mean")
  pop_mean  <- exactextractr::exact_extract(s, tract, "weighted_mean", weights = p)
  expect_equal(area_mean, 5, tolerance = 1e-9)     # (0+10)/2
  expect_equal(pop_mean, 9,  tolerance = 1e-9)     # (1*0 + 9*10)/10
  expect_false(isTRUE(all.equal(area_mean, pop_mean)))
})

test_that("cell-level threshold share differs from thresholding the tract mean", {
  skip_if_not_installed("terra")
  # Tract mean access = 9 (half pop at 3, half at 15); threshold k = 10.
  s <- .mk_rast(matrix(c(3, 15), nrow = 1))
  p <- .mk_rast(matrix(c(1, 1),  nrow = 1))
  summ <- e2sfca_cell_summaries(s, p, thresholds = 10, scale = 1)
  # Cell-level share >= 10 is 0.5 (one of two equal-pop cells).
  expect_equal(summ$threshold_shares$share_pop, 0.5, tolerance = 1e-9)
  # Thresholding the tract mean (pop-wt mean = 9 < 10) would call it 0.0 — differs.
  tract_mean <- summ$mean_population_weighted        # = 9
  expect_equal(tract_mean, 9, tolerance = 1e-9)
  expect_false(isTRUE(all.equal(as.numeric(tract_mean >= 10), 0.5)))
})

test_that("direct cell national mean == pop-weighted tract recombination (same pop_rast)", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  s <- .mk_rast(matrix(c(0, 10, 4, 8), 2, 2))
  p <- .mk_rast(matrix(c(1,  9, 5, 5), 2, 2))
  # Two tracts split the 2x2 grid into the top row and the bottom row.
  tracts <- sf::st_sf(GEOID = c("A", "B"),
    geometry = sf::st_sfc(.rect(0, 2, 1, 2), .rect(0, 2, 0, 1), crs = 5070))
  summ <- e2sfca_cell_summaries(s, p, thresholds = numeric(0), scale = 1)
  a_pop <- exactextractr::exact_extract(s, tracts, "weighted_mean", weights = p)
  p_tot <- exactextractr::exact_extract(p, tracts, "sum")     # tract pop FROM pop_rast
  recomb <- sum(a_pop * p_tot) / sum(p_tot)
  # Strict tolerance; residual is exact_extract coverage-fraction float precision
  # (the direct cell mean is exact, the recombination carries boundary rounding).
  expect_equal(summ$mean_population_weighted, recomb, tolerance = 1e-6)
})

test_that("mask accounts for NA access and negative/zero population without shifting denominator", {
  skip_if_not_installed("terra")
  s <- .mk_rast(matrix(c(5, NA, 8, 2), 2, 2))    # one missing-access cell
  p <- .mk_rast(matrix(c(10, 7, 0, -3), 2, 2))   # zero-pop + a negative (invalid) cell
  summ <- e2sfca_cell_summaries(s, p, thresholds = 0, scale = 1)
  # Valid = finite access & finite non-negative pop:
  #   cell1 (5,10) valid; cell2 (NA,7) invalid-access; cell3 (8,0) valid; cell4 (2,-3) invalid-pop
  expect_equal(summ$n_cells_valid, 2)
  expect_equal(summ$pop_valid_total, 10)                       # 10 + 0
  expect_equal(summ$pop_excluded_missing_access, 7)            # pop at the NA-access cell
  # Real population on the grid excludes the negative cell entirely.
  expect_equal(summ$pop_raster_total, 17)                      # 10 + 7 + 0
  # National mean uses ONLY valid cells: (10*5 + 0*8)/10 = 5.
  expect_equal(summ$mean_population_weighted, 5, tolerance = 1e-9)
})

test_that("zero-total-weight polygon yields NA pop-weighted mean, not a crash", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  s <- .mk_rast(matrix(c(1, 2, 3, 4), 2, 2))
  p <- .mk_rast(matrix(0, 2, 2))                 # zero population everywhere
  tract <- sf::st_sf(GEOID = "T", geometry = sf::st_sfc(.rect(0, 2, 0, 2), crs = 5070))
  pw <- exactextractr::exact_extract(s, tract, "weighted_mean", weights = p)
  expect_true(is.na(pw) || is.nan(pw))
  summ <- e2sfca_cell_summaries(s, p, thresholds = 1, scale = 1)
  expect_true(is.na(summ$mean_population_weighted))
})

# ==============================================================================
# Mass-conserving tract-to-grid allocation (allocate_pop_areaweighted)
# ==============================================================================
# A 4x4 km template of 1 km cells in the equal-area CRS. Cell index is row-major
# (top-left = 1), so a polygon's cell membership is deterministic.
.tmpl_km <- function(n = 4, res = 1000) {
  r <- terra::rast(xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
                   resolution = res, crs = "EPSG:5070")
  terra::values(r) <- NA_real_
  r
}
.sfp <- function(..., geoid) {
  polys <- list(...)
  sf::st_sf(GEOID = geoid, geometry = sf::st_sfc(polys, crs = 5070))
}

test_that("a polygon smaller than one raster cell retains all its population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  # 100x100 m tract tucked in a corner of the bottom-left cell — its centroid is
  # nowhere near any cell centre, so center-based rasterization would drop it.
  tr <- .sfp(.rect(20, 120, 20, 120), geoid = "S")
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = 777)
  expect_equal(terra::global(pr, "sum")[[1]], 777, tolerance = 1e-6)
  # all of it lands in exactly one cell (the bottom-left)
  v <- terra::values(pr)[, 1]; v <- v[v > 0]
  expect_length(v, 1L)
  expect_equal(v[[1]], 777, tolerance = 1e-6)
})

test_that("a polygon crossing several cells retains all its population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  tr <- .sfp(.rect(500, 3500, 500, 1500), geoid = "M")   # spans 3 cols x 2 rows
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = 6000)
  expect_equal(terra::global(pr, "sum")[[1]], 6000, tolerance = 1e-6)
  expect_gt(sum(terra::values(pr)[, 1] > 0), 1L)          # genuinely split
})

test_that("multiple tracts contributing to one cell sum correctly", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  # Two disjoint tracts, each half of the top-left cell -> both feed cell 1.
  a <- .rect(0, 500, 3000, 4000)     # left half of TL cell
  b <- .rect(500, 1000, 3000, 4000)  # right half of TL cell
  tr <- .sfp(a, b, geoid = c("A", "B"))
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = c(300, 700))
  v <- terra::values(pr)[, 1]
  expect_equal(v[1], 1000, tolerance = 1e-6)              # cell 1 = TL
  expect_equal(terra::global(pr, "sum")[[1]], 1000, tolerance = 1e-6)
})

test_that("total raster population equals total source population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  tr <- .sfp(.rect(0, 1500, 0, 1500), .rect(2000, 4000, 2000, 4000),
             .rect(30, 90, 30, 90), geoid = c("A", "B", "C"))
  pop <- c(1234, 5678, 9)
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = pop)
  expect_equal(terra::global(pr, "sum")[[1]], sum(pop), tolerance = 1e-6)
})

test_that("no negative cell populations are created (and negative source is rejected)", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  tr <- .sfp(.rect(0, 2000, 0, 2000), geoid = "A")
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = 500)
  expect_true(all(terra::values(pr)[, 1] >= 0))
  expect_error(allocate_pop_areaweighted(tmpl, tr, pop = -1), "negative")
})

test_that("boundary and sliver polygons do not disappear", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  # A thin sliver straddling the vertical cell boundary at x=1000.
  sliver <- .rect(995, 1005, 200, 3800)
  tr <- .sfp(sliver, geoid = "SL")
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = 42)
  expect_equal(terra::global(pr, "sum")[[1]], 42, tolerance = 1e-6)
  expect_gt(sum(terra::values(pr)[, 1] > 0), 1L)          # split across the seam
})

test_that("allocation is invariant to feature-row order", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  polys <- list(.rect(0, 1500, 0, 1500), .rect(2000, 4000, 2500, 4000),
                .rect(40, 120, 40, 120))
  tr1 <- sf::st_sf(GEOID = c("A", "B", "C"),
                   geometry = sf::st_sfc(polys[[1]], polys[[2]], polys[[3]], crs = 5070))
  ord <- c(3, 1, 2)
  tr2 <- sf::st_sf(GEOID = c("C", "A", "B"),
                   geometry = sf::st_sfc(polys[[3]], polys[[1]], polys[[2]], crs = 5070))
  p1 <- allocate_pop_areaweighted(tmpl, tr1, pop = c(100, 200, 300))
  p2 <- allocate_pop_areaweighted(tmpl, tr2, pop = c(300, 100, 200))
  expect_equal(terra::values(p1)[, 1], terra::values(p2)[, 1], tolerance = 1e-9)
})

test_that("the same tract population is conserved under both 2010 and 2020 geometries", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  # Same population, two different partitions of the same footprint (the seam).
  p2010 <- .sfp(.rect(0, 2000, 0, 4000), .rect(2000, 4000, 0, 4000),
                geoid = c("W", "E"))
  p2020 <- .sfp(.rect(0, 4000, 0, 2000), .rect(0, 4000, 2000, 4000),
                geoid = c("S", "N"))
  r10 <- allocate_pop_areaweighted(tmpl, p2010, pop = c(1000, 1000))
  r20 <- allocate_pop_areaweighted(tmpl, p2020, pop = c(1000, 1000))
  # Identical total under both vintages -> the seam test's total-demand confound
  # is removed by mass-conserving allocation.
  expect_equal(terra::global(r10, "sum")[[1]], 2000, tolerance = 1e-6)
  expect_equal(terra::global(r20, "sum")[[1]], terra::global(r10, "sum")[[1]],
               tolerance = 1e-6)
})

test_that("zero-area / no-overlap tract fails explicitly rather than dropping population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl_km()
  # A populated tract entirely OUTSIDE the template extent -> must stop(), not
  # silently vanish.
  outside <- .sfp(.rect(10000, 11000, 10000, 11000), geoid = "OUT")
  expect_error(allocate_pop_areaweighted(tmpl, outside, pop = 50),
               "zero template overlap|refusing to drop")
})
