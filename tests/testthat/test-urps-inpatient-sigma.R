source(file.path(rprojroot::find_root(rprojroot::has_file("DESCRIPTION") |
                                        rprojroot::is_git_root),
                 "R", "urps_inpatient_sigma.R"))

test_that("urps_inpatient_band_weights defaults to the CHIA-calibrated bandwidth", {
  w <- urps_inpatient_band_weights()
  expect_equal(names(w), c("30", "60", "120", "180"))
  expect_true(all(is.finite(w)))
  expect_true(all(w >= 0 & w <= 1))
  expect_true(all(diff(w) <= 0))
  expect_equal(round(as.numeric(w), 4), c(1.0000, 0.4479, 0.0180, 0.0001))  # snapshot
})

test_that("urps_inpatient_band_weights wraps gaussian_band_weights at sigma_minutes", {
  w   <- urps_inpatient_band_weights(sigma_minutes = 60)
  ref <- gaussian_band_weights(c(30L, 60L, 120L, 180L), sigma = 60)
  expect_equal(as.numeric(w), as.numeric(ref), tolerance = 1e-12)
})

test_that("urps_inpatient_band_weights records CHIA calibration metadata", {
  w    <- urps_inpatient_band_weights()
  meta <- attr(w, "decay_meta")
  expect_equal(meta$sigma_minutes, URPS_INPATIENT_SIGMA_MINUTES)
  expect_equal(meta$sigma_miles, URPS_INPATIENT_SIGMA_MILES)
  expect_equal(meta$sigma_source, "CHIA MA inpatient urogyn surgery, FY2007-2018")
  expect_equal(meta$minutes_calibration, "MA road-network isochrones, FPMRS/urology")
  expect_equal(meta$calibration_tier, "observed_regional")
})

test_that("urps_inpatient_band_weights rejects a non-positive sigma", {
  expect_error(urps_inpatient_band_weights(sigma_minutes = 0), "sigma_minutes")
  expect_error(urps_inpatient_band_weights(sigma_minutes = -5), "sigma_minutes")
})

test_that("the calibration constants are the documented, measured values", {
  expect_equal(URPS_INPATIENT_SIGMA_MILES, 22.7)
  expect_equal(URPS_INPATIENT_SIGMA_MINUTES, 41)
  expect_equal(MA_ROAD_NETWORK_RADIUS_MILES,
               c("30" = 15.6, "60" = 35.7, "120" = 70.1, "180" = 101.8))
  expect_equal(URPS_INPATIENT_SIGMA_BY_AVAILABILITY,
               c("5" = 5.0, "10" = 22.1, "25" = 27.4, "999" = 108.7))
  expect_equal(URPS_INPATIENT_SIGMA_BY_AVAILABILITY_MIN,
               c("5" = 10, "10" = 40, "25" = 50, "999" = 185))
  # Availability is the substantive claim of these two vectors: a hospital
  # farther away implies a wider (never narrower) calibrated bandwidth.
  expect_true(all(diff(URPS_INPATIENT_SIGMA_BY_AVAILABILITY) >= 0))
  expect_true(all(diff(URPS_INPATIENT_SIGMA_BY_AVAILABILITY_MIN) >= 0))
})
