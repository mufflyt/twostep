# =============================================================================
# The exported dj7 helpers that no test had ever called
# =============================================================================
# tools/ci/scientific_coverage.R was written to answer one question: which
# exported scientific functions does no test ever touch? It found nine, seven of
# them here. covr independently confirmed them at 0% executed lines, so this is
# not a static-analysis artefact -- these functions genuinely ran nowhere in the
# suite.
#
# That matters more than the percentage suggests. Every one of these encodes a
# BOUNDARY that the documentation states as inclusive or exclusive, and a
# boundary nobody asserts is a boundary that can flip in a refactor without any
# test objecting. "years_since_cert <= 15 is Early-to-mid" is a study definition;
# if it silently became `<`, physicians certified exactly 15 years ago would
# change cohort and every stratified result would shift by a little.
#
# Writing the fix for dj7_no_access_share's silent drop (below) also only became
# possible once something called it.
#
# source() rather than library(twostep): the nightly testthat job deliberately
# does NOT install the package, so every suite reaches the code through the
# working tree. A file that relies on an attached package passes under
# devtools::load_all() locally and errors with "could not find function" there.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "desjardins7_e2sfca.R"))
source(file.path(.root, "R", "accessibility_stratification.R"))

test_that("dj7_wmean matches the weighted-mean definition and its zero-weight rule", {
  x <- c(1, 2, 3, 4)
  w <- c(1, 1, 1, 1)
  expect_equal(dj7_wmean(x, w), 2.5)

  # Unequal weights, computed by hand: (10*1 + 20*3) / (1 + 3) = 70/4
  expect_equal(dj7_wmean(c(10, 20), c(1, 3)), 17.5)

  # Zero-weight elements contribute to NEITHER numerator nor denominator. If a
  # zero-weight element leaked into the denominator the answer would be 70/5.
  expect_equal(dj7_wmean(c(10, 20, 999), c(1, 3, 0)), 17.5)

  # NA weights are dropped the same way; an NA VALUE at zero weight must not
  # poison the result, which is the case the `ok` mask exists for.
  expect_equal(dj7_wmean(c(10, 20, NA), c(1, 3, 0)), 17.5)

  # No positive weight left -> NA, not NaN and not zero. Zero would be a
  # fabricated answer; NA says "undefined on this input".
  expect_true(is.na(dj7_wmean(c(1, 2), c(0, 0))))
  expect_true(is.na(dj7_wmean(c(1, 2), c(NA, NA))))
  expect_true(is.na(dj7_wmean(numeric(0), numeric(0))))

  # Documented equivalence with the sibling library function. The docs promise
  # these two cannot diverge; that promise was never checked.
  if (exists("weighted_mean_all")) {
    expect_equal(dj7_wmean(c(10, 20, 30), c(2, 0, 5)),
                 weighted_mean_all(c(10, 20, 30), c(2, 0, 5)))
  }

  expect_error(dj7_wmean(c(1, 2, 3), c(1, 2)))
})

test_that("dj7_parse_coord_id round-trips origin keys and degrades to NA, not error", {
  out <- dj7_parse_coord_id(c("39.73921_-104.99025", "40.0_-105.5"))
  expect_equal(nrow(out), 2L)
  expect_equal(out$lat, c(39.73921, 40.0))
  expect_equal(out$lon, c(-104.99025, -105.5))
  expect_type(out$coord_id, "character")

  # Malformed keys yield NA for the affected field rather than aborting: these
  # are parsed in bulk from upstream tables and one bad row must not take the
  # whole run down. The contract is per-field, so a key with a good latitude and
  # a junk longitude keeps the latitude.
  bad <- dj7_parse_coord_id(c("nounderscore", "39.5_junk", ""))
  expect_true(is.na(bad$lat[1]))
  expect_true(is.na(bad$lon[1]))
  expect_equal(bad$lat[2], 39.5)
  expect_true(is.na(bad$lon[2]))

  # Round-trip against the parser's own output: reconstructing the key from the
  # parsed pieces must give back the input.
  keys <- c("39.73921_-104.99025", "40_-105")
  p <- dj7_parse_coord_id(keys)
  expect_equal(paste0(p$lat, "_", p$lon), c("39.73921_-104.99025", "40_-105"))
})

