#!/usr/bin/env Rscript
# ==============================================================================
# map_allsubspec_allyears_access_surface.R
# ------------------------------------------------------------------------------
# PER-YEAR national E2SFCA access SURFACE for EVERY OB/GYN subspecialty, 2013-2023
# (the GO 2020 magma-surface style, all subspecs x all years). One small-multiple
# PNG per subspecialty.
#
# Efficiency: the two mass-conserving grids (2010 + 2020 tract vintage) and the
# isochrone bands do NOT depend on subspecialty, so they are built/loaded ONCE and
# reused across all 7 subspecs. Only the 7 x 11 = 77 E2SFCA surface computes are
# per (subspec, year). Idempotent: a subspec whose PNG already exists is SKIPPED
# unless E2SFCA_MAP_FORCE=1.
#
# Per year the surface uses ONLY physicians ACTIVE THAT YEAR (retirement /
# certification / relocation vary the cohort); isochrone geometry is year-agnostic,
# so the surface moves with the cohort. Demand denominator is held at a
# vintage-representative ACS year (2019 for 2013-2019, 2020 for 2020-2023) so the
# panel-to-panel driver within a vintage is the provider cohort. Colour scale is
# shared across panels of a given subspec (its own global p98 cap).
#
#   E2SFCA_MAP_SUBS   env, comma list (default: GO,MFM,REI,FPMRS,MIGS,PAG,CFP)
#   E2SFCA_MAP_FORCE  env, 1 = recompute even if the PNG exists
# ==============================================================================
suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr); library(ggplot2)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca_seam", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[allsub-map] %s\n", sprintf(...)))
# 1000 m grid for these DISPLAY small-multiples (the figure is coarsened to ~4 km
# below, so 500 m is wasted compute — ~4x slower per surface). The one-off GO 2020
# MANUSCRIPT surface (map_go_2020_access_surface.R) stays at 500 m. Override via
# E2SFCA_MAP_RES if a finer display is ever needed.
RES  <- as.integer(Sys.getenv("E2SFCA_MAP_RES", "1000"))
DISP_FACT <- max(1L, as.integer(round(4000 / RES)))    # aggregate to ~4 km for display
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
YEARS <- 2013:2023; BANDS <- c(30L, 60L, 120L, 180L)
ALL_SUB <- c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
SUBS <- { s <- Sys.getenv("E2SFCA_MAP_SUBS", ""); if (nzchar(s)) strsplit(s, ",")[[1]] else ALL_SUB }
FORCE <- Sys.getenv("E2SFCA_MAP_FORCE", "0") == "1"
stopifnot(all(SUBS %in% ALL_SUB))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
vintage_of  <- function(y) if (y >= 2020L) 2020L else 2010L
demand_year <- function(vint) if (vint == 2020L) 2020L else 2019L

# SSOT: subspecialty figure labels from the canonical map
# (scripts/manuscript_e2sfca_values.R).
source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))
full_name <- E2SFCA_SUBSPECIALTY_LABELS
say("subspecialties: %s | force=%s", paste(SUBS, collapse=","), FORCE)

# ── providers/demand inputs ──────────────────────────────────────────────────
newest <- function(p) { f <- list.files(file.path(ROOT,"artifacts"), p, recursive=TRUE, full.names=TRUE); f[order(file.info(f)$mtime, decreasing=TRUE)][1] }
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))

# supply for every (subspec, year); collect the union of ALL origins to filter iso once
supply_of <- list()
for (sub in SUBS) for (y in YEARS)
  supply_of[[paste(sub, y)]] <- compute_provider_supply(ycm, cohort, sub, y)
all_origins <- unique(unlist(lapply(supply_of, function(s) as.character(s$coord_id))))
say("%d (subspec x year) cohorts; %d unique origins total", length(supply_of), length(all_origins))

# ── isochrones (all bands, filtered to the union of all origins) — ONCE ──────
say("loading %d isochrone bands (filter to %d origins)", length(BANDS), length(all_origins))
iso_all <- do.call(rbind, lapply(BANDS, function(b) {
  x <- readRDS(file.path(ROOT,"artifacts","isochrones", sprintf("isochrones_%dmin_consolidated.rds", b)))
  x$coord_id <- as.character(if ("coord_id" %in% names(x)) x$coord_id else x$location_key)
  x <- x[x$coord_id %in% all_origins, , drop = FALSE]
  if (!"drive_time_minutes" %in% names(x)) x$drive_time_minutes <- b
  x <- x[, c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x) <- "geometry"; x }))
say("isochrone rows (all bands x origins) = %d", nrow(iso_all))

# ── one grid per tract vintage — ONCE ────────────────────────────────────────
build_vintage_grid <- function(vint) {
  ay <- demand_year(vint)
  say("fetching ACS %d tracts (geometry) for %d-vintage grid", ay, vint)
  raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=c(female_pop="B01001_026"), state=s, year=ay, geometry=TRUE)))
  raw <- raw[raw$variable == "female_pop", ]
  geom <- sf::st_as_sf(raw[, "GEOID"]); geom$GEOID <- as.character(geom$GEOID)
  pop  <- dplyr::tibble(GEOID = as.character(raw$GEOID), female_pop = as.numeric(raw$estimate))
  gg   <- build_e2sfca_grid_geometry(geom, resolution = RES)
  grid <- attach_e2sfca_population(gg, pop, "female_pop", alloc = "area")
  say("%d-vintage grid pop = %.0f (ACS %.0f)", vint,
      sum(terra::values(grid$pop_rast)[,1], na.rm = TRUE), sum(pop$female_pop))
  grid
}
grids <- list("2010" = build_vintage_grid(2010L), "2020" = build_vintage_grid(2020L))

