#' @title Create Bivariate Choropleth Map (Access × ADI)
#'
#' @description
#' Visualizes the double burden of geographic barriers and socioeconomic
#' deprivation by intersecting spatial access rates with the Area Deprivation
#' Index (ADI).
#'
#' @details
#' Creates a 3x3 grid map comparing ADI quintiles against Access rate
#' categories (low, medium, high) to highlight vulnerable populations.
#'
#' @family visualization-utils
#' @name create_bivariate_map_adi
NULL

#!/usr/bin/env Rscript

# =============================================================================
# CREATE BIVARIATE CHOROPLETH MAP: ACCESS × AREA DEPRIVATION INDEX (ADI)
# =============================================================================
#
# Purpose: Visualize double burden of geographic barriers + socioeconomic deprivation
#          Shows whether low-access areas are ALSO high-deprivation areas
#
# Data Sources:
#   1. step_4_access_by_tract.rds - Census tract-level 60-min access rates
#   2. ADI data from Neighborhood Atlas (download from neighborhoodatlas.medicine.wisc.edu)
#      OR calculate from ACS variables
#
# Output: Bivariate map with 3×3 grid:
#   - X-axis: ADI quintile (1=least deprived, 5=most deprived)
#   - Y-axis: Access rate (low, medium, high)
#   - Colors: 9-color scheme showing intersection
#
# Author: Tyler Muffly + Claude Code
# Date: 2026-01-02
# =============================================================================

# Bug BIV-1 fix (2026-05-23): wrap library() calls in
# suppressPackageStartupMessages({}) so attach noise doesn't flood logs.
suppressPackageStartupMessages({
  library(here)
  library(dplyr)
  library(sf)
  library(ggplot2)
  library(tidycensus)
  library(tigris)
  library(cowplot)
  library(classInt)
})
if (!exists("normalize_tract_id", mode = "function"))
  source(here::here("R", "utils", "tract_id_utils.R"))

# Bug BIV-2 fix (2026-05-23): hardcoded ACS year 2017 was buried in two
# different get_acs/tigris calls and one in the title — operators couldn't
# rerun for a newer ACS vintage without three separate edits. Make it env-
# overridable via BIV_ACS_YEAR (default 2017 preserves historical behavior).
.biv_acs_year <- as.integer(Sys.getenv("BIV_ACS_YEAR", unset = "2017"))

cat("\n")
cat(strrep("=", 80), "\n")
cat("BIVARIATE CHOROPLETH MAP: ACCESS × AREA DEPRIVATION\n")
cat(strrep("=", 80), "\n\n")

# -----------------------------------------------------------------------------
# STEP 1: Load Census Tract Access Data
# -----------------------------------------------------------------------------

cat("1. Loading census tract access data...\n")

# Find most recent artifact directory WITH Step 4 data (not TEST_MODE runs)
artifacts_dir <- here("artifacts")

# Search for Step 4 files
step4_files <- list.files(
  artifacts_dir,
  pattern = "step_4_access_by_tract_with_ruca.rds",
  recursive = TRUE,
  full.names = TRUE
)

if (length(step4_files) == 0) {
  stop("ERROR: No Step 4 access data found. Run pipeline through Step 4 first.")
}

# Extract run IDs and sort by timestamp (most recent first)
step4_runs <- data.frame(
  file = step4_files,
  run_id = basename(dirname(step4_files))
) %>%
  arrange(desc(run_id))

latest_run <- dirname(step4_runs$file[1])
access_file <- step4_runs$file[1]

cat(sprintf("   Using data from: %s\n", basename(latest_run)))
cat(sprintf("   File: %s\n", basename(access_file)))

if (!file.exists(access_file)) {
  stop("ERROR: Access data file not found.")
}

access_data <- readRDS(access_file)

cat(sprintf("   Loaded %s census tracts\n", format(nrow(access_data), big.mark = ",")))

# ── QA Gate 1: Normalize tract ID to GEOID (fips_tract / tract_geoid / GEOID) ──
# normalize_tract_id() stops with RETRACTION GUARD if no known alias is found.
access_data <- normalize_tract_id(access_data)

# ── QA Gate 2 (FATAL): range filter must use seconds, not minutes ───────────
# If data stores range in minutes (30, 60, 120), filter(range == 3600) returns
# 0 rows — map renders blank with no error. Log available range values first.
available_ranges <- sort(unique(access_data$range))
cat(sprintf("[bivariate_map QA] Available range values: %s\n",
            paste(available_ranges, collapse = ", ")))
