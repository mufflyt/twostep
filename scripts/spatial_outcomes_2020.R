#!/usr/bin/env Rscript
# ==============================================================================
# spatial_outcomes_2020.R  (second-review reframe, issue #1)
# ------------------------------------------------------------------------------
# The population-weighted national E2SFCA MEAN is algebraically supply/population
# (a conservation property) and is not spatial. This computes genuinely SPATIAL
# outcomes for 2020, per subspecialty, that DO depend on provider geography:
#   * population share OUTSIDE the 60-, 120-, and 180-minute catchment (no provider
#     reachable within that drive time) — graded coverage, not just 180-min zero;
#   * the Gini concentration index of the population-weighted access surface
#     (0 = perfectly even, higher = more spatially concentrated);
#   * the median and lower-decile (p10) cell-level access.
# These are the primary spatial measures the manuscript reframe elevates.
#   artifacts/2sfca/spatial_outcomes/spatial_outcomes_2020.csv
# ==============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr); library(terra) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
source(file.path(ROOT, "R", "accessibility_stratification.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca", "spatial_outcomes"); dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
say <- function(...) { cat(sprintf("[spatial] %s\n", sprintf(...))); flush.console() }
YR <- 2020L; RES <- as.integer(Sys.getenv("SPATIAL_RES", "1000"))
SUBS <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")
THRESH <- c(60L, 120L, 180L)

# reuse the cell-zero ACS cache (total female + geometry + RUCA-independent)
acs <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
den <- acs$den |> dplyr::mutate(total_f = tidyr::replace_na(total_f, 0))
say("tracts=%d total F=%.0f res=%dm", nrow(den), sum(den$total_f), RES)

newest <- function(p){f<-list.files(file.path(ROOT,"artifacts"),p,recursive=TRUE,full.names=TRUE);f[order(file.info(f)$mtime,decreasing=TRUE)][1]}
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
sup_all <- setNames(lapply(SUBS, function(s) compute_provider_supply(ycm, cohort, s, YR)), SUBS)
orig_all <- unique(unlist(lapply(sup_all, function(s) as.character(s$coord_id))))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_by_band <- setNames(lapply(c(30L,60L,120L,180L), function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig_all,,drop=FALSE]; x$drive_time_minutes<-b
  x<-x[,c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x)<-"geometry"
  sf::st_transform(x, E2SFCA_AREA_CRS) }), c(30L,60L,120L,180L))
iso_all <- do.call(rbind, iso_by_band)
say("loaded isochrones (%d origins); building %dm grid", length(orig_all), RES)

gg   <- build_e2sfca_grid_geometry(acs$geom, resolution = RES)
grid <- attach_e2sfca_population(gg, den[,c("GEOID","total_f")], "total_f", alloc="area")
popr <- grid$pop_rast
pv   <- terra::values(popr)[,1]; pv[is.na(pv)] <- 0
totpop <- sum(pv)

# population-weighted Gini of a value vector
gini_w <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & w > 0; x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; w <- w[o]
  cw <- cumsum(w) / sum(w); cxw <- cumsum(x * w) / sum(x * w)
  # trapezoidal area under Lorenz curve
  1 - sum((cw - c(0, cw[-length(cw)])) * (cxw + c(0, cxw[-length(cxw)])))
}
wquant <- function(x, w, p) {  # population-weighted quantile
  ok <- !is.na(x) & !is.na(w) & w > 0; x <- x[ok]; w <- w[ok]
  o <- order(x); x <- x[o]; cw <- cumsum(w[o]) / sum(w[o]); x[which(cw >= p)[1]]
}

rows <- list()
for (s in SUBS) {
  ids <- as.character(sup_all[[s]]$coord_id)
  # ---- population share outside each threshold (no provider within T minutes) ----
  outside <- sapply(THRESH, function(T) {
    covered <- iso_all[iso_all$drive_time_minutes <= T & iso_all$coord_id %in% ids, ]
    u <- sf::st_union(covered)                         # union of reachable catchments
    m <- terra::rasterize(terra::vect(sf::st_sf(geometry=u)), popr, field=1)
    cov_v <- terra::values(m)[,1]; inside <- !is.na(cov_v)
    100 * sum(pv[!inside]) / totpop
  })
  names(outside) <- paste0("pct_outside_", THRESH)
  # ---- Gini + quantiles of the access surface ----
  iso_s <- prepare_e2sfca_iso(iso_all[iso_all$coord_id %in% ids,,drop=FALSE], area_crs=E2SFCA_AREA_CRS)
  r <- compute_e2sfca_raster(grid, iso_s, sup_all[[s]], per_capita_scale=1e5, return_surface=TRUE)
  a <- terra::values(r$surface * 1e5)[,1]; a[is.na(a)] <- 0
  rows[[s]] <- tibble::tibble(subspec=s, res=RES,
    pct_outside_60 = outside["pct_outside_60"], pct_outside_120 = outside["pct_outside_120"],
    pct_outside_180 = outside["pct_outside_180"],
    gini = gini_w(a, pv), median_access = wquant(a, pv, 0.5), p10_access = wquant(a, pv, 0.10),
    national_mean = r$national$mean_population_weighted_scaled)
  say("  %s: outside 60/120/180 = %.1f/%.1f/%.1f%%  Gini=%.3f  median=%.3f",
      s, outside[1], outside[2], outside[3], rows[[s]]$gini, rows[[s]]$median_access)
}
res <- dplyr::bind_rows(rows)
readr::write_csv(res, file.path(OUT, "spatial_outcomes_2020.csv"))
say("wrote %s", file.path(OUT, "spatial_outcomes_2020.csv"))
cat("\n=== SPATIAL OUTCOMES 2020 (per subspecialty) ===\n")
print(as.data.frame(res |> dplyr::mutate(dplyr::across(where(is.numeric), ~round(.,3)))), row.names=FALSE)
cat("DONE\n")
