#!/usr/bin/env Rscript
# ==============================================================================
# map_fpmrs_allyears_access_surface.R
# ------------------------------------------------------------------------------
# PER-YEAR national E2SFCA access SURFACE for Urogynecology / FPMRS, 2013-2023,
# rendered as a magma small-multiple (the GO 2020 surface style, all years).
#
# For each year the surface uses ONLY the physicians ACTIVE THAT YEAR (retirement
# / board certification / relocation vary the cohort). Isochrone geometry is
# year-agnostic (roads ~static); the surface changes because the cohort changes.
#
# Grid + allocation: production mass-conserving 500 m grid (area allocation).
# Tract vintage: 2013-2019 -> 2010 tracts; 2020-2023 -> 2020 tracts (built ONCE
# per vintage). Demand denominator is held at a vintage-representative ACS year
# (2019 for the 2010 vintage, 2020 for the 2020 vintage) so that WITHIN a vintage
# the only thing moving panel-to-panel is the provider cohort. Colour scale is
# shared across panels (global p98 cap) for comparability.
#
# Override subspecialty/band-set via SUB / BAND env if reused.
# ==============================================================================
suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr); library(ggplot2)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca_seam", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[fpmrs-map] %s\n", sprintf(...)))
RES <- 500L; SUB <- Sys.getenv("E2SFCA_MAP_SUB", "FPMRS"); YEARS <- 2013:2023
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
BANDS <- c(30L, 60L, 120L, 180L)
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
vintage_of  <- function(y) if (y >= 2020L) 2020L else 2010L
demand_year <- function(vint) if (vint == 2020L) 2020L else 2019L   # vintage-representative ACS

# ── providers/demand inputs ──────────────────────────────────────────────────
newest <- function(p) { f <- list.files(file.path(ROOT,"artifacts"), p, recursive=TRUE, full.names=TRUE); f[order(file.info(f)$mtime, decreasing=TRUE)][1] }
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))

supply_by_year <- lapply(YEARS, function(y) compute_provider_supply(ycm, cohort, SUB, y))
names(supply_by_year) <- as.character(YEARS)
for (y in YEARS) say("%s %d providers=%d origins=%d", SUB, y,
                     sum(supply_by_year[[as.character(y)]]$supply), nrow(supply_by_year[[as.character(y)]]))
all_origins <- unique(unlist(lapply(supply_by_year, function(s) as.character(s$coord_id))))
say("%s: %d unique origins across %d years", SUB, length(all_origins), length(YEARS))

# ── isochrones (all bands, filtered to the union of FPMRS origins) ───────────
say("loading %d isochrone bands (filter to %d origins)", length(BANDS), length(all_origins))
iso_all <- do.call(rbind, lapply(BANDS, function(b) {
  x <- readRDS(file.path(ROOT,"artifacts","isochrones", sprintf("isochrones_%dmin_consolidated.rds", b)))
  x$coord_id <- as.character(if ("coord_id" %in% names(x)) x$coord_id else x$location_key)
  x <- x[x$coord_id %in% all_origins, , drop = FALSE]
  if (!"drive_time_minutes" %in% names(x)) x$drive_time_minutes <- b
  x <- x[, c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x) <- "geometry"; x }))
say("isochrone rows (all bands x origins) = %d", nrow(iso_all))

# ── one grid per tract vintage (geometry + demand fetched once) ──────────────
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

