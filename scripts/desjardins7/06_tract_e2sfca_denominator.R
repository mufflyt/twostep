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
# SSOT: frozen run id from the canonical constant (scripts/manuscript_e2sfca_values.R).
source(file.path(ROOT,"scripts","manuscript_e2sfca_values.R"))
source(file.path(ROOT,"R","desjardins7_e2sfca.R"))
source(file.path(ROOT,"R","study_join_accounting.R"))
OUT  <- file.path(ROOT,"artifacts","desjardins7")
UNP  <- file.path(ROOT,"artifacts","2sfca","ec2",E2SFCA_FROZEN_RUN_ID,"unpacked")
say  <- function(...) { cat(sprintf("[dj7-e2] %s\n", sprintf(...))); flush.console() }
`%||%` <- function(a,b) if(is.null(a)) b else a
SUBS <- DJ7_SUBS
YR <- 2020L
# SSOT: band weights, bands, and the tract-centroid E2SFCA recurrence live in
# R/desjardins7_e2sfca.R (dj7_incr_weights / dj7_tract_access / dj7_weighted_outcomes).
Wc  <- DJ7_WC_BASE
BANDS <- DJ7_BANDS
FIELD <- c(MFM="repro_1544",REI="repro_1544",CFP="repro_1549",MIGS="age_1854",
           PAG="girls_019",GO="age_40p",FPMRS="age_40p")

# tract centroids + denominators + rurality
acs  <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
age  <- readRDS(file.path(OUT,"cache","acs2020_female_age.rds")) |>
  mutate(across(-GEOID, as.numeric))
brk  <- function(d,ids) rowSums(d[,sprintf("a%d",ids),drop=FALSE],na.rm=FALSE)
den  <- age |> transmute(GEOID=as.character(GEOID),
  total_f=f_total, adult_18p=brk(age,31:49), repro_1544=brk(age,30:38),
  repro_1549=brk(age,30:39), age_1854=brk(age,31:40), girls_019=brk(age,27:31), age_40p=brk(age,38:49))
source(file.path(ROOT,"R","accessibility_stratification.R"))
ruca <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
cen  <- acs$geom |> select(GEOID) |> st_transform(5070) |> st_make_valid()
cen  <- cen[!st_is_empty(cen),]; cen <- st_centroid(cen)
cen$GEOID <- as.character(cen$GEOID)
den  <- align_denominator_to_reference(
  den, cen, by = "GEOID", context = "dj7 2020 denominators",
  complete_cols = setdiff(names(den), "GEOID"))
den  <- den |> left_join(ruca, by="GEOID")
# rurality_from_ruca() returns NA for uncoded tracts (e.g. RUCA 99). That is
# UNCLASSIFIED, not Rural: dj7_weighted_outcomes() keeps them in the overall
# mean/no-access denominator but excludes them from both stratum means.
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
  sp <- sup[[s]]
  supply_vec <- stats::setNames(as.numeric(sp$supply), as.character(sp$coord_id))
  dvec <- stats::setNames(as.numeric(den[[dcol]]), as.character(den$GEOID))
  acc <- dj7_tract_access(memb, supply_vec, dvec, Wc = Wc)
  out <- dj7_weighted_outcomes(acc, den, weight_col = dcol,
                               rurality_col = "rurality", scale = 1e5)
  tibble::tibble(subspec = s, denom = dcol, mean = out$mean, metro = out$metro,
                 rural = out$rural, no_access = out$no_access) |>
    mutate(ratio = out$ratio)
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
