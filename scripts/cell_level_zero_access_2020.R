#!/usr/bin/env Rscript
# ==============================================================================
# cell_level_zero_access_2020.R  (peer-review Tranche B, issue #6)  — EFFICIENT
# ------------------------------------------------------------------------------
# Cell-informed zero-access share for 2020, per subspecialty and group. The
# manuscript's tract-level "% zero" is the share of a group's population in a
# TRACT whose MEAN access is 0, which misses zero-access cells inside partially
# served tracts. This computes, per tract, the AREA FRACTION of the tract whose
# grid-cell access A_c == 0 (exactextractr over the E2SFCA surface), then the
# group zero-access share
#
#     zero_g = sum_t P_gt * zerofrac_t / sum_t P_gt ,
#
# using tract-level ACS group female populations directly (P_gt) — no per-group
# raster allocation. Only ONE grid demand-allocation (total female) is built, for
# the E2SFCA model itself; the 9 group weightings are tract-level arithmetic.
# Output: artifacts/2sfca/cell_zero/cell_zero_2020.csv  (cell vs tract compare).
# ==============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr); library(terra); library(exactextractr) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
source(file.path(ROOT, "R", "accessibility_stratification.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca", "cell_zero"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
CACHE <- file.path(OUT, "cache")
say <- function(...) { cat(sprintf("[cellzero] %s\n", sprintf(...))); flush.console() }
YR <- 2020L; ACS_YR <- 2020L; RES <- as.integer(Sys.getenv("CELLZERO_RES", "500"))
SUBS <- c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
RVARS <- c(total_f = unname(TOTAL_FEMALE_VAR), RACE_FEMALE_VARS)
GRP_LABELS <- c(total_f="Total", metro_f="Metropolitan", rural_f="Rural",
  white_nh="White, non-Hispanic", black="Black alone", hispanic="Hispanic (any race)",
  asian="Asian alone", aian="Am. Indian/Alaska Native", nhpi="Nat. Hawaiian/Pac. Isl.")

# ---- ACS 2020 tracts + denominators + rurality (reuse cache) -----------------
acs <- readRDS(file.path(CACHE, "acs2020_allrace.rds")); say("loaded cached ACS 2020")
ruca <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"), colClasses="character") |>
  dplyr::transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(ruca_code))
den <- acs$den |> dplyr::left_join(ruca, by="GEOID") |>
  dplyr::mutate(dplyr::across(dplyr::any_of(names(RVARS)), ~tidyr::replace_na(.,0)),
    metro_f = ifelse(rurality %in% "Metropolitan", total_f, 0),
    rural_f = ifelse(rurality %in% "Rural",        total_f, 0))
# tract polygons in the E2SFCA equal-area CRS; drop empty geometries (the same
# ones dropped from the demand grid), which exact_extract cannot handle
geom5070 <- sf::st_transform(acs$geom, E2SFCA_AREA_CRS)
geom5070 <- geom5070[!sf::st_is_empty(geom5070), ]
den <- den[match(geom5070$GEOID, den$GEOID), ]        # align rows to polygon order
GRP_COLS <- names(GRP_LABELS)
say("tracts=%d  total F=%.0f  (res=%dm)", nrow(den), sum(den$total_f), RES)

# ---- cohort supply + isochrones ---------------------------------------------
newest <- function(p){f<-list.files(file.path(ROOT,"artifacts"),p,recursive=TRUE,full.names=TRUE);f[order(file.info(f)$mtime,decreasing=TRUE)][1]}
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
sup_all <- setNames(lapply(SUBS, function(s) compute_provider_supply(ycm, cohort, s, YR)), SUBS)
orig_all <- unique(unlist(lapply(sup_all, function(s) as.character(s$coord_id))))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_all <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig_all,,drop=FALSE]; if(!"drive_time_minutes"%in%names(x)) x$drive_time_minutes<-b
  x<-x[,c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x)<-"geometry"; x }))
say("loaded isochrones (%d origins); building %dm grid (ONE total-female allocation)", length(orig_all), RES)

# ---- ONE grid + total-female demand allocation (for the E2SFCA model) --------
gg   <- build_e2sfca_grid_geometry(acs$geom, resolution = RES)
grid <- attach_e2sfca_population(gg, den[,c("GEOID","total_f")], "total_f", alloc="area")
say("grid built; computing %d surfaces + tract zero-fraction", length(SUBS))

# per-tract zero-access AREA FRACTION for a surface, area-weighted by cell coverage
zerofrac_by_tract <- function(surf) {
  exactextractr::exact_extract(surf, geom5070, function(v, cov) {
    z <- is.na(v) | v <= 0; s <- sum(cov); if (s <= 0) NA_real_ else sum(cov[z]) / s
  }, progress = FALSE)
}
wmean <- function(x, w) { bad <- is.na(x) | is.na(w); x[bad] <- 0; w2 <- w; w2[bad] <- 0
  if (sum(w2) <= 0) NA_real_ else 100 * sum(x * w2) / sum(w2) }

rows <- list()
for (s in SUBS) {
  iso_s <- prepare_e2sfca_iso(iso_all[iso_all$coord_id %in% as.character(sup_all[[s]]$coord_id),,drop=FALSE],
                              area_crs = E2SFCA_AREA_CRS)
  r <- compute_e2sfca_raster(grid, iso_s, sup_all[[s]], per_capita_scale=1e5, return_surface=TRUE)
  zf <- zerofrac_by_tract(r$surface)                 # per-tract zero-access area fraction
  for (g in GRP_COLS)
    rows[[paste(s,g)]] <- tibble::tibble(subspec=s, group_key=g, group=unname(GRP_LABELS[g]),
      cell_zero_pct = wmean(zf, den[[g]]), res=RES)
  say("  %s: rural cell-zero=%.1f%%  AIAN cell-zero=%.1f%%  total=%.1f%%",
      s, wmean(zf, den$rural_f), wmean(zf, den$aian), wmean(zf, den$total_f))
}
cell_tbl <- dplyr::bind_rows(rows)

# ---- compare with tract-MEAN-based values (canonical stratified series) ------
long <- readr::read_csv(file.path(ROOT,"artifacts","2sfca","figures",
  "allsubspec_allyears_stratified_LONG.csv"), show_col_types=FALSE) |>
  dplyr::filter(year==YR) |> dplyr::select(subspec, group=stratum, tract_zero_pct=pct_zero)
cmp <- cell_tbl |> dplyr::left_join(long, by=c("subspec","group")) |>
  dplyr::mutate(diff_pp = cell_zero_pct - tract_zero_pct)
readr::write_csv(cmp, file.path(OUT, "cell_zero_2020.csv"))
say("wrote %s", file.path(OUT, "cell_zero_2020.csv"))

cat("\n=== CELL-informed vs TRACT-MEAN zero-access, 2020 (rural & AIAN) ===\n")
print(as.data.frame(cmp |> dplyr::filter(group %in% c("Rural","Am. Indian/Alaska Native")) |>
  dplyr::transmute(subspec, group, cell=round(cell_zero_pct,1), tract=round(tract_zero_pct,1),
                   diff_pp=round(diff_pp,1))), row.names=FALSE)
cat(sprintf("\nMedian cell-minus-tract difference (all groups/subspecs): %+.2f pp\n",
    median(cmp$diff_pp, na.rm=TRUE)))
cat("DONE\n")
