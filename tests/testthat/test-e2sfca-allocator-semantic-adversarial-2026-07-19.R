# ==============================================================================
# Semantic + adversarial tests for the E2SFCA allocator
# (R/two_step_floating_catchment.R).
#
# These are NEW invariant guards, deliberately non-overlapping with
# tests/testthat/test-two-step-floating-catchment.R. They target four contracts
# the 11-year production run depends on:
#   1. band weights are a monotone non-increasing distance-decay that equals the
#      documented default vector and are sorted by ascending band;
#   2. incremental weights PARTITION the cumulative weights (reverse-cumsum
#      reconstructs them exactly, no double counting);
#   3. allocate_pop_areaweighted is MASS-CONSERVING and never invents, destroys,
#      or negativizes population, and fails LOUD instead of silently dropping it;
#   4. supply is per-subspecialty and MUST NOT pool the 7 subspecialties;
#      the two-step ratio never leaks Inf/NaN from a zero catchment.
#
# Style: no em-dashes or en-dashes anywhere. Hyphens, commas, or "to" only.
# Heavy deps (sf/terra/exactextractr) are guarded with skip_if_not_installed.
# ==============================================================================

suppressWarnings({
  library(testthat)
})

source(testthat::test_path("..", "..", "R", "two_step_floating_catchment.R"))

# Axis-aligned rectangle as an sf polygon geometry in EPSG:5070.
.rect2 <- function(xmin, xmax, ymin, ymax) {
  sf::st_polygon(list(rbind(
    c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
  )))
}

# A 4x4 grid of 1 km cells in the equal-area CRS (row-major, top-left = 1).
.tmpl2 <- function(n = 4, res = 1000) {
  r <- terra::rast(xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
                   resolution = res, crs = "EPSG:5070")
  terra::values(r) <- NA_real_
  r
}

.sf_polys <- function(polys, geoid) {
  sf::st_sf(GEOID = geoid, geometry = sf::st_sfc(polys, crs = 5070))
}

# ==============================================================================
# 1. Band weights: documented default, monotone non-increasing, band-sorted
# ==============================================================================
test_that("default band weights equal the documented vector and are non-increasing", {
  w <- e2sfca_band_weights()   # no args -> E2SFCA_DEFAULT_WEIGHTS
  # Exactly the four canonical bands, exactly the documented decay values.
  expect_equal(names(w), c("30", "60", "120", "180"))
  expect_equal(unname(w), c(1.00, 0.68, 0.22, 0.09), tolerance = 1e-12)
  # Monotone non-increasing: no farther band ever counts MORE than a nearer one.
  expect_true(all(diff(w) <= 1e-9))
})

test_that("band weights are returned sorted by ascending band regardless of input order", {
  # Names are numeric-string bands; supplied here out of order and unsorted.
  scrambled <- c("180" = 0.09, "30" = 1.00, "120" = 0.22, "60" = 0.68)
  w <- e2sfca_band_weights(scrambled)
  expect_equal(names(w), c("30", "60", "120", "180"))          # ascending band
  expect_equal(unname(w), c(1.00, 0.68, 0.22, 0.09), tolerance = 1e-12)
  expect_true(all(diff(as.integer(names(w))) > 0))             # strictly increasing bands
})

test_that("a flat (constant) weight vector is accepted and yields zero inner increments", {
  # Weakly monotone means equal successive weights are legal; increments are 0
  # except the outermost, which is its own weight. Guards the >1e-9 diff branch.
  w <- e2sfca_band_weights(c("30" = 0.5, "60" = 0.5, "120" = 0.5))
  expect_equal(unname(w), c(0.5, 0.5, 0.5))
  inc <- e2sfca_incremental_weights(c("30" = 0.5, "60" = 0.5, "120" = 0.5))
  expect_equal(unname(inc["30"]), 0, tolerance = 1e-12)
  expect_equal(unname(inc["60"]), 0, tolerance = 1e-12)
  expect_equal(unname(inc["120"]), 0.5, tolerance = 1e-12)     # outermost = own weight
})