# ── CONUS state outlines — ONCE ──────────────────────────────────────────────
states <- suppressMessages(tigris::states(cb = TRUE, resolution = "20m", progress_bar = FALSE))
states <- sf::st_transform(states[states$STATEFP %in% conus(), ], E2SFCA_AREA_CRS)

# ── per (subspec, year) surface -> coarse display frame ──────────────────────
per_year_df <- function(sub, y) {
  s <- supply_of[[paste(sub, y)]]
  if (!nrow(s)) return(NULL)
  grid <- grids[[as.character(vintage_of(y))]]
  iso_y <- iso_all[iso_all$coord_id %in% as.character(s$coord_id), , drop = FALSE]
  iso <- prepare_e2sfca_iso(iso_y, area_crs = E2SFCA_AREA_CRS)
  res <- compute_e2sfca_raster(grid, iso, s, per_capita_scale = 1e5,
                               thresholds = E2SFCA_DEFAULT_THRESHOLDS, return_surface = TRUE)
  surf <- res$surface * 1e5
  disp <- terra::aggregate(surf, fact = DISP_FACT, fun = "mean", na.rm = TRUE)
  d <- as.data.frame(disp, xy = TRUE, na.rm = TRUE); names(d)[3] <- "access"
  d$access[d$access < 0] <- 0
  d$year <- y; d$n_orig <- nrow(s); d$natmean <- res$national$mean_population_weighted_scaled
  d
}

render_sub <- function(sub) {
  out_png <- file.path(OUT, sprintf("map_%s_allyears_access_surface.png", tolower(sub)))
  if (file.exists(out_png) && !FORCE) { say("SKIP %s (exists)", sub); return(invisible(out_png)) }
  say("=== %s ===", sub)
  frames <- lapply(YEARS, function(y) tryCatch(per_year_df(sub, y),
              error = function(e) { say("  %s %d FAILED: %s", sub, y, conditionMessage(e)); NULL }))
  df <- dplyr::bind_rows(Filter(Negate(is.null), frames))
  if (!nrow(df)) { say("  %s: NO surfaces built — skipping figure", sub); return(invisible(NULL)) }
  for (yy in sort(unique(df$year))) {
    r <- df[df$year == yy, ]; say("  %s %d: cells=%d natmean=%.3f max=%.3f", sub, yy, nrow(r), r$natmean[1], max(r$access))
  }
  cap <- as.numeric(stats::quantile(df$access[df$access > 0], 0.98, na.rm = TRUE))
  lab <- df |> distinct(year, n_orig, natmean) |> arrange(year) |>
    mutate(facet = sprintf("%d  (n=%d, mean %.2f)", year, n_orig, natmean))
  df <- df |> left_join(lab |> select(year, facet), by = "year")
  df$facet <- factor(df$facet, levels = lab$facet)

  fig <- ggplot() +
    geom_raster(data = df, aes(x, y, fill = pmin(access, cap))) +
    geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.12) +
    scale_fill_viridis_c(option = "magma", trans = "sqrt", direction = 1,
      name = sprintf("Access per 100k women (√ scale, capped at p98=%.2f)", cap),
      labels = scales::label_number(accuracy = 0.01),
      guide = guide_colourbar(title.position = "top", title.hjust = 0.5)) +
    facet_wrap(~ facet, ncol = 4) +
    coord_sf(crs = E2SFCA_AREA_CRS, expand = FALSE, datum = NA) +
    labs(title = sprintf("Access to %s - E2SFCA, 2013-2023", full_name[[sub]]),
         subtitle = sprintf("Providers per 100,000 women on the mass-conserving %s m display grid. Cohort ACTIVE THAT YEAR varies with retirement / certification / relocation; isochrone geometry is year-agnostic, so the surface moves with the cohort. n = active origins.", format(RES, big.mark=",")),
         caption = "Demand denominator held at a vintage-representative ACS year (2019 for 2013-2019, 2020 for 2020-2023) so the panel-to-panel driver within a vintage is the provider cohort. CONUS, EPSG:5070.") +
    theme_void(base_size = 12) +
    theme(plot.title = element_text(size = rel(1.25), face = "bold"),
          plot.title.position = "plot",
          legend.position = "bottom", legend.key.width = unit(60, "pt"),
          strip.text = element_text(face = "bold"),
          plot.margin = margin(8, 8, 8, 8))
  ggsave(out_png, fig, width = 15, height = 12, dpi = 200, bg = "white")
  say("wrote %s", out_png)
  invisible(out_png)
}

for (sub in SUBS) render_sub(sub)
say("ALL DONE — %d subspecialties", length(SUBS))
