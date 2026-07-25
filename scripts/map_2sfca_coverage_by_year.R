#!/usr/bin/env Rscript
# ==============================================================================
# map_2sfca_coverage_by_year.R
# ------------------------------------------------------------------------------
# PER-YEAR coverage maps for one OB/GYN subspecialty, 2013-2023. For each year we
# take the isochrones of ONLY the physicians ACTIVE THAT YEAR (retirement /
# certification / relocation vary the cohort) and union them into one "reachable
# within BAND minutes" footprint. The individual drive-time blobs are reused
# across years (roads are ~static); the YEARLY UNION changes because the cohort
# changes. Faceted small-multiples over CONUS. Facet label carries the provider
# count so the cohort change is explicit.
#
#   SUB  env E2SFCA_MAP_SUB   (default GO)
#   BAND env E2SFCA_MAP_BAND  (default 60)
# ==============================================================================
suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(ggplot2)
}))
sf::sf_use_s2(FALSE)                                   # projected union via GEOS
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[cov-map] %s\n", sprintf(...)))

SUB   <- Sys.getenv("E2SFCA_MAP_SUB", "GO")
BAND  <- as.integer(Sys.getenv("E2SFCA_MAP_BAND", "60"))
YEARS <- 2013:2023
CRS5070 <- 5070L
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

# ── active cohort (coord_ids) per year ───────────────────────────────────────
newest <- function(p) { f <- list.files(file.path(ROOT,"artifacts"), p, recursive=TRUE, full.names=TRUE); f[order(file.info(f)$mtime, decreasing=TRUE)][1] }
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
coords_by_year <- lapply(YEARS, function(y) {
  s <- compute_provider_supply(ycm, cohort, SUB, y)
  list(year = y, coords = unique(as.character(s$coord_id)),
       n_prov = sum(s$supply), n_orig = nrow(s))
})
names(coords_by_year) <- as.character(YEARS)
all_coords <- unique(unlist(lapply(coords_by_year, `[[`, "coords")))
say("%s: %d unique origins across %d years", SUB, length(all_coords), length(YEARS))
for (cy in coords_by_year) say("  %d: providers=%d origins=%d", cy$year, cy$n_prov, cy$n_orig)

# ── load ONE band, filter to this subspecialty's union of origins ────────────
say("loading %d-min isochrones (filter to %s origins)", BAND, SUB)
iso <- readRDS(file.path(ROOT,"artifacts","isochrones", sprintf("isochrones_%dmin_consolidated.rds", BAND)))
iso$coord_id <- as.character(if ("coord_id" %in% names(iso)) iso$coord_id else iso$location_key)
iso <- iso[iso$coord_id %in% all_coords, , drop = FALSE]
sf::st_geometry(iso) <- attr(iso, "sf_column")
iso <- sf::st_transform(iso[, "coord_id"], CRS5070)
iso <- sf::st_make_valid(iso)
iso <- sf::st_simplify(iso, dTolerance = 2000, preserveTopology = TRUE)   # display speed
iso <- iso[!sf::st_is_empty(iso), ]
say("isochrone polygons kept: %d", nrow(iso))

# ── per-year union footprint ─────────────────────────────────────────────────
foot <- do.call(rbind, lapply(coords_by_year, function(cy) {
  sub <- iso[iso$coord_id %in% cy$coords, ]
  if (!nrow(sub)) return(NULL)
  u <- sf::st_union(sf::st_geometry(sub))
  sf::st_sf(year = cy$year, n_prov = cy$n_prov, n_orig = cy$n_orig, geometry = u)
}))
foot$facet <- sprintf("%d  (n=%d)", foot$year, foot$n_orig)
foot$facet <- factor(foot$facet, levels = foot$facet[order(foot$year)])
say("built %d yearly footprints", nrow(foot))

# ── CONUS state outlines ─────────────────────────────────────────────────────
states <- suppressMessages(tigris::states(cb = TRUE, resolution = "20m", progress_bar = FALSE))
states <- sf::st_transform(states[states$STATEFP %in% conus(), ], CRS5070)

full_name <- c(GO="Gynecologic Oncology", MFM="Maternal-Fetal Medicine",
  REI="Reproductive Endocrinology", FPMRS="Urogynecology (FPMRS)",
  MIGS="Minimally Invasive Gyn Surgery", PAG="Pediatric & Adolescent Gyn",
  CFP="Complex Family Planning")

fig <- ggplot() +
  geom_sf(data = states, fill = "grey93", colour = "white", linewidth = 0.15) +
  geom_sf(data = foot, aes(fill = year), colour = NA, alpha = 0.85) +
  geom_sf(data = states, fill = NA, colour = "white", linewidth = 0.15) +
  scale_fill_viridis_c(option = "viridis", guide = "none") +
  facet_wrap(~ facet, ncol = 4) +
  coord_sf(crs = CRS5070, expand = FALSE, datum = NA) +
  labs(title = sprintf("Where a woman can reach a %s within %d minutes, by year",
                       full_name[[SUB]], BAND),
       subtitle = sprintf("Union of drive-time isochrones around %s physicians ACTIVE THAT YEAR (2013-2023). Same road-blobs, different cohort each year -> the footprint moves. n = active origins.", SUB),
       caption = "Physician cohort varies by retirement / board certification / relocation. Isochrone geometry is year-agnostic; the yearly UNION is not. CONUS, EPSG:5070.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.2), face = "bold"),
        plot.title.position = "plot",
        strip.text = element_text(face = "bold", size = rel(1.0)),
        plot.margin = margin(8, 8, 8, 8))

out_png <- file.path(OUT, sprintf("map_coverage_by_year_%s_%dmin.png", SUB, BAND))
ggsave(out_png, fig, width = 14, height = 11, dpi = 200, bg = "white")
say("wrote %s", out_png)