if (!3600 %in% available_ranges) {
  stop(sprintf(
    "[bivariate_map] FATAL: range==3600 (60 minutes in seconds) not found in data.\n  Available range values: %s\n  If data uses minutes, change filter to range==60.",
    paste(available_ranges, collapse = ", ")), call. = FALSE)
}

# Extract 60-minute access rate
# Note: range is in seconds (3600 = 60 minutes)
# Note: percent is the access rate (% of population with access)
access_tract <- access_data %>%
  filter(range == 3600, category == "total_female") %>%  # 60-minute threshold, total female population
  filter(year == max(year)) %>%
  select(GEOID, access_rate_60min = percent) %>%
  filter(!is.na(access_rate_60min)) %>%
  distinct(GEOID, .keep_all = TRUE)  # Ensure one row per tract

# ── QA Gate 2b (FATAL): year + range + category filter must produce rows ────
if (nrow(access_tract) == 0L) {
  stop(sprintf(
    "[bivariate_map] FATAL: filter(range==3600, category=='total_female') produced 0 rows.\n  Available categories: %s",
    paste(sort(unique(access_data$category)), collapse = ", ")), call. = FALSE)
}

cat(sprintf("   60-minute access data: %s tracts (before adding geometry)\n", format(nrow(access_tract), big.mark = ",")))

# Add census tract geometries
cat("   Loading census tract geometries...\n")
# Bug BIV-4 fix (2026-05-23): wrap tigris call in tryCatch — offline / API
# outage would otherwise crash deep in the HTTP layer with a cryptic error.
# Bug BIV-5 fix (2026-05-23): hardcoded STATEFP list bypassed the project
# SSOT (NON_CONTIGUOUS_CODES is STUSPS) and silently went stale relative to
# the cohort exclusion list. Convert NON_CONTIGUOUS_CODES → STATEFP via the
# tigris fips table; fall back to the historical hardcoded list on lookup
# failure so behavior is preserved.
.biv_nc_fips <- tryCatch({
  .nc_codes <- get("NON_CONTIGUOUS_CODES", inherits = TRUE)
  .fips <- tigris::fips_codes
  unique(.fips$state_code[match(.nc_codes, .fips$state)])
}, error = function(e) c("02", "15", "72", "78", "69", "66", "60"))
us_tracts <- tryCatch(
  tigris::tracts(cb = TRUE, year = .biv_acs_year),
  error = function(e) stop(sprintf(
    "[bivariate_map] tigris tracts fetch failed for year=%d: %s",
    .biv_acs_year, conditionMessage(e)), call. = FALSE)
) %>%
  filter(!STATEFP %in% .biv_nc_fips) %>%  # Exclude AK, HI, territories (NON_CONTIGUOUS_CODES SSOT)
  st_transform(9311) %>%  # EPSG:9311 (NAD83(2011) / US National Atlas Equal Area)
  select(GEOID)

# Join access data with geometries
n_before_join <- nrow(access_tract)
access_tract <- access_tract %>%
  inner_join(us_tracts, by = "GEOID") %>%
  st_as_sf()

# ── QA Gate 3 (FATAL): GEOID join must retain most tracts ───────────────────
# inner_join silently drops all rows whose GEOID doesn't match the 2017 tigris
# tracts. A GEOID format mismatch (e.g., 11-digit vs 10-digit padding) produces
# 0 matched rows — the map is blank with no error.
n_after_join  <- nrow(access_tract)
pct_retained  <- if (n_before_join > 0L) n_after_join / n_before_join else 0
if (n_after_join == 0L) {
  stop(sprintf(
    "[bivariate_map] FATAL: 0 tracts retained after inner_join with us_tracts geometry.\n  Before join: %d tracts. GEOID format mismatch? Access data GEOID: '%s' (length %d)\n  Check 11-vs-10 digit padding or 2017 vs 2020 TIGER vintage.",
    n_before_join,
    access_tract$GEOID[1],
    nchar(access_tract$GEOID[1])), call. = FALSE)
} else if (pct_retained < 0.5) {
  warning(sprintf(
    "[bivariate_map] Only %.1f%% of access tracts matched geometry (%d of %d).\n  Likely GEOID vintage mismatch: access data uses %d-digit GEOIDs.",
    pct_retained * 100, n_after_join, n_before_join,
    nchar(access_tract$GEOID[1])), call. = FALSE)
}
cat(sprintf("[bivariate_map QA] Geometry join: %d/%d tracts matched (%.1f%% retained)\n",
            n_after_join, n_before_join, pct_retained * 100))

