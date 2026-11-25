#!/usr/bin/env Rscript
# =============================================================================
# desjardins7/09_surface_recovery.R
# Robustness: re-run the 2020 E2SFCA surface after ADDING the recovered
# physicians that fall within the 5-km cluster radius of an existing isochrone
# origin (they reuse that origin's catchment; supply is incremented there). If
# the metro:rural ratio and no-access barely move, the geocoding loss did not
# bias the disparities. Reuses the validated tract-centroid engine from step 06.
#   artifacts/desjardins7/surface_recovery_2020.csv
# =============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr); library(RANN) }))
ROOT <- if (requireNamespace("here", quietly=TRUE)) here::here() else normalizePath(".")
if (!exists("E2SFCA_FROZEN_RUN_ID")) source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))  # SSOT: frozen E2SFCA run
OUT  <- file.path(ROOT,"artifacts","desjardins7")
UNP  <- file.path(ROOT,"artifacts","2sfca","ec2",E2SFCA_FROZEN_RUN_ID,"unpacked")
say  <- function(...) { cat(sprintf("[dj7-sr] %s\n", sprintf(...))); flush.console() }
source(file.path(ROOT,"R","accessibility_stratification.R"))
source(file.path(ROOT,"R","desjardins7_e2sfca.R"))
source(file.path(ROOT,"R","study_join_accounting.R"))
SUBS <- DJ7_SUBS
Wc <- DJ7_WC_BASE
BANDS <- DJ7_BANDS

acs <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
cen <- acs$geom |> select(GEOID) |> st_transform(5070) |> st_make_valid()
cen <- cen[!st_is_empty(cen),]; cen <- st_centroid(cen); cen$GEOID <- as.character(cen$GEOID)
den <- acs$den |> transmute(GEOID=as.character(GEOID), total_f=total_f)
den <- align_denominator_to_reference(den, cen, by="GEOID",
  context="dj7 surface denominators", complete_cols="total_f")
ruca<- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
den <- den |> left_join(ruca, by="GEOID")
# NA rurality (uncoded RUCA) stays unclassified; it is excluded from stratum means only.

rec <- readr::read_csv(file.path(OUT,"recovered_2020.csv"), show_col_types=FALSE) |>
  filter(in_surface_5km)
say("surface-eligible recovered (within 5 km): %d", nrow(rec))

sup0 <- setNames(lapply(SUBS, function(s)
  readRDS(file.path(UNP,sprintf("step_4_2sfca_%s_2020_providers.rds",s))) |>
    transmute(coord_id=as.character(coord_id), supply)), SUBS)
orig <- unique(unlist(lapply(sup0, function(x) x$coord_id)))
oll <- do.call(rbind, strsplit(orig,"_",fixed=TRUE))
op  <- st_transform(st_as_sf(data.frame(lat=as.numeric(oll[,1]),lon=as.numeric(oll[,2])),
                             coords=c("lon","lat"), crs=4326), 5070)
oc  <- st_coordinates(op)

# augmented supply: snap each recovered to nearest origin coord_id, +1 supply there
augment <- function(s){
  r <- rec[rec$code==s,]
  base <- sup0[[s]]
  if (nrow(r)==0) return(base)
  rp <- st_coordinates(st_transform(st_as_sf(r, coords=c("lon","lat"), crs=4326),5070))
  nn <- RANN::nn2(oc, rp, k=1)$nn.idx[,1]
  add <- tibble::tibble(coord_id=orig[nn]) |> count(coord_id, name="add")
  base |> full_join(add, by="coord_id") |>
    mutate(supply=tidyr::replace_na(supply,0)+tidyr::replace_na(add,0)) |> select(coord_id,supply)
}

iso <- setNames(lapply(BANDS, function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig,,drop=FALSE]; st_geometry(x)<-attr(x,"sf_column")
  st_make_valid(st_transform(x[,"coord_id"],5070))}), as.character(BANDS))

outcomes <- function(s, supdf){
  cds <- supdf$coord_id
  supply_vec <- setNames(as.numeric(supdf$supply), as.character(supdf$coord_id))
  dvec <- setNames(as.numeric(den$total_f), as.character(den$GEOID))
  memb <- lapply(as.character(BANDS), function(bb){
    ib<-iso[[bb]][iso[[bb]]$coord_id %in% cds,]
    j<-st_join(cen, ib, join=st_within, left=FALSE); tibble::tibble(coord_id=j$coord_id, GEOID=j$GEOID)})
  names(memb)<-as.character(BANDS)
  acc <- dj7_tract_access(memb, supply_vec, dvec, Wc = Wc)
  out <- dj7_weighted_outcomes(acc, den, weight_col = "total_f",
                               rurality_col = "rurality", scale = 1e5)
  c(mean = out$mean, metro = out$metro, rural = out$rural, no_access = out$no_access)
}

rows<-list()
for (s in SUBS){
  say("  %s ...", s)
  b<-outcomes(s, sup0[[s]]); a<-outcomes(s, augment(s))
  rows[[s]]<-tibble::tibble(subspec=s,
    mean_base=b["mean"], mean_rec=a["mean"],
    ratio_base=b["metro"]/b["rural"], ratio_rec=a["metro"]/a["rural"],
    noacc_base=b["no_access"], noacc_rec=a["no_access"])
  say("    ratio %.2f->%.2f  no-access %.2f->%.2f", rows[[s]]$ratio_base, rows[[s]]$ratio_rec,
      rows[[s]]$noacc_base, rows[[s]]$noacc_rec)
}
res<-bind_rows(rows)
readr::write_csv(res, file.path(OUT,"surface_recovery_2020.csv"))
cat("\n=== DONE ===\n"); print(as.data.frame(res |> mutate(across(where(is.numeric),~round(.,3)))))
