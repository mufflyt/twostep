#!/usr/bin/env Rscript

# -----------------------------------------------------------------------------
# ARCHIVED / LEGACY -- NOT part of the render (render.R) or test-execution path.
# Belongs to the older subspecialty/bivariate-map subsystem, preserved for
# provenance (see docs/SSOT_LEDGER.md, CRS-9311 entry) and intentionally
# renv-ignored (.renvignore). Some source() helpers it references are not
# vendored in this repo, so it will not run as-is; kept for reference only.
# -----------------------------------------------------------------------------

#' @title Calculate Subspecialty-Specific Accessibility with Age-Appropriate
#'   Denominators
#'
#' @description
#' Extends tract-level accessibility to subspecialty-specific analysis with
#' age-stratified population denominators. Uses clinically-appropriate age
#' cohorts for each subspecialty (e.g., reproductive age for REI/MFM,
#' older population for GO/FPMRS).
#'
#' @inheritParams shared_params_isochrones
#' @param census_tracts `sf`: with age-stratified population
#' @inheritParams shared_params_cohort
#' @param age_config `list`: from census_age_stratified.yml
#' @inheritParams shared_params_temporal
#' @param drive_time `numeric`: drive time in minutes
#' @return data frame with subspecialty-specific accessibility metrics
#' @export

# STEP49_R5F3_library-calls: bare library() calls violate project convention.
# Replace with requireNamespace() so this file is safe in callr subprocesses.
suppressPackageStartupMessages({
  requireNamespace("dplyr", quietly = TRUE)
  requireNamespace("sf",    quietly = TRUE)
  requireNamespace("here",  quietly = TRUE)
})

# NOTE (2026-08-09): this file previously ran
#     source(here::here("R", "isochrone_best_practices_helpers.R"))
# at package load time. That file is not in this repository, so R CMD INSTALL
# failed at lazy-load and the ENTIRE package -- all 53 exports -- was
# uninstallable because of this one function.
#
# A top-level source() is also wrong in package code regardless of whether the
# file exists: package functions must come from the namespace or from Imports,
# not be read off disk relative to a working directory that will not exist for
# an installed package.
#
# The three helpers it supplied -- calculate_area_weighted_allocation(),
# load_age_stratified_census() and resolve_path_from_config() -- live in
# mufflyt/isochrones (R/utils/area_weighted_allocation.R,
# R/load_age_stratified_census.R, R/path_resolver.R). They were never ported
# here, so this function has been non-functional since the file was copied in.
# The guard below makes that failure loud and specific at call time instead of
# breaking installation for everyone.

