# tests/testthat/test-urps-consumer-contract.R
# INTEGRATION tests (not production dependencies) for twostep's future consumption
# of the mufflyaccess workforce SSOT under isochrones artifact CONTRACT 3.0.0.
# twostep does not currently consume a national URPS scalar; when it does, it will
# VALIDATE provider totals against mufflyaccess::urps_count() and never redefine
# them. Every call is fully explicit: year, measure, geography, pathway
# (include_urology), and incomplete-data behavior.
#
# These SKIP with a precise reason until mufflyaccess 0.7.0 (which serves contract
# 3.0.0) is installed and exposes urps_count(). None are left intentionally
# failing on main: twostep's own not-yet-built functions are gated behind exists()
# skips too, so this file contributes ZERO failures until the real API arrives.
#
# CONTRACT 3.0.0 current canonical cells (2023, board_certified_active, w/ urology):
#   national = 1306   CONUS = 1303   (reconciliation: 1027 ABOG + 279 ABU net-new)
# 1332 / 1329 are RETIRED v2.1.0 cells and must NEVER be returned as current.
library(testthat)

# TRUE only when the contract-3.0.0 API is actually callable: mufflyaccess >= 0.7.0
# installed AND exporting urps_count(). Guards on the function + version, not mere
# package presence (a leftover 0.1.x install exposes no urps_count()).
.ssot_v3_ready <- function() {
  requireNamespace("mufflyaccess", quietly = TRUE) &&
    utils::packageVersion("mufflyaccess") >= "0.7.0" &&
    exists("urps_count", where = asNamespace("mufflyaccess"), inherits = FALSE)
}
.skip_reason <- "requires mufflyaccess >= 0.7.0 exposing urps_count() (artifact contract 3.0.0)"

# the single canonical 2023 national active call twostep will use as its baseline
.urps_2023_active_national <- function() {
  mufflyaccess::urps_count(
    year = 2023L, measure = "board_certified_active",
    geography = "national", include_urology = TRUE, incomplete = "error")
}

# 1. Provider roster reconciles to the SSOT count (contract 3.0.0 national cell).
test_that("twostep provider input reconciles with the mufflyaccess SSOT count", {
  skip_if_not(.ssot_v3_ready(), .skip_reason)
  skip_if_not(exists("load_twostep_provider_input"),
              "load_twostep_provider_input() not implemented yet")
  providers <- load_twostep_provider_input(
    specialty = "URPS", year = 2023L, include_urology = TRUE)
  expect_equal(dplyr::n_distinct(providers$provider_id),
               as.integer(.urps_2023_active_national()))
})

# 2. twostep preserves provider-release provenance (twostep-owned; SKIP until the
#    accessibility pipeline exists -- a development TODO, never a failing test on main).
test_that("accessibility outputs retain provider-release provenance", {
  skip_if_not(exists("run_twostep_accessibility"),
              "run_twostep_accessibility() not implemented (twostep accessibility pipeline pending)")
  result <- run_twostep_accessibility(specialty = "URPS", year = 2023L)
  required_columns <- c(
    "provider_snapshot_version", "provider_source_sha256", "twostep_method_version")
  expect_true(all(required_columns %in% names(result)))
})

# 4. Accessibility supply totals reconcile before weighting, against the SSOT count.
test_that("all active providers enter the accessibility supply and reconcile to the SSOT", {
  skip_if_not(.ssot_v3_ready(), .skip_reason)
  skip_if_not(exists("load_twostep_provider_input") && exists("prepare_provider_supply"),
              "twostep provider-supply pipeline not implemented yet")
  providers <- load_twostep_provider_input(
    specialty = "URPS", year = 2023L, include_urology = TRUE)
  supply <- prepare_provider_supply(providers)
  expect_setequal(unique(supply$provider_id), unique(providers$provider_id))
  expect_equal(dplyr::n_distinct(supply$provider_id),
               as.integer(.urps_2023_active_national()))
})

# 5. SEMANTIC GUARD (contract 3.0.0): the current 2023 active national cell is 1306
#    and CONUS is 1303. The retired v2.1.0 cells 1332 / 1329 must NEVER be returned
#    as current. The 2025 roster snapshot is a distinct measure and is NOT asserted
#    here (its value is read from the contract, not hand-assumed).
test_that("current 2023 active cells are the contract 3.0.0 values, not the retired v2.1.0 cells", {
  skip_if_not(.ssot_v3_ready(), .skip_reason)
  national <- as.integer(.urps_2023_active_national())
  conus <- as.integer(mufflyaccess::urps_count(
    year = 2023L, measure = "board_certified_active",
    geography = "conus", include_urology = TRUE, incomplete = "error"))
  expect_equal(national, 1306L)
  expect_equal(conus, 1303L)
  expect_false(national %in% c(1332L, 1329L))   # retired v2.1.0, never current
  expect_false(conus    %in% c(1332L, 1329L))
  expect_lt(conus, national)                     # CONUS is the smaller scope
})
