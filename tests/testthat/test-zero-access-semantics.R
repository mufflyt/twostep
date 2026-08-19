# =============================================================================
# Zero-access: missing data must not be able to manufacture the finding
# =============================================================================
# Zero access is a COUNT OF ABSENCE, so the usual NA-to-zero convention is not a
# small bias here -- it is the answer. An earlier version of this code coerced
# NA to zero "matching the mean-access code", which would have inflated the
# headline zero-access share using incomplete surfaces. These tests exist so
# that cannot come back.
#
# The empirical basis for the semantics is recorded in ?zero_access_audit:
# compute_e2sfca_raster builds the surface DENSELY (values initialised to 0,
# rasterize with background = 0), so a cell outside every catchment holds an
# explicit 0 and NA means something upstream is incomplete.
suppressWarnings(suppressMessages(library(testthat)))
.root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION") | rprojroot::is_git_root)
source(file.path(.root, "R", "zero_access.R"))

skip_if_no_terra <- function() skip_if_not_installed("terra")
mk <- function(v) { r <- terra::rast(nrows = 1, ncols = length(v)); terra::values(r) <- v; r }

test_that("zero access is population-weighted, not cell-counted", {
  skip_if_no_terra()
  # Two of four cells are zero-access but hold 100 of 1000 people: 10 percent,
  # NOT the 50 percent a cell count would report.
  expect_equal(zshare_rast(mk(c(0, 0, 0.5, 0.9)), mk(c(50, 50, 400, 500))), 10)
  expect_equal(zshare_rast(mk(c(0, 0)), mk(c(10, 90))), 100)
  expect_equal(zshare_rast(mk(c(1, 2)), mk(c(10, 90))), 0)
})

test_that("an explicit zero is a measurement and is counted", {
  skip_if_no_terra()
  # This is the case the whole estimand exists for: access computed and equal to
  # zero. It must be counted, and must not be confused with the NA case below.
  expect_equal(zshare_rast(mk(c(0, 1, 1)), mk(c(250, 250, 500))), 25)
})

test_that("NA access is an incomplete surface, NOT zero access", {
  skip_if_no_terra()
  # The defect this file exists to prevent. Returning a number here would
  # inflate the reported zero-access share out of missing data.
  expect_error(zshare_rast(mk(c(NA, 1)), mk(c(25, 75))), "NO evaluable accessibility")
  expect_error(zshare_rast(mk(c(NA, 1)), mk(c(25, 75))), "not zero access")
  # and it says HOW MUCH population is unresolved, not merely that something failed
  expect_error(zshare_rast(mk(c(NA, NA, 1)), mk(c(10, 10, 80))), "20 of 100")
})

test_that("a missing population key is excluded, never counted as zero access", {
  skip_if_no_terra()
  # NA weight = no eligible population here. It must not enter the numerator as
  # if it were a zero-access person, nor the denominator.
  expect_equal(zshare_rast(mk(c(0, 1)), mk(c(NA, 100))), 0)
  au <- zero_access_audit(mk(c(0, 1)), mk(c(NA, 100)))
  expect_equal(au$excluded_population, 0)   # NA weights sum to 0 under na.rm
  expect_equal(au$eligible_population, 100)
})

test_that("the coverage audit reports the denominator honestly", {
  skip_if_no_terra()
  au <- zero_access_audit(mk(c(0, 1, NA)), mk(c(100, 300, 600)))
  expect_equal(au$eligible_population, 1000)
  expect_equal(au$evaluable_population, 400)
  expect_equal(au$unresolved_population, 600)
  expect_equal(au$zero_access_population, 100)
  expect_equal(au$pct_evaluable, 40)
  # The share is WITHHELD while population is unresolved: no plausible-looking
  # number computed over a silently shrunken denominator.
  expect_true(is.na(au$zero_share))
})

test_that("reporting over an incomplete denominator requires an explicit tolerance", {
  skip_if_no_terra()
  # Only when a tolerance is declared by name is a share returned, and then it is
  # explicitly over EVALUABLE population: 100 of 400, not 100 of 1000.
  expect_equal(zshare_rast(mk(c(0, 1, NA)), mk(c(100, 300, 600)), tol_unresolved = 600), 25)
  # one unit short of the needed tolerance still refuses
  expect_error(zshare_rast(mk(c(0, 1, NA)), mk(c(100, 300, 600)), tol_unresolved = 599))
})

test_that("no population yields NA rather than a fabricated zero", {
  skip_if_no_terra()
  expect_true(is.na(zshare_rast(mk(c(0, 1)), mk(c(0, 0)))))
})

test_that("zero access is invariant to rescaling POSITIVE access", {
  skip_if_no_terra()
  # The support (who is at exactly zero) is geometric. Multiplying every positive
  # value by 1000 changes every mean and no zero-access share. This is the
  # property behind the multiverse's support classification: specifications that
  # only rescale positive weights cannot move this estimand at all.
  w <- mk(c(100, 300, 600))
  expect_equal(zshare_rast(mk(c(0, 0.5, 2) * 1000), w), zshare_rast(mk(c(0, 0.5, 2)), w))
})

test_that("a failed provider surface cannot masquerade as zero access", {
  skip_if_no_terra()
  # An entirely NA surface is a total routing/processing failure. It must error,
  # not report 100 percent zero access -- which would look like a dramatic
  # scientific finding.
  expect_error(zshare_rast(mk(c(NA, NA, NA)), mk(c(100, 100, 100))), "NO evaluable")
})