#' Calculate subspecialty accessibility by area overlap
#'
#' @description
#' Computes area-weighted population accessibility for
#' a given Otolaryngology subspecialty. Uses spatial intersection
#' of isochrone polygons with census tracts (Walker
#' 2023) to estimate the fraction of the target
#' population within driving distance of a provider.
#'
#' @details
#' - **Pipeline step**: Step 5 accessibility analysis
#' - **Inputs**: Isochrone sf, census tract sf, age
#'   config YAML, subspecialty name
#' - **Algorithm**: Filters isochrones by subspecialty
#'   and drive time, unions geometries, computes
#'   area-weighted overlap with census tracts using
#'   EPSG:9311 projection
#' - **Performance**: Dominated by st_intersection;
#'   scales with tract count
#' - **Reproducibility**: Deterministic given same
#'   spatial inputs and CRS
#' - **Failure modes**: Returns NULL if no isochrones
#'   found for subspecialty
#'
#' @param census_tracts sf. Census tract polygons
#'   with GEOID and population columns.
#' @inheritParams shared_params_cohort
#' @param age_config `list`: Age cohort configuration
#'   mapping subspecialties to population variables.
#' @inheritParams shared_params_temporal
#' @param drive_time `integer`: Drive time threshold
#'   in minutes (default 60).
#' @return Tibble with one row containing subspecialty,
#'   age_cohort, year, drive_time, population totals,
#'   percent_accessible with CI, and provider/tract
#'   counts. NULL if no matching isochrones.
#' @keywords internal
calculate_subspecialty_accessibility <- function(
  isochrones,
  census_tracts,
  subspecialty,
  age_config,
  year,
  drive_time = 60
) {

  # Fail loudly and specifically rather than with "could not find function".
  .needed <- c("calculate_area_weighted_allocation",
               "load_age_stratified_census",
               "resolve_path_from_config")
  .missing <- .needed[!vapply(.needed, exists, logical(1), mode = "function")]
  if (length(.missing)) {
    stop("calculate_subspecialty_accessibility() depends on helpers that were ",
         "never ported into twostep: ", paste(.missing, collapse = ", "), ".\n",
         "They live in mufflyt/isochrones (R/utils/area_weighted_allocation.R, ",
         "R/load_age_stratified_census.R, R/path_resolver.R). Port them into ",
         "this package, or use compute_e2sfca() / compute_band_tract_overlap(), ",
         "which are self-contained.", call. = FALSE)
  }

  cat(sprintf("[INFO] Calculating accessibility for %s (year %d, drive time %d min)\n",
              subspecialty, year, drive_time))

  # Filter isochrones to this subspecialty only
  subspec_isochrones <- isochrones %>%
    filter(subspecialty == !!subspecialty, drive_time_minutes == drive_time)

  if (nrow(subspec_isochrones) == 0) {
    cat(sprintf("[WARN] No isochrones found for subspecialty: %s at %d minutes\n",
                subspecialty, drive_time))
    return(NULL)
  }

  cat(sprintf("[INFO] Found %d isochrones for %s\n",
              nrow(subspec_isochrones), subspecialty))

  # Get age cohort for this subspecialty
  age_cohort <- age_config$subspecialty_age_mapping[[subspecialty]]$cohort

  cat(sprintf("[INFO] Using age cohort: %s\n", age_cohort))

  # Determine which population variable to use
  if (age_cohort == "pediatric_adolescent") {
    pop_var <- "female_0_21"
    pop_moe_var <- "female_0_21_moe"
  } else if (age_cohort == "reproductive_age") {
    pop_var <- "female_15_44"
    pop_moe_var <- "female_15_44_moe"
  } else if (age_cohort == "older_population") {
    pop_var <- "female_45_85plus"
    pop_moe_var <- "female_45_85plus_moe"
  } else {
    pop_var <- "female_15_85plus"
    pop_moe_var <- "female_15_85plus_moe"
  }

  # Ensure CRS match — use EPSG:9311 for accurate area calculations
  census_tracts <- st_transform(census_tracts, 9311)

  # Area-weighted accessibility (Walker 2023, §7.3-7.4)
  # Replaces centroid-based method which suffered from "centroid trap" —
  # large rural tracts scored 0% if their centroid fell outside the isochrone
  cat("[INFO] Calculating area-weighted accessibility (Walker 2023)...\n")

  # Fix invalid geometries before union to prevent TopologyException
  subspec_isochrones <- st_make_valid(subspec_isochrones)

  # Load safe_st_union if not already loaded
  if (!exists("safe_st_union", mode = "function")) {
    source(here::here("R", "safe_st_union.R"))
  }

  cat("[INFO] Creating isochrone union...\n")
  isochrone_union <- safe_st_union(
    subspec_isochrones,
    label = "Subspecialty accessibility union",
    verbose = TRUE
  )
  isochrone_union_sf <- sf::st_sf(geometry = isochrone_union)
  isochrone_union_sf <- st_transform(isochrone_union_sf, 9311)

  # Source the area-weighted allocation utility
  source(here::here("R", "utils", "area_weighted_allocation.R"))

  # Pre-calculate tract areas
  census_tracts$area_original_m2 <- as.numeric(sf::st_area(census_tracts))

  # Prepare population and population_moe columns for the utility interface
  census_tracts_prepped <- census_tracts %>%
    mutate(
      population = .data[[pop_var]],
      population_moe = .data[[pop_moe_var]]
    )

  # Calculate area-weighted overlap fractions
  cat("[INFO] Performing area-weighted spatial intersection...\n")
  overlap_result <- calculate_area_weighted_allocation(
    census_geographies = census_tracts_prepped,
    isochrones = isochrone_union_sf,
    area_col = "area_original_m2",
    min_overlap_threshold = 0.001,
    use_prefilter = TRUE,
    validate = TRUE,
    verbose = TRUE
  )

  # Join overlap fractions back to census data
  accessibility_results <- census_tracts %>%
    st_drop_geometry() %>%
    left_join(
      overlap_result %>% select(GEOID, overlap_fraction),
      by = "GEOID"
    ) %>%
    mutate(
      overlap_fraction = if_else(is.na(overlap_fraction), 0, overlap_fraction),
      has_access = as.integer(overlap_fraction >= 0.001),
      total_pop = .data[[pop_var]],
      total_pop_moe = .data[[pop_moe_var]],
      accessible_pop = overlap_fraction * .data[[pop_var]]
    )

  # Summarize
  cat("[INFO] Calculating summary statistics...\n")

  total_population <- sum(accessibility_results$total_pop, na.rm = TRUE)
  accessible_population <- sum(accessibility_results$accessible_pop, na.rm = TRUE)
  prop_accessible <- if (total_population > 0) {
    accessible_population / total_population
  } else {
    NA_real_
  }
  percent_accessible <- prop_accessible * 100

  # Calculate confidence interval for proportion
  # Using normal approximation for large samples
  se_prop <- if (!is.na(prop_accessible)) {
    sqrt(prop_accessible * (1 - prop_accessible) / total_population) * 100
  } else {
    NA_real_
  }

  summary <- tibble(
    subspecialty = subspecialty,
    age_cohort = age_cohort,
    year = year,
    drive_time = drive_time,
    total_population = total_population,
    accessible_population = accessible_population,
    percent_accessible = percent_accessible,
    percent_se = se_prop,
    # R57 BUG FIX (2026-05-23): max(0,...)/min(100,...) clips CI bounds, hiding
    # true uncertainty near 0% or 100% accessibility. Store raw bounds; callers
    # use coord_cartesian or explicit guards for display clipping. Normal approx
    # with 1.96 is appropriate here — n = total_population (millions).
    percent_ci_lower = percent_accessible - 1.96 * se_prop,
    percent_ci_upper = percent_accessible + 1.96 * se_prop,
    n_providers = n_distinct(subspec_isochrones$npi),
    n_isochrones = nrow(subspec_isochrones),
    n_tracts_total = nrow(accessibility_results),
    n_tracts_with_access = sum(accessibility_results$has_access, na.rm = TRUE)
  )

  cat(sprintf("[INFO] Results: %.1f%% accessibility (%s of %s)\n",
              percent_accessible,
              format(accessible_population, big.mark = ","),
              format(total_population, big.mark = ",")))
  cat(sprintf("[INFO] Providers: %d | Isochrones: %d\n",
              summary$n_providers, summary$n_isochrones))

  return(summary)
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# EXECUTION SECTION
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if (sys.nframe() == 0) {

  cat("=== Testing Subspecialty Accessibility Calculator ===\n\n")

  library(yaml)

  # Load configuration
  age_config <- yaml::read_yaml(here("config", "census_age_stratified.yml"))

  # Load test data
  cat("Loading isochrones...\n")
  isochrones <- readRDS(resolve_path_from_config("isochrone_cache.orchestrator_checkpoints.subspecialty_tagged_cache"))

  cat("Loading census data...\n")
  source(here("R", "load_age_stratified_census.R"))
  census_data <- load_age_stratified_census(year = 2023)

  # Test with MFM
  cat("\n=== Testing MFM ===\n")
  result_mfm <- calculate_subspecialty_accessibility(
    isochrones = isochrones,
    census_tracts = census_data,
    subspecialty = "MFM",
    age_config = age_config,
    year = 2023,
    drive_time = 60
  )

  print(result_mfm)

  cat("\n✅ Test complete\n")
}
