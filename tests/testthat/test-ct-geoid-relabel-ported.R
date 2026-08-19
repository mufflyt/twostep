# ==============================================================================
# Connecticut planning-region GEOID relabel -- ported from isochrones 2026-08-18.
# ==============================================================================
# THE BUG THIS PINS
#   From ACS 2022 the Census Bureau returns CT tracts under planning-region
#   county FIPS (09110-09190); the access surface uses legacy county FIPS
#   (09001-09015). An unrelabeled GEOID join matches ZERO Connecticut tracts,
#   so the whole state silently leaves the analysis. A national match-rate gate
#   does not catch it (CT is ~1% of tracts).
#
# Each test states what it would let through if it were deleted.
# ==============================================================================

# source() rather than library(twostep): the nightly testthat job deliberately
# does NOT install the package, so every suite reaches the code through the
# working tree.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "ct_geoid_relabel.R"))

skip_if_no_table <- function() {
  if (!nzchar(ct_equivalency_table_path())) {
    testthat::skip("CT equivalency table not resolvable in this context")
  }
}

test_that("equivalency table resolves and is well-formed (883 pairs)", {
  # Deleting this test would let a truncated or mis-columned table through, and
  # the relabel would then silently no-op on the rows it cannot map.
  skip_if_no_table()
  map <- utils::read.csv(ct_equivalency_table_path(), colClasses = "character")
  expect_true(all(c("legacy_geoid", "new_geoid") %in% names(map)))
  expect_equal(nrow(map), 883L)
  expect_false(anyNA(map$legacy_geoid))
  expect_true(all(nchar(map$legacy_geoid) == 11L))
  expect_true(all(nchar(map$new_geoid) == 11L))
})

test_that("2022+ planning-region GEOIDs are relabeled to legacy county GEOIDs", {
  # THE CORE ASSERTION. Without the relabel these GEOIDs never match the access
  # surface and Connecticut vanishes from every stratum.
  skip_if_no_table()
  map <- utils::read.csv(ct_equivalency_table_path(), colClasses = "character")
  df  <- data.frame(GEOID = head(map$new_geoid, 5L), stringsAsFactors = FALSE)
  out <- suppressMessages(relabel_ct_geoids_safe(df, 2023))
  expect_identical(out$GEOID, head(map$legacy_geoid, 5L))
  expect_false(any(grepl("^091[1-9]0", out$GEOID)))
})

test_that("NEGATIVE CONTROL: non-Connecticut GEOIDs are never touched", {
  # If the relabel ever widened its pattern, this would catch it. A relabel that
  # rewrote, say, Massachusetts GEOIDs would corrupt a state that was fine.
  skip_if_no_table()
  df  <- data.frame(GEOID = c("25025010100", "36061010100", "06037101110"),
                    stringsAsFactors = FALSE)
  out <- suppressMessages(relabel_ct_geoids_safe(df, 2023))
  expect_identical(out$GEOID, df$GEOID)
})

test_that("NEGATIVE CONTROL: no-op before 2022 (legacy codes still valid)", {
  # Applying the relabel to pre-2022 data would corrupt years that were correct.
  skip_if_no_table()
  df <- data.frame(GEOID = c("09001010101", "09190010101"),
                   stringsAsFactors = FALSE)
  expect_identical(relabel_ct_geoids_safe(df, 2021)$GEOID, df$GEOID)
  expect_identical(relabel_ct_geoids_safe(df, 2013)$GEOID, df$GEOID)
})

test_that("idempotent: a second pass changes nothing", {
  # The denominator cache is relabeled on read, so this MUST hold or a cached
  # re-read would double-map.
  skip_if_no_table()
  map   <- utils::read.csv(ct_equivalency_table_path(), colClasses = "character")
  df    <- data.frame(GEOID = head(map$new_geoid, 20L), stringsAsFactors = FALSE)
  once  <- suppressMessages(relabel_ct_geoids_safe(df,   2023))
  twice <- suppressMessages(relabel_ct_geoids_safe(once, 2023))
  expect_identical(once$GEOID, twice$GEOID)
})

test_that("documented water tracts are kept, never relabeled", {
  skip_if_no_table()
  df  <- data.frame(GEOID = c("09180990100", "09190990000"),
                    stringsAsFactors = FALSE)
  out <- relabel_ct_geoids_safe(df, 2023)
  expect_identical(out$GEOID, df$GEOID)
})

test_that("FAIL-CLOSED on a planning-region GEOID with no equivalency entry", {
  # An ACS CT universe drift must stop the run, not silently drop the tract.
  skip_if_no_table()
  bad <- data.frame(GEOID = "09110999999", stringsAsFactors = FALSE)
  expect_error(suppressMessages(relabel_ct_geoids_safe(bad, 2023)),
               "no equivalency entry")
})

test_that("FAIL-CLOSED when the table is missing but CT new-codes are present", {
  df <- data.frame(GEOID = "09190010101", stringsAsFactors = FALSE)
  expect_error(
    suppressMessages(relabel_ct_geoids_safe(df, 2023,
                                            path = tempfile(fileext = ".csv"))),
    "equivalency table is missing")
})

test_that("sf geometry and row order survive the relabel", {
  # The reason this helper exists rather than a merge()/rbind() equivalency.
  skip_if_no_table()
  skip_if_not_installed("sf")
  map <- utils::read.csv(ct_equivalency_table_path(), colClasses = "character")
  pts <- sf::st_as_sf(
    data.frame(GEOID = head(map$new_geoid, 3L),
               x = c(-72.7, -72.8, -72.9), y = c(41.7, 41.8, 41.9),
               stringsAsFactors = FALSE),
    coords = c("x", "y"), crs = 4326)
  out <- suppressMessages(relabel_ct_geoids_safe(pts, 2023))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_identical(out$GEOID, head(map$legacy_geoid, 3L))
  expect_equal(sf::st_coordinates(out), sf::st_coordinates(pts))
})