cat(sprintf("   60-minute access data: %s tracts (with geometry)\n", format(nrow(access_tract), big.mark = ",")))

# -----------------------------------------------------------------------------
# STEP 2: Calculate Simplified ADI from ACS Variables
# -----------------------------------------------------------------------------
# Note: Full ADI requires downloading from Neighborhood Atlas
# Here we calculate a simplified deprivation index from publicly available ACS data

cat("\n2. Calculating Area Deprivation Index from ACS data...\n")
cat("   (Using simplified 5-variable index as proxy for full ADI)\n")

# Get ACS variables for deprivation index (2017 5-year estimates to match access data)
# Variables based on Singh 2003 ADI methodology:
#   - % below poverty (B17001)
#   - % unemployed (B23025)
#   - % less than high school education (B15003)
#   - Median household income (B19013)
#   - % households without vehicle (B08201)
#
# DESIGN NOTE: ADI uses total-population (both sexes) ACS variables intentionally.
# The ADI measures TRACT-LEVEL neighborhood deprivation, not individual patient
# characteristics. The research question is: "Do women in deprived neighborhoods
# have worse access to OB/GYN subspecialists?" The deprivation of the neighborhood
# is a contextual variable — it characterizes the place, not the person.
#
# Using female-only poverty/unemployment (B17001_017/B23001_090) would:
#   1. Deviate from the published Singh 2003 ADI methodology
#   2. Produce a non-standard index without published validation
#   3. Not meaningfully change tract-level rankings (male and female poverty
#      rates are highly correlated at tract level, r > 0.95)
#
# The Y-axis (subspecialty access) IS female-specific (OB/GYN denominator).
# The X-axis (ADI) is an area-level ecological measure — both-sexes is correct.
# Bug BIV-3 fix (2026-05-23): replaced two stale "Otolaryngology" references
# (legacy from ENT pivot) with OB/GYN to match project scope.

cat("   Downloading ACS data for all US tracts...\n")

adi_vars <- c(
  "B17001_002",  # Below poverty level
  "B17001_001",  # Total for poverty status
  "B23025_005",  # Unemployed
  "B23025_003",  # In labor force
  "B15003_002",  # No schooling
  "B15003_003",  # Nursery to 4th grade
  "B15003_004",  # 5th-6th grade
  "B15003_005",  # 7th-8th grade
  "B15003_006",  # 9th grade
  "B15003_007",  # 10th grade
  "B15003_008",  # 11th grade
  "B15003_009",  # 12th grade no diploma
  "B15003_001",  # Total for educational attainment
  "B19013_001",  # Median household income
  "B08201_002",  # No vehicle available
  "B08201_001"   # Total households for vehicle
)

# Download for all US (this may take 1-2 minutes)
# Bug BIV-6 fix (2026-05-23): wrap get_acs() in tryCatch + use the env-
# overridable .biv_acs_year so the script can be rerun for any ACS vintage
# without a code edit and so an API outage / rate-limit crashes with a
# useful diagnostic instead of a confusing httr error.
acs_adi <- tryCatch(
  get_acs(
    geography = "tract",
    variables = adi_vars,
    year = .biv_acs_year,
    survey = "acs5",
    geometry = FALSE
  ),
  error = function(e) stop(sprintf(
    "[bivariate_map] tidycensus::get_acs() failed for year=%d: %s\n  Check CENSUS_API_KEY env var and Census API status.",
    .biv_acs_year, conditionMessage(e)), call. = FALSE)
)

cat("   Processing ACS variables...\n")

