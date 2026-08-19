#!/usr/bin/env Rscript
# ==============================================================================
# seam_test_subgroup.R  (peer-review Tranche B, issue #5)
# ------------------------------------------------------------------------------
# Subgroup-specific tract-vintage seam test. The manuscript fits trends across the
# 2019->2020 census-tract vintage change (2010-vintage tracts -> 2020-vintage
# tracts). A national seam test showed the NATIONAL estimate is stable, but
# rurality/race subgroups could shift at the boundary. This isolates the pure
# vintage effect by holding the PHYSICIAN COHORT FIXED (2020 active) and computing
# each subgroup's mean access and zero-access share under BOTH frameworks:
#   A = 2010-vintage tracts + 2019 ACS (2015-2019) + RUCA 2010
#   B = 2020-vintage tracts + 2020 ACS (2016-2020) + RUCA 2020
# seam shift = B - A (cohort fixed). Small shift => the vintage change does not
# drive the subgroup trends. Computed per subgroup x subspecialty; the zero-access
# metric matches the manuscript's tract-mean definition used in the trends.
#   artifacts/2sfca/seam_subgroup/seam_subgroup.csv
# ==============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr); library(terra); library(exactextractr) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
source(file.path(ROOT, "R", "accessibility_stratification.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca", "seam_subgroup"); dir.create(OUT, showWarnings=FALSE, recursive=TRUE)
CACHE <- file.path(OUT, "cache"); dir.create(CACHE, showWarnings=FALSE, recursive=TRUE)
say <- function(...) { cat(sprintf("[seam] %s\n", sprintf(...))); flush.console() }
COHORT_YR <- 2020L; RES <- as.integer(Sys.getenv("SEAM_RES", "1000"))
SUBS <- c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
RVARS <- c(total_f=unname(TOTAL_FEMALE_VAR), RACE_FEMALE_VARS)
GRP_LABELS <- c(metro_f="Metropolitan", rural_f="Rural",
  white_nh="White, non-Hispanic", black="Black alone", hispanic="Hispanic (any race)",
  asian="Asian alone", aian="Am. Indian/Alaska Native", nhpi="Nat. Hawaiian/Pac. Isl.")

# the two vintage frameworks: (label, ACS year, RUCA file)
VINTAGES <- list(
  v2010 = list(acs=2019L, ruca="ruca_tract_mapping_2010.csv"),
  v2020 = list(acs=2020L, ruca="ruca_tract_mapping.csv"))

fetch_vintage <- function(vname) {
  cf <- file.path(CACHE, sprintf("acs_%s.rds", vname))
  if (file.exists(cf)) { say("loaded cached %s", vname); return(readRDS(cf)) }
  ay <- VINTAGES[[vname]]$acs
  say("fetching ACS %d tracts (%s vintage)", ay, vname)
  raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=RVARS, state=s, year=ay, geometry=TRUE)))
  geom <- raw |> dplyr::distinct(GEOID,.keep_all=TRUE) |> sf::st_as_sf() |> dplyr::select(GEOID)
  geom$GEOID <- as.character(geom$GEOID)
  wide <- raw |> sf::st_drop_geometry() |>
    dplyr::transmute(GEOID=as.character(GEOID), variable, estimate=as.numeric(estimate)) |>
    tidyr::pivot_wider(names_from=variable, values_from=estimate)
  out <- list(geom=geom, den=wide); saveRDS(out, cf); out
}

# fixed 2020 cohort supply + isochrones (shared across vintages)
newest <- function(p){f<-list.files(file.path(ROOT,"artifacts"),p,recursive=TRUE,full.names=TRUE);f[order(file.info(f)$mtime,decreasing=TRUE)][1]}
ycm    <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
sup_all <- setNames(lapply(SUBS, function(s) compute_provider_supply(ycm, cohort, s, COHORT_YR)), SUBS)
orig_all <- unique(unlist(lapply(sup_all, function(s) as.character(s$coord_id))))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_all <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig_all,,drop=FALSE]; if(!"drive_time_minutes"%in%names(x)) x$drive_time_minutes<-b
  x<-x[,c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x)<-"geometry"; x }))
