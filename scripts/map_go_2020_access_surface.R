#!/usr/bin/env Rscript
# ==============================================================================
# map_go_2020_access_surface.R
# ------------------------------------------------------------------------------
# Compute and MAP the national E2SFCA access surface for Gynecologic Oncology
# (GO), 2020, using the PRODUCTION mass-conserving allocation. Renders a CONUS
# choropleth (per 100k women) plus a companion map on a perceptual scale.
# ==============================================================================
suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr); library(ggplot2)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))  # SSOT constants
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca_seam", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[go-map] %s\n", sprintf(...)))
RES <- E2SFCA_PRODUCTION_RESOLUTION_M; YEAR <- 2020L; SUB <- "GO"   # SSOT: production 500 m
conus <- function() CONUS_STATE_FIPS   # SSOT: scripts/manuscript_e2sfca_values.R

# ── providers + demand ───────────────────────────────────────────────────────
newest <- function(p) { f <- list.files(file.path(ROOT,"artifacts"), p, recursive=TRUE, full.names=TRUE); f[order(file.info(f)$mtime, decreasing=TRUE)][1] }
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
supply <- compute_provider_supply(ycm, cohort, SUB, YEAR)
say("%s %d providers=%d origins=%d", SUB, YEAR, sum(supply$supply), nrow(supply))

say("fetching 2020 tract female pop + geometry (CONUS, cached)")
raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
  geography="tract", variables=c(female_pop="B01001_026"), state=s, year=2020L, geometry=TRUE)))
raw <- raw[raw$variable=="female_pop", ]
geom <- sf::st_as_sf(raw[,"GEOID"]); geom$GEOID <- as.character(geom$GEOID)
pop_vals <- dplyr::tibble(GEOID=as.character(raw$GEOID), female_pop=as.numeric(raw$estimate))

# ── production grid (mass-conserving) + E2SFCA surface ───────────────────────
say("building mass-conserving grid @ %dm", RES)
gg   <- build_e2sfca_grid_geometry(geom, resolution = RES)
grid <- attach_e2sfca_population(gg, pop_vals, "female_pop", alloc = "area")   # production default
say("grid pop = %.0f (ACS %.0f)", sum(terra::values(grid$pop_rast)[,1],na.rm=TRUE), sum(pop_vals$female_pop))

# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_sf <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b) {
  x <- readRDS(file.path(ROOT,"artifacts","isochrones", sprintf("isochrones_%dmin_consolidated.rds", b)))
  x$coord_id <- as.character(if ("coord_id" %in% names(x)) x$coord_id else x$location_key)
  x <- x[x$coord_id %in% supply$coord_id, , drop = FALSE]
  if (!"drive_time_minutes" %in% names(x)) x$drive_time_minutes <- b
  x <- x[, c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x) <- "geometry"; x }))
iso <- prepare_e2sfca_iso(iso_sf, area_crs = E2SFCA_AREA_CRS)
say("isochrone rows (GO x band) = %d", nrow(iso_sf))

res  <- compute_e2sfca_raster(grid, iso, supply, per_capita_scale = 1e5,
                              thresholds = E2SFCA_DEFAULT_THRESHOLDS, return_surface = TRUE)
surf <- res$surface * 1e5                                   # accessibility per 100k women
names(surf) <- "access"
terra::writeRaster(surf, file.path(OUT, "go_2020_access_surface_500m.tif"), overwrite = TRUE)
say("national pop-wt mean/100k = %.4f", res$national$mean_population_weighted_scaled)

# ── coarsen for display + CONUS state outlines ───────────────────────────────
disp <- terra::aggregate(surf, fact = 8, fun = "mean", na.rm = TRUE)   # ~4 km cells
df <- as.data.frame(disp, xy = TRUE, na.rm = TRUE); names(df)[3] <- "access"
df$access[df$access < 0] <- 0
cap <- as.numeric(stats::quantile(df$access[df$access > 0], 0.98, na.rm = TRUE))
say("display cells=%d  cap(p98)=%.3f  max=%.3f", nrow(df), cap, max(df$access))

states <- suppressMessages(tigris::states(cb = TRUE, resolution = "20m", progress_bar = FALSE))
states <- states[states$STATEFP %in% conus(), ]
states <- sf::st_transform(states, E2SFCA_AREA_CRS)

base_theme <- theme_void(base_size = 13) +
  theme(plot.title = element_text(size = rel(1.15), face = "bold", hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5), plot.title.position = "plot",
        legend.position = "bottom", legend.key.width = unit(28, "pt"),
        plot.margin = margin(6, 6, 6, 6))

mk_map <- function(trans, title, subtitle, bartitle) {
  ggplot() +
    geom_raster(data = df, aes(x, y, fill = pmin(access, cap))) +
    geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.18) +
    scale_fill_viridis_c(option = "magma", trans = trans, direction = 1,
      name = bartitle, labels = scales::label_number(accuracy = 0.01),
      guide = guide_colourbar(title.position = "top", title.hjust = 0.5)) +
    coord_sf(crs = E2SFCA_AREA_CRS, expand = FALSE) +
    labs(title = title, subtitle = subtitle) + base_theme
}

m1 <- mk_map("sqrt",
  "Access to Gynecologic Oncologists - E2SFCA, 2020",
  sprintf("Providers per 100,000 women (mass-conserving 500 m grid; national pop-wt mean %.3f)",
          res$national$mean_population_weighted_scaled),
  sprintf("Access per 100k women (√ scale, capped at p98=%.2f)", cap))

ggsave(file.path(OUT, "map_go_2020_access_surface.png"), m1,
       width = 12, height = 8, dpi = 200, bg = "white")
say("wrote %s", file.path(OUT, "map_go_2020_access_surface.png"))