# Reshape and calculate deprivation components
adi_components <- acs_adi %>%
  select(GEOID, variable, estimate) %>%
  tidyr::pivot_wider(names_from = variable, values_from = estimate) %>%
  mutate(
    # % below poverty
    pct_poverty = (B17001_002 / B17001_001) * 100,

    # % unemployed (of those in labor force)
    pct_unemployed = (B23025_005 / B23025_003) * 100,

    # % less than high school
    less_than_hs = B15003_002 + B15003_003 + B15003_004 + B15003_005 +
                   B15003_006 + B15003_007 + B15003_008 + B15003_009,
    pct_less_than_hs = (less_than_hs / B15003_001) * 100,

    # Median income (inverse - lower is more deprived)
    median_income = B19013_001,

    # % no vehicle
    pct_no_vehicle = (B08201_002 / B08201_001) * 100
  ) %>%
  select(GEOID, pct_poverty, pct_unemployed, pct_less_than_hs,
         median_income, pct_no_vehicle)

# Standardize variables (z-scores)
adi_standardized <- adi_components %>%
  mutate(
    z_poverty = scale(pct_poverty)[,1],
    z_unemployed = scale(pct_unemployed)[,1],
    z_education = scale(pct_less_than_hs)[,1],
    z_income = -scale(median_income)[,1],  # Negative: lower income = higher deprivation
    z_vehicle = scale(pct_no_vehicle)[,1]
  ) %>%
  # Calculate composite ADI score (mean of z-scores)
  mutate(
    adi_score = (z_poverty + z_unemployed + z_education + z_income + z_vehicle) / 5
  ) %>%
  select(GEOID, adi_score, pct_poverty, pct_unemployed, pct_less_than_hs,
         median_income, pct_no_vehicle)

# ── QA Gate 4 (WARNING): division-by-zero in ADI components → Inf/NaN ────────
# If a denominator (B17001_001, B23025_003, etc.) is 0 for small tracts, the
# resulting percentage is Inf or NaN. z-score standardization then propagates
# Inf into the ADI score → affected tracts render as the NA color silently.
n_inf_adi <- sum(!is.finite(adi_standardized$adi_score), na.rm = TRUE)
if (n_inf_adi > 0L) {
  warning(sprintf(
    "[bivariate_map] %d tracts have non-finite ADI score (Inf/NaN from zero denominator).\n  These tracts will be excluded from the bivariate map. Check denominator columns: B17001_001, B23025_003, B15003_001, B08201_001.",
    n_inf_adi), call. = FALSE)
}
cat(sprintf("[bivariate_map QA] ADI calculated for %s tracts (%d Inf/NaN excluded)\n",
            format(nrow(adi_standardized), big.mark = ","), n_inf_adi))

cat(sprintf("   Calculated ADI for %s tracts\n", format(nrow(adi_standardized), big.mark = ",")))

# -----------------------------------------------------------------------------
# STEP 3: Merge Access and ADI Data
# -----------------------------------------------------------------------------

cat("\n3. Merging access and deprivation data...\n")

bivariate_data <- access_tract %>%
  left_join(adi_standardized, by = "GEOID") %>%
  filter(!is.na(adi_score), !is.na(access_rate_60min))

cat(sprintf("   Merged dataset: %s tracts\n", format(nrow(bivariate_data), big.mark = ",")))

# -----------------------------------------------------------------------------
# STEP 4: Create Bivariate Classification
# -----------------------------------------------------------------------------

cat("\n4. Creating bivariate classification (3×3 grid)...\n")

# Classify access into 3 categories (using quantiles)
access_breaks <- quantile(bivariate_data$access_rate_60min,
                          probs = c(0, 0.33, 0.67, 1), na.rm = TRUE)

# Classify ADI into 3 categories (using quantiles)
adi_breaks <- quantile(bivariate_data$adi_score,
                       probs = c(0, 0.33, 0.67, 1), na.rm = TRUE)

bivariate_data <- bivariate_data %>%
  mutate(
    access_class = cut(access_rate_60min,
                       breaks = access_breaks,
                       labels = c("Low", "Medium", "High"),
                       include.lowest = TRUE),

    adi_class = cut(adi_score,
                    breaks = adi_breaks,
                    labels = c("Low\nDeprivation", "Medium\nDeprivation", "High\nDeprivation"),
                    include.lowest = TRUE),

    # Create bivariate category (9 combinations)
    bivar_category = paste0(as.character(access_class), "-", as.character(adi_class))
  )