# ==============================================================================
# 2. Incremental weights PARTITION the cumulative weights (no double counting)
# ==============================================================================
test_that("reverse cumulative sum of incremental weights reconstructs the cumulative weights", {
  W   <- c("30" = 1.00, "60" = 0.68, "120" = 0.22, "180" = 0.09)
  inc <- e2sfca_incremental_weights(W)
  # W_b = sum over bands k >= b of inc_k. rev(cumsum(rev(inc))) is that partial
  # sum from the outermost band inward. If it equals W for every band, the
  # increments partition the cumulative weights with no gap and no overlap.
  reconstructed <- rev(cumsum(rev(inc)))
  expect_equal(unname(reconstructed), unname(W), tolerance = 1e-12)
  expect_equal(names(reconstructed), names(W))
  # All increments non-negative (the monotone contract guarantees a valid partition).
  expect_true(all(inc >= -1e-12))
})

test_that("incremental weights are non-negative even at the float-clamp boundary", {
  # A weight drop just under the 1e-9 monotone tolerance must not yield a
  # negative increment (the source clamps tiny negatives to 0).
  W <- c("30" = 1.0, "60" = 1.0 + 5e-10)   # 60 is trivially "higher" within tol
  inc <- e2sfca_incremental_weights(W)
  expect_true(all(inc >= 0))
})

# ==============================================================================
# 3. compute_band_tract_overlap: cumulative fractions are non-decreasing in band
# ==============================================================================
test_that("cumulative overlap fraction is monotone non-decreasing across nested bands", {
  skip_if_not_installed("sf")
  # One tract fully inside progressively larger nested cumulative isochrones.
  tracts <- sf::st_sf(
    GEOID = "T1",
    geometry = sf::st_sfc(.rect2(0, 10, 0, 10), crs = 5070)
  )
  # 30 covers a quarter, 60 covers half, 120 covers all of T1. Nested (cumulative).
  iso <- sf::st_sf(
    coord_id = c("A", "A", "A"),
    drive_time_minutes = c(30L, 60L, 120L),
    geometry = sf::st_sfc(
      .rect2(0, 5, 0, 5),    # 25% of T1
      .rect2(0, 10, 0, 5),   # 50% of T1
      .rect2(0, 10, 0, 10),  # 100% of T1
      crs = 5070
    )
  )
  ov <- compute_band_tract_overlap(iso, tracts, verbose = FALSE)
  ov <- ov[order(ov$band), ]
  expect_equal(ov$overlap_fraction, c(0.25, 0.5, 1.0), tolerance = 1e-9)
  # The load-bearing invariant: a larger cumulative band never covers LESS.
  expect_true(all(diff(ov$overlap_fraction) >= -1e-9))
})

# ==============================================================================
# 4. Supply is per-subspecialty: NEVER pool the 7 subspecialties
# ==============================================================================
test_that("compute_provider_supply is per-subspecialty and does not pool subspecialties", {
  # Same origin A hosts a GO and an MFM physician; origin B hosts a MIGS.
  # Selecting one subspecialty must count ONLY that subspecialty's NPIs.
  ycm <- dplyr::tibble(
    npi           = c("10", "11", "12", "13"),
    analysis_year = c(2020L, 2020L, 2020L, 2020L),
    coord_id      = c("A", "A", "B", "A"),
    match_source  = c("spatial", "spatial", "spatial", "spatial")
  )
  cohort <- dplyr::tibble(
    npi = c("10", "11", "12", "13"),
    subspecialty_normalized = c("GO", "MFM", "MIGS", "GO")
  )
  go   <- compute_provider_supply(ycm, cohort, "GO",   2020L)
  mfm  <- compute_provider_supply(ycm, cohort, "MFM",  2020L)
  migs <- compute_provider_supply(ycm, cohort, "MIGS", 2020L)

  # GO: NPIs 10 and 13, both at origin A -> supply 2 at A, and NO origin B.
  expect_setequal(go$coord_id, "A")
  expect_equal(go$supply[go$coord_id == "A"], 2L)
  # MFM: only NPI 11 at A -> supply 1, MFM must NOT inherit the GO count.
  expect_setequal(mfm$coord_id, "A")
  expect_equal(mfm$supply[mfm$coord_id == "A"], 1L)
  # MIGS: only NPI 12 at B.
  expect_setequal(migs$coord_id, "B")
  expect_equal(migs$supply[migs$coord_id == "B"], 1L)
  # Pooling would give A a supply of 3 for any single subspecialty; it must not.
  expect_false(any(go$supply == 3L))
})