# ── per-year E2SFCA surface -> coarse display frame ──────────────────────────
per_year_df <- function(y) {
  s <- supply_by_year[[as.character(y)]]
  grid <- grids[[as.character(vintage_of(y))]]
  iso_y <- iso_all[iso_all$coord_id %in% as.character(s$coord_id), , drop = FALSE]
  iso <- prepare_e2sfca_iso(iso_y, area_crs = E2SFCA_AREA_CRS)
  res <- compute_e2sfca_raster(grid, iso, s, per_capita_scale = 1e5,
                               thresholds = E2SFCA_DEFAULT_THRESHOLDS, return_surface = TRUE)
  surf <- res$surface * 1e5
  disp <- terra::aggregate(surf, fact = 8, fun = "mean", na.rm = TRUE)         # ~4 km
  d <- as.data.frame(disp, xy = TRUE, na.rm = TRUE); names(d)[3] <- "access"
  d$access[d$access < 0] <- 0
  d$year <- y; d$n_orig <- nrow(s)
  d$natmean <- res$national$mean_population_weighted_scaled
  say("  %d: cells=%d natmean=%.3f max=%.3f", y, nrow(d), d$natmean[1], max(d$access))
  d
}
frames <- lapply(YEARS, function(y) tryCatch(per_year_df(y),
             error = function(e) { say("YEAR %d FAILED: %s", y, conditionMessage(e)); NULL }))
df <- dplyr::bind_rows(Filter(Negate(is.null), frames))
stopifnot(nrow(df) > 0)
ok_years <- sort(unique(df$year)); say("surfaces built for %d/%d years", length(ok_years), length(YEARS))

# shared colour cap across all panels (global p98 of positive access)
cap <- as.numeric(stats::quantile(df$access[df$access > 0], 0.98, na.rm = TRUE))
say("shared display cap (p98) = %.3f", cap)

lab <- df |> distinct(year, n_orig, natmean) |> arrange(year) |>
  mutate(facet = sprintf("%d  (n=%d, mean %.2f)", year, n_orig, natmean))
df <- df |> left_join(lab |> select(year, facet), by = "year")
df$facet <- factor(df$facet, levels = lab$facet)

# ── CONUS state outlines ─────────────────────────────────────────────────────
states <- suppressMessages(tigris::states(cb = TRUE, resolution = "20m", progress_bar = FALSE))
states <- sf::st_transform(states[states$STATEFP %in% conus(), ], E2SFCA_AREA_CRS)

full_name <- c(GO="Gynecologic Oncology", MFM="Maternal-Fetal Medicine",
  REI="Reproductive Endocrinology", FPMRS="Urogynecology (FPMRS)",
  MIGS="Minimally Invasive Gyn Surgery", PAG="Pediatric & Adolescent Gyn",
  CFP="Complex Family Planning")

fig <- ggplot() +
  geom_raster(data = df, aes(x, y, fill = pmin(access, cap))) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.12) +
  scale_fill_viridis_c(option = "magma", trans = "sqrt", direction = 1,
    name = sprintf("Access per 100k women (√ scale, capped at p98=%.2f)", cap),
    labels = scales::label_number(accuracy = 0.01),
    guide = guide_colourbar(title.position = "top", title.hjust = 0.5)) +
  facet_wrap(~ facet, ncol = 4) +
  coord_sf(crs = E2SFCA_AREA_CRS, expand = FALSE, datum = NA) +
  labs(title = sprintf("Access to %s — E2SFCA, 2013-2023", full_name[[SUB]]),
       subtitle = "Providers per 100,000 women on the mass-conserving 500 m grid. Cohort ACTIVE THAT YEAR varies with retirement / certification / relocation; isochrone geometry is year-agnostic, so the surface moves with the cohort. n = active origins.",
       caption = "Demand denominator held at a vintage-representative ACS year (2019 for 2013-2019, 2020 for 2020-2023) so the panel-to-panel driver within a vintage is the provider cohort. CONUS, EPSG:5070.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.25), face = "bold"),
        plot.title.position = "plot",
        legend.position = "bottom", legend.key.width = unit(60, "pt"),
        strip.text = element_text(face = "bold"),
        plot.margin = margin(8, 8, 8, 8))

out_png <- file.path(OUT, sprintf("map_%s_allyears_access_surface.png", tolower(SUB)))
ggsave(out_png, fig, width = 15, height = 12, dpi = 200, bg = "white")
say("wrote %s", out_png)