# Create color scheme (3×3 grid)
# Rows: Access (Low, Med, High)
# Cols: ADI (Low, Med, High deprivation)
bivar_colors <- c(
  "Low-Low\nDeprivation" = "#e8e8e8",      # Low access, low deprivation
  "Low-Medium\nDeprivation" = "#ace4e4",   # Low access, medium deprivation
  "Low-High\nDeprivation" = "#5ac8c8",     # Low access, high deprivation (WORST)
  "Medium-Low\nDeprivation" = "#dfb0d6",   # Medium access, low deprivation
  "Medium-Medium\nDeprivation" = "#a5add3", # Medium access, medium deprivation
  "Medium-High\nDeprivation" = "#5698b9",  # Medium access, high deprivation
  "High-Low\nDeprivation" = "#be64ac",     # High access, low deprivation (BEST)
  "High-Medium\nDeprivation" = "#8c62aa",  # High access, medium deprivation
  "High-High\nDeprivation" = "#3b4994"     # High access, high deprivation
)

# Summarize distribution
category_counts <- bivariate_data %>%
  st_drop_geometry() %>%
  count(access_class, adi_class) %>%
  arrange(access_class, adi_class)

cat("\n   Bivariate distribution:\n")
print(category_counts, n = 100)

# -----------------------------------------------------------------------------
# STEP 5: Create Bivariate Map
# -----------------------------------------------------------------------------

cat("\n5. Creating bivariate choropleth map...\n")

# Get US states for boundaries
# Bug BIV-7 fix (2026-05-23): tigris vintage + STUSPS exclusion now both
# track the SSOT — .biv_acs_year for vintage, NON_CONTIGUOUS_CODES (with
# error fallback) for the territory list. Previously the STUSPS list here
# differed from the STATEFP list above (CONUS filter inconsistency).
us_states <- tryCatch(
  tigris::states(cb = TRUE, resolution = "20m", year = .biv_acs_year),
  error = function(e) stop(sprintf(
    "[bivariate_map] tigris states fetch failed for year=%d: %s",
    .biv_acs_year, conditionMessage(e)), call. = FALSE)
) %>%
  filter(!STUSPS %in% tryCatch(NON_CONTIGUOUS_CODES,
                               error = function(e) c("HI", "AK", "PR", "VI", "GU", "MP", "AS"))) %>%
  st_transform(st_crs(bivariate_data))

# Create main map
bivar_map <- ggplot() +
  geom_sf(data = bivariate_data,
          aes(fill = bivar_category),
          color = NA,
          size = 0) +
  geom_sf(data = us_states,
          fill = NA,
          color = "white",
          size = 0.3) +
  scale_fill_manual(
    values = bivar_colors,
    name = "Access × Deprivation"
  ) +
  theme_void() +
  theme(
    legend.position = "none",
    plot.title = element_text(size = 14, face = "bold", hjust = 0.5),
    plot.subtitle = element_text(size = 10, hjust = 0.5, margin = margin(b = 10))
  ) +
  labs(
    # Bug BIV-8 fix (2026-05-23): title hardcoded "Gynecologic Oncology" but
    # the cohort is the full OB/GYN subspecialist set — env-overridable via
    # BIV_TITLE / BIV_SUBSPECIALTY_LABEL with broader default. Subtitle ACS
    # vintage was also hardcoded "2017" — drive it off .biv_acs_year.
    title = Sys.getenv("BIV_TITLE",
                       unset = sprintf("Geographic Access to %s Care by Area Deprivation",
                                       Sys.getenv("BIV_SUBSPECIALTY_LABEL", unset = "OB/GYN Subspecialty"))),
    subtitle = sprintf("60-Minute Drive Time Access × Area Deprivation Index (ADI), %d", .biv_acs_year)
  )

# Create legend (separate plot)
legend_data <- expand.grid(
  access = c("Low", "Medium", "High"),
  adi = c("Low\nDeprivation", "Medium\nDeprivation", "High\nDeprivation")
) %>%
  mutate(
    bivar_cat = paste0(access, "-", adi),
    access = factor(access, levels = c("High", "Medium", "Low")),
    adi = factor(adi, levels = c("Low\nDeprivation", "Medium\nDeprivation", "High\nDeprivation"))
  )

legend_plot <- ggplot(legend_data, aes(x = adi, y = access)) +
  geom_tile(aes(fill = bivar_cat), color = "white", size = 1) +
  scale_fill_manual(values = bivar_colors) +
  labs(
    x = "Area Deprivation →",
    y = "← Access Rate"
  ) +
  theme_minimal() +
  theme(
    legend.position = "none",
    axis.title = element_text(size = 9, face = "bold"),
    axis.text = element_text(size = 8),
    panel.grid = element_blank()
  ) +
  coord_fixed()