test_that("compute_provider_supply drops NA-subspecialty rows and returns no origins for an empty cohort", {
  ycm <- dplyr::tibble(
    npi = c("20", "21"), analysis_year = c(2020L, 2020L),
    coord_id = c("A", "B"), match_source = c("spatial", "spatial")
  )
  cohort <- dplyr::tibble(npi = c("20", "21"),
                          subspecialty_normalized = c(NA_character_, "GO"))
  # NPI 20 has NA subspecialty and must be excluded; NPI 21 (GO) is the only GO.
  go <- compute_provider_supply(ycm, cohort, "GO", 2020L)
  expect_setequal(go$coord_id, "B")
  # A subspecialty absent from the cohort yields a zero-row supply, not an error.
  none <- compute_provider_supply(ycm, cohort, "URPS", 2020L)
  expect_equal(nrow(none), 0L)
})

# ==============================================================================
# 5. compute_e2sfca: empty supply and zero-population edges never leak Inf/NaN
# ==============================================================================
test_that("compute_e2sfca with an empty cohort leaves every tract outside the model, no NaN", {
  overlap <- dplyr::tibble(coord_id = "A", band = 30L, GEOID = "T1",
                           overlap_fraction = 1)
  tractpop <- dplyr::tibble(GEOID = c("T1", "T2"), female_pop = c(100, 200))
  supply_empty <- dplyr::tibble(coord_id = character(0), supply = integer(0))
  res <- compute_e2sfca(overlap, tractpop, supply_empty, weights = c("30" = 1.0),
                        pop_col = "female_pop", per_capita_scale = 1)
  # Every tract present in tract_pop still gets a row. With no modelled
  # provider there is no catchment, so no tract is inside one -- the scientific
  # value is NA rather than a measured zero. (Was: `all(access == 0)`, which
  # said an empty cohort had been measured and found to supply nothing.)
  expect_setequal(res$access$GEOID, c("T1", "T2"))
  expect_true(all(is.na(res$access$access)))
  expect_true(all(res$access$coverage_status == "outside_all_modeled_catchments"))
  # The algebraic form is still exactly 0 and still finite -- the NaN guard this
  # test exists for is unchanged.
  expect_true(all(res$access$access_math == 0))
  expect_true(all(is.finite(res$access$access_math)))
  expect_true(all(res$access$n_providers == 0L))
})

test_that("compute_e2sfca with a mix of zero-pop and populated tracts stays finite", {
  # Provider A reaches both a zero-population tract and a populated one. The
  # zero-pop tract must not inject a divide-by-zero into any provider ratio.
  overlap <- dplyr::tibble(
    coord_id = c("A", "A"), band = c(30L, 30L),
    GEOID = c("T0", "T1"), overlap_fraction = c(1, 1)
  )
  tractpop <- dplyr::tibble(GEOID = c("T0", "T1"), female_pop = c(0, 50))
  supply   <- dplyr::tibble(coord_id = "A", supply = 4L)
  res <- compute_e2sfca(overlap, tractpop, supply, weights = c("30" = 1.0),
                        pop_col = "female_pop", per_capita_scale = 1)
  # demand_A = 1 * 0 + 1 * 50 = 50 ; R_A = 4/50 = 0.08.
  expect_equal(res$provider_ratios$ratio, 0.08, tolerance = 1e-9)
  expect_true(all(is.finite(res$access$access)))
  # The zero-pop tract still receives finite access (its own coverage of A).
  expect_true(is.finite(res$access$access[res$access$GEOID == "T0"]))
})

# ==============================================================================
# 6. allocate_pop_areaweighted: mass conservation under NA and zero-pop edges
# ==============================================================================
test_that("NA source population is treated as zero and total mass is conserved", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl2()
  tr <- .sf_polys(list(.rect2(0, 1500, 0, 1500),
                       .rect2(2000, 4000, 2000, 4000)),
                  geoid = c("A", "B"))
  pop <- c(500, NA_real_)   # B's population is missing -> counts as 0
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = pop)
  # Conserved total equals the sum of the non-NA population only.
  expect_equal(terra::global(pr, "sum")[[1]], 500, tolerance = 1e-6)
  expect_true(all(terra::values(pr)[, 1] >= 0))
})

