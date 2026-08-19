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
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
SUBS <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP"); BANDS <- c(30L,60L,120L,180L)
SCHEMES <- list(
  base    = c(`30`=1.00,`60`=0.68,`120`=0.22,`180`=0.09),
  steeper = c(`30`=1.00,`60`=0.50,`120`=0.10,`180`=0.02),
  flatter = c(`30`=1.00,`60`=0.85,`120`=0.55,`180`=0.30))
incr <- function(Wc) c(`30`=unname(Wc[1]-Wc[2]),`60`=unname(Wc[2]-Wc[3]),
                       `120`=unname(Wc[3]-Wc[4]),`180`=unname(Wc[4]))

acs <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
den <- acs$den |> transmute(GEOID=as.character(GEOID), total_f=tidyr::replace_na(total_f,0))
ruca<- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
cen <- acs$geom |> select(GEOID) |> st_transform(5070) |> st_make_valid()
cen <- cen[!st_is_empty(cen),]; cen <- st_centroid(cen); cen$GEOID <- as.character(cen$GEOID)
den <- den[match(cen$GEOID, den$GEOID),]; den$GEOID <- cen$GEOID
den <- den |> left_join(ruca, by="GEOID"); den$rurality[is.na(den$rurality)] <- "Rural"
dvec <- setNames(den$total_f, den$GEOID)

sup <- setNames(lapply(SUBS, function(s)
  readRDS(file.path(UNP,sprintf("step_4_2sfca_%s_2020_providers.rds",s))) |>
    transmute(coord_id=as.character(coord_id), supply)), SUBS)
orig <- unique(unlist(lapply(sup, function(x) x$coord_id)))
iso <- setNames(lapply(BANDS, function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig,,drop=FALSE]; st_geometry(x)<-attr(x,"sf_column")
  st_make_valid(st_transform(x[,"coord_id"],5070))}), as.character(BANDS))

wm <- function(x,w){ok<-w>0; sum(x[ok]*w[ok])/sum(w[ok])}
rows <- list()
for (s in SUBS) {
  cds <- sup[[s]]$coord_id
  say("membership for %s ...", s)
  memb <- lapply(as.character(BANDS), function(bb){
    ib<-iso[[bb]][iso[[bb]]$coord_id %in% cds,]
    j<-st_join(cen, ib, join=st_within, left=FALSE); tibble::tibble(coord_id=j$coord_id, GEOID=j$GEOID)})
  names(memb)<-as.character(BANDS)
  # cumulative population per origin per band (weight-independent)
  cumpop <- lapply(as.character(BANDS), function(bb)
    memb[[bb]] |> mutate(d=dvec[GEOID]) |> group_by(coord_id) |> summarise(p=sum(d,na.rm=TRUE),.groups="drop"))
  names(cumpop)<-as.character(BANDS)
  for (nm in names(SCHEMES)) {
    Wc <- SCHEMES[[nm]]; Wi <- incr(Wc)
    Dj <- setNames(rep(0,length(cds)),cds)
    for (bb in as.character(BANDS)) { a<-setNames(cumpop[[bb]]$p,cumpop[[bb]]$coord_id); Dj[names(a)]<-Dj[names(a)]+Wi[[bb]]*a }
    Rj <- setNames(sup[[s]]$supply,cds)/pmax(Dj,.Machine$double.eps); Rj[!is.finite(Rj)]<-0
    ap <- bind_rows(lapply(as.character(BANDS), function(bb) memb[[bb]] |> mutate(w=Wc[[bb]]))) |>
      group_by(GEOID,coord_id) |> summarise(w=max(w),.groups="drop") |> mutate(c=w*Rj[coord_id])
    Ai <- ap |> group_by(GEOID) |> summarise(A=sum(c,na.rm=TRUE),.groups="drop")
    d2 <- den |> left_join(Ai,by="GEOID"); d2$A[is.na(d2$A)]<-0; d2$A100<-d2$A*1e5
    rows[[paste(s,nm)]] <- tibble::tibble(subspec=s, scheme=nm,
      mean=wm(d2$A100,d2$total_f),
      ratio=wm(d2$A100[d2$rurality=="Metropolitan"],d2$total_f[d2$rurality=="Metropolitan"])/
            wm(d2$A100[d2$rurality=="Rural"],d2$total_f[d2$rurality=="Rural"]),
      no_access=100*sum(d2$total_f[d2$A<=0])/sum(d2$total_f))
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
