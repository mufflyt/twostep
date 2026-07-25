#!/usr/bin/env Rscript
# =============================================================================
# desjardins7/06_tract_e2sfca_denominator.R   (review issue #4 — the real test)
# -----------------------------------------------------------------------------
# Re-runs the FULL E2SFCA model (not just the geometric no-access set) under
# field-specific population denominators, and reports how the mean access,
# metro:rural ratio, and cross-specialty ranking change. Uses a tract-centroid
# implementation of the same weighting as the production engine:
#   incremental band weights on cumulative isochrone populations for demand D_j,
#   cumulative band weight of the tightest reaching band for A_i.
#   W = (30:1.00, 60:0.68, 120:0.22, 180:0.09);  w' = W_b - W_{b+1}.
# Baseline (total-female) is validated against the published national means.
#   artifacts/desjardins7/denominator_full_sensitivity_2020.csv
# =============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr) }))
ROOT <- if (requireNamespace("here", quietly=TRUE)) here::here() else normalizePath(".")
OUT  <- file.path(ROOT,"artifacts","desjardins7")
UNP  <- file.path(ROOT,"artifacts","2sfca","ec2","e2sfca_20260712_190734","unpacked")
say  <- function(...) { cat(sprintf("[dj7-e2] %s\n", sprintf(...))); flush.console() }
SUBS <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")
YR <- 2020L
Wc  <- c(`30`=1.00,`60`=0.68,`120`=0.22,`180`=0.09)          # cumulative band weights
Wi  <- c(`30`=unname(Wc["30"]-Wc["60"]), `60`=unname(Wc["60"]-Wc["120"]),  # incremental (demand)
         `120`=unname(Wc["120"]-Wc["180"]), `180`=unname(Wc["180"]))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
BANDS <- c(30L,60L,120L,180L)
FIELD <- c(MFM="repro_1544",REI="repro_1544",CFP="repro_1549",MIGS="age_1854",
           PAG="girls_019",GO="age_40p",FPMRS="age_40p")

# tract centroids + denominators + rurality
acs  <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
age  <- readRDS(file.path(OUT,"cache","acs2020_female_age.rds")) |>
  mutate(across(-GEOID, ~tidyr::replace_na(as.numeric(.),0)))
brk  <- function(d,ids) rowSums(d[,sprintf("a%d",ids),drop=FALSE],na.rm=TRUE)
den  <- age |> transmute(GEOID=as.character(GEOID),
  total_f=f_total, adult_18p=brk(age,31:49), repro_1544=brk(age,30:38),
  repro_1549=brk(age,30:39), age_1854=brk(age,31:40), girls_019=brk(age,27:31), age_40p=brk(age,38:49))
source(file.path(ROOT,"R","accessibility_stratification.R"))
ruca <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
cen  <- acs$geom |> select(GEOID) |> st_transform(5070) |> st_make_valid()
cen  <- cen[!st_is_empty(cen),]; cen <- st_centroid(cen)
cen$GEOID <- as.character(cen$GEOID)
den  <- den[match(cen$GEOID, den$GEOID),]; den$GEOID <- cen$GEOID
den  <- den |> left_join(ruca, by="GEOID")
den$rurality[is.na(den$rurality)] <- "Rural"
say("tracts=%d  total_f=%.0f", nrow(cen), sum(den$total_f))

# provider supply per subspec (coord_id, supply)
sup <- setNames(lapply(SUBS, function(s)
  readRDS(file.path(UNP, sprintf("step_4_2sfca_%s_2020_providers.rds",s))) |>
    transmute(coord_id=as.character(coord_id), supply)), SUBS)
orig <- unique(unlist(lapply(sup, function(x) x$coord_id)))

# isochrones per band (transform to 5070), restricted to 2020 origins
iso <- setNames(lapply(BANDS, function(b){
  x <- readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id <- as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x <- x[x$coord_id %in% orig,,drop=FALSE]
  st_geometry(x) <- attr(x,"sf_column") %||% "geometry"
  x <- st_transform(x[,"coord_id"], 5070); st_make_valid(x)
}), as.character(BANDS))
say("isochrones loaded for %d origins", length(orig))

`%||%` <- function(a,b) if(is.null(a)) b else a