test_that("a zero-population tract outside the template does NOT error (only populated ones must)", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl2()
  # Populated tract inside + an EMPTY (pop 0) tract entirely outside the grid.
  # The guard fires only for pop > 0 with no overlap, so pop 0 must pass cleanly.
  tr <- .sf_polys(list(.rect2(0, 1000, 0, 1000),
                       .rect2(50000, 51000, 50000, 51000)),
                  geoid = c("IN", "OUT0"))
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = c(321, 0))
  expect_equal(terra::global(pr, "sum")[[1]], 321, tolerance = 1e-6)
})

test_that("a populated degenerate (zero-area) tract fails loud rather than dropping population", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl2()
  # A collapsed rectangle (a vertical line, zero area) inside the grid extent.
  # It intersects no cell area, so the allocator must stop() to avoid silently
  # losing the 99 population it carries.
  degenerate <- .sf_polys(list(.rect2(2000, 2000, 500, 3500)), geoid = "LINE")
  expect_error(
    allocate_pop_areaweighted(tmpl, degenerate, pop = 99),
    "overlap|drop|population|area"
  )
})

test_that("conservation tolerance is enforced: a stricter-than-float tol still passes on clean geometry", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl2()
  # Cell-aligned tracts (exact area split) conserve to machine precision, so an
  # aggressive tol still passes. This exercises the audit branch without a bug.
  tr <- .sf_polys(list(.rect2(0, 2000, 0, 4000), .rect2(2000, 4000, 0, 4000)),
                  geoid = c("W", "E"))
  pr <- allocate_pop_areaweighted(tmpl, tr, pop = c(1000, 3000),
                                  conservation_tol = 1e-9)
  expect_equal(terra::global(pr, "sum")[[1]], 4000, tolerance = 1e-6)
})

test_that("allocation length mismatch between pop and tracts is rejected", {
  skip_if_not_installed("terra"); skip_if_not_installed("exactextractr")
  tmpl <- .tmpl2()
  tr <- .sf_polys(list(.rect2(0, 1000, 0, 1000), .rect2(1000, 2000, 0, 1000)),
                  geoid = c("A", "B"))
  # pop has length 1 but there are 2 tracts -> stopifnot in the allocator.
  expect_error(allocate_pop_areaweighted(tmpl, tr, pop = 100))
})

# ==============================================================================
# 8. The conservation GUARDS themselves must fire.
# ==============================================================================
# Added 2026-08-16 after the scientific mutation corpus
# (tools/ci/mutation_corpus.R) showed that replacing the per-tract conservation
# check with `if (FALSE)` was killed by NO test. The allocator's whole purpose is
# mass conservation, and its safety net was untested: every existing test
# confirmed that conservation HOLDS, none confirmed that a violation would be
# CAUGHT. Those are different claims, and only the second one protects you when
# the arithmetic changes.
test_that("the per-tract conservation guard fires when the tolerance is exceeded", {
  tmpl <- .tmpl2()
  tr   <- .sf_polys(list(.rect2(0, 2000, 0, 2000), .rect2(2000, 4000, 0, 2000)),
                    c("A", "B"))
  # A negative tolerance makes any conservation error at all -- including the
  # unavoidable floating-point residue -- exceed it, so a wired-up guard MUST
  # raise. With the guard disabled this call returns quietly and the test fails.
  expect_error(
    allocate_pop_areaweighted(tmpl, tr, pop = c(1000, 3000), conservation_tol = -1),
    # SPECIFIC on purpose. A loose "conservation error" would also match the
    # GLOBAL guard, so disabling the per-tract one would still pass.
    "per-tract conservation error")
})

test_that("the allocator refuses inputs that would silently lose population", {
  tmpl <- .tmpl2()
  tr   <- .sf_polys(list(.rect2(0, 2000, 0, 2000)), "A")
  # Negative source population is meaningless and must not be coerced away.
  expect_error(allocate_pop_areaweighted(tmpl, tr, pop = -5),
               "negative source population")
  # A tract carrying population that falls entirely outside the template would
  # drop that population on the floor; the allocator must refuse rather than
  # quietly under-count.
  far <- .sf_polys(list(.rect2(1e6, 1e6 + 1000, 1e6, 1e6 + 1000)), "FAR")
  expect_error(allocate_pop_areaweighted(tmpl, far, pop = 250),
               "zero template overlap|refusing to drop population")
})