say("fixed %d cohort; %d origins; res=%dm", COHORT_YR, length(orig_all), RES)

wmean <- function(x,w){ bad<-is.na(x)|is.na(w); x[bad]<-0; w2<-w; w2[bad]<-0; if(sum(w2)<=0) NA_real_ else sum(x*w2)/sum(w2) }

# compute subgroup mean-access + tract-mean zero-access for one vintage framework
estimate_vintage <- function(vname) {
  acs <- fetch_vintage(vname)
  ruca <- read.csv(file.path(ROOT,"data","external",VINTAGES[[vname]]$ruca), colClasses="character") |>
    dplyr::transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(ruca_code))
  den <- acs$den |> dplyr::left_join(ruca, by="GEOID") |>
    dplyr::mutate(dplyr::across(dplyr::any_of(names(RVARS)), ~tidyr::replace_na(.,0)),
      metro_f=ifelse(rurality %in% "Metropolitan", total_f, 0),
      rural_f=ifelse(rurality %in% "Rural", total_f, 0))
  geom5070 <- sf::st_transform(acs$geom, E2SFCA_AREA_CRS)
  geom5070 <- geom5070[!sf::st_is_empty(geom5070), ]
  den <- den[match(geom5070$GEOID, den$GEOID), ]
  gg <- build_e2sfca_grid_geometry(acs$geom, resolution=RES)
  grid <- attach_e2sfca_population(gg, den[,c("GEOID","total_f")], "total_f", alloc="area")
  say("  [%s] grid built; %d subspec surfaces", vname, length(SUBS))
  purrr::map_dfr(SUBS, function(s){
    iso_s <- prepare_e2sfca_iso(iso_all[iso_all$coord_id %in% as.character(sup_all[[s]]$coord_id),,drop=FALSE],
                                area_crs=E2SFCA_AREA_CRS)
    r <- compute_e2sfca_raster(grid, iso_s, sup_all[[s]], per_capita_scale=1e5, return_surface=TRUE)
    surf <- r$surface * 1e5
    tmean <- exactextractr::exact_extract(surf, geom5070, "mean", progress=FALSE)  # tract mean access
    tmean[is.na(tmean)] <- 0
    tibble::tibble(vintage=vname, subspec=s, group_key=names(GRP_LABELS)) |>
      dplyr::mutate(group=unname(GRP_LABELS[group_key]),
        mean_access=vapply(group_key, function(g) wmean(tmean, den[[g]]), 0),
        pct_zero=vapply(group_key, function(g) 100*wmean(as.numeric(tmean<=0), den[[g]]), 0))
  })
}

est <- dplyr::bind_rows(estimate_vintage("v2010"), estimate_vintage("v2020"))
seam <- est |> dplyr::select(subspec, group, vintage, mean_access, pct_zero) |>
  tidyr::pivot_wider(names_from=vintage, values_from=c(mean_access, pct_zero)) |>
  dplyr::mutate(seam_mean = mean_access_v2020 - mean_access_v2010,
                seam_zero = pct_zero_v2020 - pct_zero_v2010)
readr::write_csv(seam, file.path(OUT, "seam_subgroup.csv"))
say("wrote %s", file.path(OUT,"seam_subgroup.csv"))

cat("\n=== SUBGROUP SEAM SHIFT (2020-vintage minus 2010-vintage, cohort fixed at 2020) ===\n")
print(as.data.frame(seam |> dplyr::filter(group %in% c("Rural","Metropolitan","Am. Indian/Alaska Native","White, non-Hispanic")) |>
  dplyr::mutate(subspec=factor(subspec, levels=SUBS)) |> dplyr::arrange(subspec, group) |>
  dplyr::transmute(subspec, group, seam_access=round(seam_mean,3), seam_zero_pp=round(seam_zero,2))), row.names=FALSE)
cat(sprintf("\nMax |seam| zero-access shift: %.2f pp; max |seam| mean-access: %.3f  (across all groups/subspecs)\n",
  max(abs(seam$seam_zero),na.rm=TRUE), max(abs(seam$seam_mean),na.rm=TRUE)))
cat("DONE\n")