# tract-in-band membership is denominator-independent: compute ONCE per subspec
membership <- function(s) {
  cds <- sup[[s]]$coord_id
  m <- lapply(as.character(BANDS), function(bb){
    ib <- iso[[bb]][iso[[bb]]$coord_id %in% cds,]
    j  <- st_join(cen, ib, join=st_within, left=FALSE)
    say("    %s band %s: %d (coord,tract) pairs", s, bb, nrow(j))
    tibble::tibble(coord_id=j$coord_id, GEOID=j$GEOID, band=as.integer(bb))
  })
  setNames(m, as.character(BANDS))
}

# for a subspec + denominator (reusing precomputed membership), compute outcomes
run_e2sfca <- function(s, dcol, memb) {
  sp <- sup[[s]]; cds <- sp$coord_id
  dvec <- setNames(den[[dcol]], den$GEOID)
  # demand D_j = sum_b w'_b * cumpop(<=b)
  Dj <- rep(0, length(cds)); names(Dj) <- cds
  for (bb in as.character(BANDS)) {
    cp <- memb[[bb]] |> mutate(d=dvec[GEOID]) |> group_by(coord_id) |>
      summarise(pop=sum(d,na.rm=TRUE), .groups="drop")
    add <- setNames(cp$pop, cp$coord_id)
    Dj[names(add)] <- Dj[names(add)] + Wi[[bb]]*add
  }
  Rj <- setNames(sp$supply,cds) / pmax(Dj, .Machine$double.eps)
  Rj[!is.finite(Rj)] <- 0
  # A_i = sum_j Wc[tightest band] * R_j  (tightest = max Wc across bands present)
  allpairs <- bind_rows(lapply(as.character(BANDS), function(bb)
    memb[[bb]] |> mutate(w=Wc[[bb]]))) |>
    group_by(GEOID, coord_id) |> summarise(w=max(w), .groups="drop") |>
    mutate(contrib = w * Rj[coord_id])
  Ai <- allpairs |> group_by(GEOID) |> summarise(A=sum(contrib,na.rm=TRUE), .groups="drop")
  d2 <- den |> select(GEOID, w=all_of(dcol), rurality) |> left_join(Ai, by="GEOID")
  d2$A[is.na(d2$A)] <- 0; d2$A100 <- d2$A*1e5
  wm <- function(x,w){ok<-w>0&!is.na(w); if(sum(w[ok])<=0) NA else sum(x[ok]*w[ok])/sum(w[ok])}
  tibble::tibble(subspec=s, denom=dcol,
    mean=wm(d2$A100,d2$w),
    metro=wm(d2$A100[d2$rurality=="Metropolitan"], d2$w[d2$rurality=="Metropolitan"]),
    rural=wm(d2$A100[d2$rurality=="Rural"], d2$w[d2$rurality=="Rural"]),
    no_access=100*sum(d2$w[d2$A<=0],na.rm=TRUE)/sum(d2$w,na.rm=TRUE)) |>
    mutate(ratio=metro/pmax(rural,.Machine$double.eps))
}

rows <- list()
for (s in SUBS) {
  say("  computing membership for %s ...", s)
  memb <- membership(s)
  base <- run_e2sfca(s,"total_f", memb); fld <- run_e2sfca(s,FIELD[[s]], memb)
  rows[[s]] <- bind_rows(base, fld)
  say("  %s: baseline mean=%.3f ratio=%.2f | field(%s) mean=%.3f ratio=%.2f",
      s, base$mean, base$ratio, FIELD[[s]], fld$mean, fld$ratio)
}
res <- bind_rows(rows)
readr::write_csv(res, file.path(OUT,"denominator_full_sensitivity_2020.csv"))
# rankings
base_rank <- res |> filter(denom=="total_f") |> arrange(desc(mean)) |> pull(subspec)
fld_rank  <- res |> filter(denom!="total_f") |> arrange(desc(mean)) |> pull(subspec)
say("baseline ranking: %s", paste(base_rank,collapse=">"))
say("field-denom ranking: %s", paste(fld_rank,collapse=">"))
cat("\n=== DONE ===\n"); print(as.data.frame(res |> mutate(across(where(is.numeric),~round(.,3)))))
