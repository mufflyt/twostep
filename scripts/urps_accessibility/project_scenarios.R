#!/usr/bin/env Rscript
# =============================================================================
# Accessibility under URPS workforce-projection scenarios -- real E2SFCA adapter
#
# Wires the deterministic scenario layer (R/urps_accessibility_scenarios.R) to
# the production vector E2SFCA engine (compute_e2sfca). This is the runnable
# end-to-end path; it needs the geospatial INPUTS that are produced upstream by
# the isochrones pipeline and are NOT committed in this repo:
#
#   * overlap        tibble(coord_id, band, GEOID, overlap_fraction)
#                    -- from compute_band_tract_overlap(iso_sf, tracts_sf); it is
#                       YEAR-AGNOSTIC and reusable across every scenario/year, so
#                       we compute it once (or load a cache) and only vary supply.
#   * tract_pop      tibble(GEOID, female_pop)               -- ACS demand
#   * baseline_origins  data.frame(coord_id, state_abbr, supply)
#                    -- the baseline per-origin roster supply + each origin's
#                       state, from compute_provider_supply() joined to a
#                       coord_id -> state lookup.
#
# The projection artifact is produced by cliff (validated against the
# mufflyaccess projection contract). Point PROJECTION_PATH at it.
#
# Run:  Rscript scripts/urps_accessibility/project_scenarios.R
# =============================================================================

suppressWarnings(suppressMessages({
  library(twostep)        # compute_e2sfca(), E2SFCA_DEFAULT_WEIGHTS
  library(mufflyaccess)   # the projection contract + scenario registry
}))

PROJECTION_PATH <- Sys.getenv(
  "URPS_PROJECTION_PATH",
  "../cliff/scripts/urps_projection/urps_projection_2023_2040_v1.csv")

# ---- Inputs (fail loud with guidance if the upstream artifacts are absent) ---
.need <- function(obj, what)
  if (is.null(obj)) stop(sprintf(
    "[project_scenarios] missing input: %s. Produce it from the isochrones pipeline / frozen 2SFCA run before running this adapter.",
    what), call. = FALSE)

# These loaders are intentionally thin; adapt the paths to your artifact layout.
readRDS_if <- function(p) if (file.exists(p)) readRDS(p) else NULL

overlap          <- readRDS_if("artifacts/2sfca/overlap_band_tract.rds")
tract_pop        <- readRDS_if("artifacts/2sfca/tract_female_pop.rds")
baseline_origins <- readRDS_if("artifacts/2sfca/baseline_origins_by_state.rds")
.need(overlap, "band x tract overlap (artifacts/2sfca/overlap_band_tract.rds)")
.need(tract_pop, "tract female population (artifacts/2sfca/tract_female_pop.rds)")
.need(baseline_origins, "baseline per-origin supply by state (artifacts/2sfca/baseline_origins_by_state.rds)")

# ---- The engine seam ---------------------------------------------------------
# Receives engine-ready per-origin supply (coord_id, supply) for one scenario-year
# and returns a one-row headline: population-weighted mean access + zero-access
# population share across reached tracts.
accessibility_fn <- function(supply, scenario_id, year, overlap, tract_pop, ...) {
  res <- twostep::compute_e2sfca(overlap, tract_pop, supply,
                                 weights = twostep::E2SFCA_DEFAULT_WEIGHTS,
                                 pop_col = "female_pop")
  acc <- merge(res$access[, c("GEOID", "access_scaled")], tract_pop, by = "GEOID")
  w   <- acc$female_pop
  data.frame(
    mean_access_per100k = sum(acc$access_scaled * w) / sum(w),
    zero_access_pop_share = sum(w[acc$access_scaled <= 0]) / sum(w),
    n_reached_tracts = nrow(acc),
    stringsAsFactors = FALSE)
}

# ---- Run the scenario x year grid -------------------------------------------
projection <- mufflyaccess::read_urps_projection(PROJECTION_PATH, validate = TRUE)

access_by_scenario <- urps_project_accessibility(
  projection        = projection,
  accessibility_fn  = accessibility_fn,
  baseline_origins  = baseline_origins,   # -> engine-ready coord_id supply
  basis             = "headcount",
  overlap           = overlap,
  tract_pop         = tract_pop)

out_dir <- "artifacts/2sfca/scenarios"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
out_csv <- file.path(out_dir, "access_by_urps_scenario.csv")
utils::write.csv(access_by_scenario, out_csv, row.names = FALSE)
cat(sprintf("wrote %d rows (%d scenarios x %d years) -> %s\n",
            nrow(access_by_scenario),
            length(unique(access_by_scenario$scenario_id)),
            length(unique(access_by_scenario$year)), out_csv))
