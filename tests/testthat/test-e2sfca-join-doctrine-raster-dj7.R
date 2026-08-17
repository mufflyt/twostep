# =============================================================================
# Scientific join doctrine on the RASTER path and in desjardins7.
# =============================================================================
# The doctrine was enforced in compute_e2sfca() first. These are the other two
# surfaces that consume the same scientific keys, and both had real violations:
# the raster path silently wiped out an origin's ENTIRE demand when a band had
# no weight, and dj7_tract_access silently zeroed unmatched tracts and origins.
#
#   No silent loss.  No silent multiplication.  No silent zeroing.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "two_step_floating_catchment.R"))
source(file.path(.root, "R", "desjardins7_e2sfca.R"))

# --- the shared diagnostic ----------------------------------------------------
test_that("the diagnostic reports what joined to what, how many, and which ids", {
  m <- .sci_join_msg("membership", "dvec", "GEOID",
                     c("T1","T2","T3","T4","T5","T6"), " Extra context.")
  expect_match(m, "membership -> dvec")
  expect_match(m, "joined on `GEOID`")
  expect_match(m, "6 key\\(s\\)")
  expect_match(m, "T1, T2, T3, T4, T5")
  expect_match(m, "and 1 more")
  expect_match(m, "Extra context")
})

test_that(".unmatched_keys finds exactly the keys with no match", {
  x <- data.frame(k = c("a","b","c","c"), stringsAsFactors = FALSE)
  y <- data.frame(k = c("b","c"), stringsAsFactors = FALSE)
  expect_equal(.unmatched_keys(x, y, "k"), "a")
  expect_equal(.unmatched_keys(y, x, "k"), character(0))
})

# --- desjardins7 --------------------------------------------------------------
# dj7_incr_weights requires the full four-band vector, so the fixture uses
# DJ7_WC_BASE with membership in the 30-minute band only.
#
# Hand derivation. Incremental weights are (0.32, 0.46, 0.13, 0.09).
#   Step 1 uses INCREMENTAL: Dj[P1] = 0.32 * (100 + 300) = 128, R = 4/128 = 0.03125
#   Step 2 uses CUMULATIVE via the tightest band: w = Wc[["30"]] = 1.00
#   so A = 1.00 * 0.03125 = 0.03125 for both tracts.
.dj7_fixture <- function() {
  list(
    membership = list("30" = data.frame(GEOID = c("T1","T2"), coord_id = c("P1","P1"),
                                        stringsAsFactors = FALSE)),
    supply = c(P1 = 4),
    dvec   = c(T1 = 100, T2 = 300))
}

test_that("dj7_tract_access reproduces a hand calculation", {
  f <- .dj7_fixture()
  a <- dj7_tract_access(f$membership, f$supply, f$dvec)
  expect_setequal(a$GEOID, c("T1","T2"))
  expect_equal(a$A[a$GEOID == "T1"], 0.03125, tolerance = 1e-12)
  expect_equal(a$A[a$GEOID == "T2"], 0.03125, tolerance = 1e-12)
})

test_that("FAIL CLOSED: a tract in the membership with no demand entry is refused", {
  f <- .dj7_fixture()
  f$dvec <- f$dvec["T1"]                     # T2 is reached but has no demand
  expect_error(dj7_tract_access(f$membership, f$supply, f$dvec), "T2")
  expect_error(dj7_tract_access(f$membership, f$supply, f$dvec), "inflate accessibility")
  expect_error(dj7_tract_access(f$membership, f$supply, f$dvec), "-> dvec")
})

test_that("an explicit zero demand is valid and is NOT confused with a missing key", {
  f <- .dj7_fixture(); f$dvec["T2"] <- 0
  a <- dj7_tract_access(f$membership, f$supply, f$dvec)
  # Demand falls to 0.32 * 100 = 32, so R = 4/32 = 0.125 and A = 1.00 * 0.125.
  expect_equal(a$A[a$GEOID == "T1"], 0.125, tolerance = 1e-12)
  expect_equal(nrow(a), 2)
})

test_that("dj7 detection does not depend on row order", {
  f <- .dj7_fixture(); f$dvec <- f$dvec["T1"]
  m <- f$membership[["30"]]
  for (ord in list(c(2,1), c(1,2))) {
    f2 <- f; f2$membership[["30"]] <- m[ord, , drop = FALSE]
    expect_error(dj7_tract_access(f2$membership, f$supply, f$dvec), "T2")
  }
})

# --- raster path --------------------------------------------------------------
test_that("the raster path refuses duplicate origins BEFORE any geometry work", {
  # Validated up front, so the error is about the input rather than a downstream
  # symptom. A duplicated origin is counted twice in Step 2 and OVERSTATES
  # accessibility -- the same hole the vector path already closes.
  sup <- data.frame(coord_id = c("P1", "P1"), supply = c(2, 2), stringsAsFactors = FALSE)
  expect_error(
    compute_e2sfca_raster(grid = list(), iso = NULL, supply = sup,
                          weights = E2SFCA_DEFAULT_WEIGHTS),
    "OVERSTATE accessibility")
  expect_error(
    compute_e2sfca_raster(grid = list(), iso = NULL, supply = sup,
                          weights = E2SFCA_DEFAULT_WEIGHTS),
    "supply -> itself joined on `coord_id`")
})

test_that("the raster band filter is explicit rather than an NA that zeroes a whole origin", {
  # Before the change, a band with no weight joined to NA, propagated through
  # sum(w_inc * cum_pop) to an NA demand, and was zeroed -- silently removing
  # that origin entirely. The source now filters bands explicitly and counts it.
  src <- readLines(file.path(.root, "R", "two_step_floating_catchment.R"))
  i0 <- grep("^compute_e2sfca_raster <- function", src)
  i1 <- i0 + which(src[i0:length(src)] == "}")[1] - 1L
  body <- src[i0:i1]
  expect_true(any(grepl("bands_outside <- setdiff", body)))
  expect_true(any(grepl('relationship = "many-to-one"', body)))
  expect_true(any(grepl("bands_outside_weight_vector", body)))
  # And nothing in the raster body joins band weights without the guard.
  expect_false(any(grepl('left_join\\(cumpop,$', body)))
})