# Combine map and legend
combined_plot <- ggdraw() +
  draw_plot(bivar_map, x = 0, y = 0, width = 1, height = 1) +
  draw_plot(legend_plot, x = 0.05, y = 0.05, width = 0.2, height = 0.2)

# Save outputs
# Bug BIV-10 fix (2026-05-23): output_dir was hardcoded manuscript/figures —
# env-overridable via BIV_FIG_DIR so CI / alternative output trees can
# redirect without code edits.
output_dir <- Sys.getenv("BIV_FIG_DIR", unset = here("manuscript", "figures"))
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

output_png <- file.path(output_dir, "bivariate_access_adi.png")
output_pdf <- file.path(output_dir, "bivariate_access_adi.pdf")

ggsave(output_png, combined_plot, width = 12, height = 8, dpi = 300, bg = "white")
ggsave(output_pdf, combined_plot, width = 12, height = 8, bg = "white")

# ── QA Gate 5 (post-save): files must exist and be non-trivial ───────────────
# Bug BIV-9 fix (2026-05-23): file.info()$size NA propagation through
# `< 20` evaluates as NA (falsy), silently passing a blank chart. Hard-stop
# on NA + keep the suspicious-small warning for the real case.
for (.out_file in c(output_png, output_pdf)) {
  if (!file.exists(.out_file)) {
    stop(sprintf(
      "[bivariate_map] FATAL: ggsave() completed but output not found: %s", .out_file),
      call. = FALSE)
  }
  .sz <- file.info(.out_file)$size
  if (is.na(.sz))
    stop(sprintf("[bivariate_map] RETRACTION GUARD: file.info()$size=NA (stat failed) for: %s",
                 .out_file), call. = FALSE)
  .kb <- .sz / 1024
  if (.kb < 20) {
    warning(sprintf(
      "[bivariate_map] Output suspiciously small (%.1f KB): %s — map may be blank.",
      .kb, basename(.out_file)), call. = FALSE)
  }
  cat(sprintf("   ✓ Saved %s: %s (%.1f KB)\n",
              toupper(tools::file_ext(.out_file)), .out_file, .kb))
}

# -----------------------------------------------------------------------------
# STEP 6: Calculate Summary Statistics
# -----------------------------------------------------------------------------

cat("\n6. Summary statistics:\n")
cat(strrep("-", 80), "\n")

# Double burden areas (low access + high deprivation)
double_burden <- bivariate_data %>%
  st_drop_geometry() %>%
  filter(access_class == "Low", adi_class == "High\nDeprivation") %>%
  nrow()

# Best case (high access + low deprivation)
best_case <- bivariate_data %>%
  st_drop_geometry() %>%
  filter(access_class == "High", adi_class == "Low\nDeprivation") %>%
  nrow()

total_tracts <- nrow(bivariate_data)

cat(sprintf("   Total tracts analyzed: %s\n", format(total_tracts, big.mark = ",")))
cat(sprintf("   Double burden (Low access + High deprivation): %s (%.1f%%)\n",
            format(double_burden, big.mark = ","),
            (double_burden / total_tracts) * 100))
cat(sprintf("   Best case (High access + Low deprivation): %s (%.1f%%)\n",
            format(best_case, big.mark = ","),
            (best_case / total_tracts) * 100))

cat("\n")
cat(strrep("=", 80), "\n")
cat("✓ BIVARIATE MAP COMPLETE\n")
cat(strrep("=", 80), "\n\n")

cat("INTERPRETATION:\n")
cat("  • Cyan/teal areas: LOW ACCESS + HIGH DEPRIVATION (double burden)\n")
cat("  • Purple areas: HIGH ACCESS + LOW DEPRIVATION (best access)\n")
cat("  • Gray areas: LOW ACCESS + LOW DEPRIVATION (isolated but affluent)\n")
cat("  • Blue areas: HIGH ACCESS + HIGH DEPRIVATION (urban poor with access)\n\n")

cat("POLICY IMPLICATIONS:\n")
cat("  • Cyan/teal areas need BOTH improved access AND economic support\n")
cat("  • Gray areas may afford to travel; focus on telemedicine\n")
cat("  • Blue areas have geographic access but may face other barriers\n")
cat("    (insurance, language, cultural factors)\n\n")