test_that("dj7_conus_ok gates the documented bounding box and rejects NA", {
  # Inside
  expect_true(dj7_conus_ok(39.7, -104.9))     # Denver
  expect_true(dj7_conus_ok(25.8, -80.2))      # Miami
  # Outside: the three exclusions the docs name explicitly
  expect_false(dj7_conus_ok(61.2, -149.9))    # Anchorage, AK
  expect_false(dj7_conus_ok(21.3, -157.8))    # Honolulu, HI
  expect_false(dj7_conus_ok(18.4, -66.1))     # San Juan, PR

  # The box is documented as OPEN on all four sides: lon in (-125, -66),
  # lat in (24, 50). A point exactly on an edge is out. If any of these flipped
  # to closed, coastal and border origins would silently enter or leave the
  # study area.
  expect_false(dj7_conus_ok(39.7, -125))
  expect_false(dj7_conus_ok(39.7, -66))
  expect_false(dj7_conus_ok(24, -100))
  expect_false(dj7_conus_ok(50, -100))
  expect_true(dj7_conus_ok(24.001, -124.999))

  # NA is FALSE, not NA: this gate feeds subsetting, where an NA would select a
  # row of NAs rather than dropping it.
  expect_false(dj7_conus_ok(NA_real_, -104.9))
  expect_false(dj7_conus_ok(39.7, NA_real_))
  expect_equal(dj7_conus_ok(c(39.7, NA, 61.2), c(-104.9, -104.9, -149.9)),
               c(TRUE, FALSE, FALSE))
})

test_that("dj7_career_stage splits INCLUSIVE of the cutoff", {
  expect_equal(dj7_career_stage(0),  "Early-to-mid")
  expect_equal(dj7_career_stage(14), "Early-to-mid")
  # The boundary itself. Exactly `cutoff` years is Early-to-mid; this single
  # assertion is the whole reason the function is worth testing.
  expect_equal(dj7_career_stage(15), "Early-to-mid")
  expect_equal(dj7_career_stage(16), "Late")
  expect_equal(dj7_career_stage(40), "Late")

  # NA years -> NA stage, never silently assigned to a cohort.
  expect_true(is.na(dj7_career_stage(NA_real_)))
  expect_equal(dj7_career_stage(c(10, 15, 16, NA)),
               c("Early-to-mid", "Early-to-mid", "Late", NA))

  # The cutoff is a parameter, and moving it moves the boundary with it.
  expect_equal(dj7_career_stage(15, cutoff = 10), "Late")
  expect_equal(dj7_career_stage(10, cutoff = 10), "Early-to-mid")
})

test_that("dj7_in_surface is INCLUSIVE of the cluster radius", {
  expect_true(dj7_in_surface(0))
  expect_true(dj7_in_surface(4.99))
  expect_true(dj7_in_surface(5))          # exactly the radius is in-surface
  expect_false(dj7_in_surface(5.01))
  expect_false(dj7_in_surface(100))

  # NA distance -> FALSE. A recovered physician whose nearest origin is unknown
  # must not be assumed to re-enter the surface: that would add supply to a
  # catchment on the strength of a missing value.
  expect_false(dj7_in_surface(NA_real_))

  expect_equal(dj7_in_surface(c(1, 5, 5.0001, NA)),
               c(TRUE, TRUE, FALSE, FALSE))
  expect_true(dj7_in_surface(10, radius_km = 10))
  expect_false(dj7_in_surface(10.5, radius_km = 10))
})

test_that("dj7_assign_quintile puts zero-access in category 1 and quartiles the rest", {
  # Hand-built: eight positive values 1..8 plus two zeros. Quartiles of the
  # POSITIVE distribution 1..8 are 2.75 / 4.5 / 6.25, so
  #   (0, 2.75] -> 2   (2.75, 4.5] -> 3   (4.5, 6.25] -> 4   (6.25, ) -> 5
  access <- c(0, 0, 1, 2, 3, 4, 5, 6, 7, 8)
  q <- dj7_assign_quintile(access)
  expect_equal(q[1:2], c(1L, 1L))
  expect_equal(q, c(1L, 1L, 2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L))

  # Category 1 is defined by access <= 0, and the zeros must NOT be included in
  # the quartile computation -- if they were, the cut points would move.
  expect_equal(dj7_assign_quintile(c(1:8)), c(2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L))

  # All five categories are integers in 1:5, always.
  expect_type(q, "integer")
  expect_true(all(q >= 1L & q <= 5L))

  # NA is filed as category 1. This is the documented reproduction of the
  # published rule, NOT a claim that unmeasured equals zero -- the roxygen block
  # says so explicitly, and the caller is told to pass `access_math`. Pinned
  # here so the behaviour cannot change silently in either direction.
  # Same 1..8 positive distribution as above, so the categories are the ones
  # already derived by hand; the NA simply prepends a category 1 without
  # disturbing the cut points (it is not a positive value).
  expect_equal(dj7_assign_quintile(c(NA, 1, 2, 3, 4, 5, 6, 7, 8)),
               c(1L, 2L, 2L, 3L, 3L, 4L, 4L, 5L, 5L))

  # Supplied breaks are used instead of computed ones.
  expect_equal(dj7_assign_quintile(c(1, 5, 9), brk = c(2, 6, 8)),
               c(2L, 3L, 5L))

  # No positive values at all: everything is category 1 and nothing errors on
  # the empty quantile.
  expect_equal(dj7_assign_quintile(c(0, 0, 0)), c(1L, 1L, 1L))
  expect_equal(dj7_assign_quintile(numeric(0)), integer(0))
})

