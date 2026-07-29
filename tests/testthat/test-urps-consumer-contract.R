# tests/testthat/test-urps-consumer-contract.R
# twostep's consumer contract with the mufflyaccess SSOT (v2.1 measure-by-year-
# by-geography API). twostep converts the canonical provider roster + population
# denominators into E2SFCA / accessibility measures; it VALIDATES provider totals
# against mufflyaccess::urps_count() but never REDEFINES them.
#
# Every call is fully explicit per the contract: year, measure, geography,
# pathway (include_urology), and incomplete-data policy.
#
# RED-FIRST, with the correct dependency semantics:
#   * Reconciliation + semantic tests are blocked on UPSTREAM (mufflyaccess must
#     ship urps_count()). They SKIP until the SSOT API exists, then go red until
#     twostep implements its provider-input loader. Guarded on the FUNCTION, not
#     the package: mufflyaccess may be installed (leftover) yet not expose the API.
#   * The provenance test is twostep's OWN responsibility, so it stays RED (no
#     skip) until run_twostep_accessibility() emits provenance columns.
library(testthat)

# TRUE only when the SSOT API is actually callable (installed AND exports urps_count).
.ssot_ready <- function() {
  requireNamespace("mufflyaccess", quietly = TRUE) &&
    exists("urps_count", where = asNamespace("mufflyaccess"), inherits = FALSE)
}

# the single canonical call twostep uses for its 2023 active national baseline
.urps_2023_active_national <- function() {
  mufflyaccess::urps_count(
    year = 2023L, measure = "board_certified_active",
    geography = "national", include_urology = TRUE, incomplete = "error")
}

# 1. Provider roster reconciles to the SSOT count.
test_that("twostep provider input reconciles with the mufflyaccess SSOT count", {
  skip_if_not(.ssot_ready(), "mufflyaccess::urps_count() not available yet")
  providers <- load_twostep_provider_input(
    specialty = "URPS", year = 2023L, include_urology = TRUE)
  expect_equal(dplyr::n_distinct(providers$provider_id),
               .urps_2023_active_national())
})

# 2. twostep preserves provider-release provenance (twostep-owned -> RED until done).
test_that("accessibility outputs retain provider-release provenance", {
  result <- run_twostep_accessibility(specialty = "URPS", year = 2023L)
  required_columns <- c(
    "provider_snapshot_version", "provider_source_sha256", "twostep_method_version")
  expect_true(all(required_columns %in% names(result)))
})

# 4. Accessibility supply totals reconcile before weighting (all active providers
#    enter the calculation), against the SSOT count (never a hardcoded literal).
test_that("all active providers enter the accessibility supply and reconcile to the SSOT", {
  skip_if_not(.ssot_ready(), "mufflyaccess::urps_count() not available yet")
  providers <- load_twostep_provider_input(
    specialty = "URPS", year = 2023L, include_urology = TRUE)
  supply <- prepare_provider_supply(providers)
  expect_setequal(unique(supply$provider_id), unique(providers$provider_id))
  expect_equal(dplyr::n_distinct(supply$provider_id), .urps_2023_active_national())
})

# 5. SEMANTIC GUARD: the 2023 active national count is 1332 and is NEVER 1339.
#    1339 is the 2025 roster_snapshot; treating it as the 2023 active count is the
#    exact confusion the measure/year distinction exists to prevent.
test_that("the 2023 active national count is 1332, not the 2025 snapshot (1339)", {
  skip_if_not(.ssot_ready(), "mufflyaccess::urps_count() not available yet")
  active_2023 <- .urps_2023_active_national()
  expect_equal(active_2023, 1332L)
  expect_false(identical(active_2023, 1339L))
  # CONUS is a distinct, smaller scope
  conus_2023 <- mufflyaccess::urps_count(
    year = 2023L, measure = "board_certified_active",
    geography = "conus", include_urology = TRUE, incomplete = "error")
  expect_equal(conus_2023, 1329L)
  expect_lt(conus_2023, active_2023)
})
