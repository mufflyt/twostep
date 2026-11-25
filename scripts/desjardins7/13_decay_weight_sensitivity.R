#!/usr/bin/env Rscript
# =============================================================================
# desjardins7/13_decay_weight_sensitivity.R   (review #10)
# Tests whether the rural disparity depends on the particular Gaussian decay
# weights. Re-runs the 2020 E2SFCA under three cumulative band-weight schemes:
#   base    = 1.00, 0.68, 0.22, 0.09  (primary)
#   steeper = 1.00, 0.50, 0.10, 0.02  (access decays faster; more local)
#   flatter = 1.00, 0.85, 0.55, 0.30  (access decays slower; longer reach)
# Tract-in-band membership is weight-independent, so it is computed ONCE per
# subspecialty and all three schemes are evaluated from it (cheap). Reports the
# metro:rural ratio, mean, and no-access under each scheme.
#   artifacts/desjardins7/decay_weight_sensitivity_2020.csv
# =============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr) }))
ROOT <- if (requireNamespace("here", quietly=TRUE)) here::here() else normalizePath(".")
if (!exists("E2SFCA_FROZEN_RUN_ID")) source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))  # SSOT: frozen E2SFCA run
OUT  <- file.path(ROOT,"artifacts","desjardins7")
UNP  <- file.path(ROOT,"artifacts","2sfca","ec2",E2SFCA_FROZEN_RUN_ID,"unpacked")
say  <- function(...) { cat(sprintf("[dj7-dw] %s\n", sprintf(...))); flush.console() }
source(file.path(ROOT,"R","accessibility_stratification.R"))
source(file.path(ROOT,"R","desjardins7_e2sfca.R"))
source(file.path(ROOT,"R","study_join_accounting.R"))
SUBS <- DJ7_SUBS; BANDS <- DJ7_BANDS
SCHEMES <- list(
  base    = DJ7_WC_BASE,
  steeper = c(`30`=1.00,`60`=0.50,`120`=0.10,`180`=0.02),
  flatter = c(`30`=1.00,`60`=0.85,`120`=0.55,`180`=0.30))

acs <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
cen <- acs$geom |> select(GEOID) |> st_transform(5070) |> st_make_valid()
cen <- cen[!st_is_empty(cen),]; cen <- st_centroid(cen); cen$GEOID <- as.character(cen$GEOID)
den <- acs$den |> transmute(GEOID=as.character(GEOID), total_f=total_f)
den <- align_denominator_to_reference(den, cen, by="GEOID",
  context="dj7 decay-weight denominators", complete_cols="total_f")
ruca<- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
den <- den |> left_join(ruca, by="GEOID")
# NA rurality (uncoded RUCA) stays unclassified; excluded from stratum means only.
dvec <- setNames(as.numeric(den$total_f), as.character(den$GEOID))

sup <- setNames(lapply(SUBS, function(s)
  readRDS(file.path(UNP,sprintf("step_4_2sfca_%s_2020_providers.rds",s))) |>
    transmute(coord_id=as.character(coord_id), supply)), SUBS)
orig <- unique(unlist(lapply(sup, function(x) x$coord_id)))
iso <- setNames(lapply(BANDS, function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig,,drop=FALSE]; st_geometry(x)<-attr(x,"sf_column")
  st_make_valid(st_transform(x[,"coord_id"],5070))}), as.character(BANDS))

rows <- list()
for (s in SUBS) {
  cds <- sup[[s]]$coord_id
  supply_vec <- setNames(as.numeric(sup[[s]]$supply), as.character(cds))
  say("membership for %s ...", s)
  memb <- lapply(as.character(BANDS), function(bb){
    ib<-iso[[bb]][iso[[bb]]$coord_id %in% cds,]
    j<-st_join(cen, ib, join=st_within, left=FALSE); tibble::tibble(coord_id=j$coord_id, GEOID=j$GEOID)})
  names(memb)<-as.character(BANDS)
  for (nm in names(SCHEMES)) {
    acc <- dj7_tract_access(memb, supply_vec, dvec, Wc = SCHEMES[[nm]])
    out <- dj7_weighted_outcomes(acc, den, weight_col = "total_f",
                                 rurality_col = "rurality", scale = 1e5)
    rows[[paste(s,nm)]] <- tibble::tibble(subspec=s, scheme=nm,
      mean=out$mean, ratio=out$ratio, no_access=out$no_access)
  }
  r <- dplyr::bind_rows(rows[grep(paste0("^",s," "),names(rows))])
  say("  %s ratio base/steeper/flatter = %.2f / %.2f / %.2f", s,
      r$ratio[r$scheme=="base"], r$ratio[r$scheme=="steeper"], r$ratio[r$scheme=="flatter"])
}
res <- dplyr::bind_rows(rows)
readr::write_csv(res, file.path(OUT,"decay_weight_sensitivity_2020.csv"))
rr <- res |> group_by(subspec) |> summarise(ratio_range=max(ratio)-min(ratio), .groups="drop")
say("max metro:rural ratio RANGE across weight schemes (any field): %.3f", max(rr$ratio_range))
cat("\n=== DONE ===\n"); print(as.data.frame(res |> mutate(across(where(is.numeric),~round(.,3)))))