test_that("dj7_no_access_share is population-weighted, not tract-counted", {
  # Two tracts have zero access. They hold 100 of 1000 people, so the share is
  # 10% -- NOT the 50% a tract count would give. This distinction is the entire
  # point of the function and was previously asserted nowhere.
  acc  <- data.frame(GEOID = c("A", "B", "C", "D"), A = c(0, 0, 0.5, 0.9))
  dvec <- c(A = 50, B = 50, C = 400, D = 500)
  expect_equal(dj7_no_access_share(acc, dvec), 10)

  # Tracts in dvec with NO row in access_df are unreached, hence zero access.
  # Here E holds 500 more people and appears in no access row: (50+50+500)/1500.
  dvec2 <- c(dvec, E = 500)
  expect_equal(dj7_no_access_share(acc, dvec2), 100 * 600 / 1500)

  # Invariant to the positive values: the zero-access SET is geometric.
  acc_bigger <- transform(acc, A = ifelse(A > 0, A * 1000, A))
  expect_equal(dj7_no_access_share(acc_bigger, dvec),
               dj7_no_access_share(acc, dvec))

  # Bounds and degenerate denominators.
  expect_equal(dj7_no_access_share(data.frame(GEOID = "A", A = 0), c(A = 10)), 100)
  expect_equal(dj7_no_access_share(data.frame(GEOID = "A", A = 1), c(A = 10)), 0)
  expect_true(is.na(dj7_no_access_share(acc, c(A = 0, B = 0, C = 0, D = 0))))
})

test_that("dj7_no_access_share fails closed on keys that would change the denominator", {
  acc  <- data.frame(GEOID = c("A", "B", "C"), A = c(0, 0.5, 0.9))
  dvec <- c(A = 100, B = 400, C = 500)

  # THE DEFECT THIS COVERAGE PASS FOUND. Before the fix, a tract with a measured
  # access value but no demand weight was dropped by intersect() without a word.
  # That is a silent change to the population denominator -- exactly the class
  # of failure the join doctrine forbids -- and it survived the doctrine sweep
  # only because no test called this function.
  expect_error(dj7_no_access_share(rbind(acc, data.frame(GEOID = "Z", A = 0)), dvec),
               "no match in dvec")
  expect_error(dj7_no_access_share(rbind(acc, data.frame(GEOID = "Z", A = 0)), dvec),
               "Z")

  # A duplicated GEOID would let match() keep the first row and discard the
  # rest, so a tract could be recorded as zero-access or not depending on row
  # order alone.
  expect_error(dj7_no_access_share(rbind(acc, data.frame(GEOID = "A", A = 9)), dvec),
               "duplicated GEOID")

  # The legitimate direction still works: dvec keys absent from access_df are
  # unreached, and stay zero rather than erroring.
  expect_silent(dj7_no_access_share(acc, c(dvec, Q = 1)))
})

test_that("the dj7 helpers compose into the published categorisation end to end", {
  # A miniature study run through the helpers in the order the scripts use them,
  # so the pieces are checked together and not only in isolation.
  coords <- c("39.7_-104.9", "40.0_-105.5", "61.2_-149.9")   # third is Alaska
  p <- dj7_parse_coord_id(coords)
  keep <- dj7_conus_ok(p$lat, p$lon)
  expect_equal(keep, c(TRUE, TRUE, FALSE))

  acc  <- data.frame(GEOID = c("T1", "T2", "T3", "T4"), A = c(0, 0.2, 0.6, 1.4))
  dvec <- c(T1 = 200, T2 = 300, T3 = 250, T4 = 250)

  share <- dj7_no_access_share(acc, dvec)
  expect_equal(share, 20)                       # 200 of 1000

  q <- dj7_assign_quintile(acc$A)
  expect_equal(q[1], 1L)                        # the zero-access tract
  expect_true(all(q[-1] >= 2L))                 # everything reached is 2..5

  # The population-weighted mean access over the same tracts, by hand:
  # (0*200 + 0.2*300 + 0.6*250 + 1.4*250)/1000 = (0 + 60 + 150 + 350)/1000
  expect_equal(dj7_wmean(acc$A, dvec), 0.56)
})
