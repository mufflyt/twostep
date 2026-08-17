# Frozen Colorado regression for the zero-versus-unreached contract.
#
# The fixture is a real 1,447-tract Colorado E2SFCA study area built outside
# this repo (real provider coordinates, so it is not committed here). When it is
# absent these tests skip; when present they are the end-to-end proof that the
# contract holds on real data at real scale, not only on hand-sized fixtures.
#
# 190 is hard-coded ONLY here. The implementation must never know it.

fixture_dir <- Sys.getenv("MM_CO_FIXTURE_DIR",
                          unset = path.expand("~/co-validation-fixture"))
have_fixture <- function() {
  all(file.exists(file.path(fixture_dir,
    c("tracts.rds", "supply.rds", "overlap.rds", "e2sfca_twostep.rds"))))
}
co <- function(f) readRDS(file.path(fixture_dir, paste0(f, ".rds")))

co_result <- function() {
  compute_e2sfca(
    overlap = co("overlap"),
    tract_pop = sf::st_drop_geometry(co("tracts")),
    supply = co("supply")[, c("coord_id", "supply")],
    weights = E2SFCA_DEFAULT_WEIGHTS[c("30", "60")])
}

test_that("Colorado classifies 1,447 tracts as 1,257 within and 190 outside", {
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  a <- co_result()$access
  expect_equal(nrow(a), 1447L)
  expect_equal(sum(a$coverage_status == "within_modeled_catchment"), 1257L)
  expect_equal(sum(a$coverage_status == "outside_all_modeled_catchments"), 190L)
  expect_equal(sum(a$reached), 1257L)
})

test_that("the 190 are EXACTLY the tracts with no catchment relationship", {
  # Not "190 rows that happen to be zero". Derived independently from the
  # overlap table, which is the relationship coverage is supposed to describe.
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  a <- co_result()$access
  absent_from_overlap <- setdiff(a$GEOID, unique(as.character(co("overlap")$GEOID)))
  expect_setequal(a$GEOID[!a$reached], absent_from_overlap)
  expect_equal(length(absent_from_overlap), 190L)
})

test_that("every unreached Colorado tract is NA scientifically and 0 algebraically", {
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  a <- co_result()$access
  out <- a[!a$reached, ]
  expect_true(all(is.na(out$access)))
  expect_true(all(is.na(out$access_scaled)))
  expect_true(all(out$access_math == 0))
  expect_true(all(out$access_scaled_math == 0))
  expect_true(all(out$coverage_status == "outside_all_modeled_catchments"))
})

test_that("every reached Colorado tract keeps score == math, genuine zeros included", {
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  a <- co_result()$access
  hit <- a[a$reached, ]
  expect_equal(hit$access, hit$access_math)
  expect_false(any(is.na(hit$access)))
})

test_that("REGRESSION: the numbers did not move for any reached tract", {
  # The expected numerical change to the algorithm is exactly zero. This
  # compares against the surface computed BEFORE the contract repair, frozen in
  # the fixture. If this ever fails, the patch stopped being a contract change.
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  before <- co("e2sfca_twostep")$access
  a <- co_result()$access
  m <- merge(before[, c("GEOID", "access")], a[, c("GEOID", "access", "reached")],
             by = "GEOID", suffixes = c("_before", "_after"))
  hit <- m[m$reached, ]
  expect_equal(nrow(hit), 1257L)
  expect_equal(hit$access_after, hit$access_before, tolerance = 1e-12)
})

test_that("supply conservation is unchanged, on the algebraic column", {
  skip_if_not(have_fixture(), "Colorado adjudication fixture not present")
  tracts <- co("tracts")
  a <- co_result()$access
  pv <- stats::setNames(tracts$female_pop, as.character(tracts$GEOID))
  expect_equal(sum(pv[a$GEOID] * a$access_math), sum(co("supply")$supply),
               tolerance = 1e-9)
  # And the scientific column deliberately will not do this silently.
  expect_true(is.na(sum(pv[a$GEOID] * a$access)))
})
