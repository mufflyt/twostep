#!/usr/bin/env Rscript
# ==============================================================================
# sensitivity_e2sfca_2020.R
# ------------------------------------------------------------------------------
# Sensitivity analysis for the 2020 E2SFCA accessibility surfaces. Recomputes,
# for every subspecialty, the national population-weighted mean access and the
# rural-vs-metropolitan and American Indian/Alaska Native-vs-White contrasts under
# alternative modeling assumptions, to test whether the manuscript's headline
# findings (subspecialty ordering; rural and AIAN disadvantage) are robust.
#
# Axes varied (2020 cohort, canonical isochrones + ACS 2020):
#   * distance-decay weights : base (1.00/0.68/0.22/0.09) vs sharper vs slower
#   * catchment bands        : drop the 180-min band (30/60/120 only)
#   * grid resolution        : 500 m vs 1000 m
#   * decay FORM             : zonal presets vs a four-band Gaussian-derived zonal
#                              approximation (McGrail 2012) -- NOT continuous decay
#   * maldistribution        : M2SFCA (Delamater 2013), step2_power = 2, whose
#                              access increments are diff(W^2) (not diff(W)^2)
#   * variable catchments    : tighter (urban) decay for metro tracts + wider
#                              (rural) decay for rural tracts (McGrail & Humphreys
#                              2009), composited by tract rurality  [VAR block]
#
# Method: the E2SFCA surface is recomputed with compute_e2sfca_raster() (the same
# engine as production); the demand denominator is total female population on a
# mass-conserving grid (identical estimand to the canonical run). Rurality and
# race subgroup means re-weight the SAME surface by subgroup female population,
# allocated to grid cells by the same area-weighted rule. No values are hardcoded.
#
# Output: artifacts/2sfca/sensitivity/sensitivity_2020.csv  (+ console summary),
#   sensitivity_2020_manifest.json (frozen inputs + SHA-256, for reproducibility).
# QUICK=1 -> 1 subspecialty (GO), variants base/gaussian/m2sfca, 1000 m (smoke).
#   The exploratory metro/rural composite runs ONLY with RUN_EXPLORATORY_COMPOSITE=1
#   (it is a post-hoc two-surface composite, NOT a consistent dynamic-catchment
#   E2SFCA, and is not a national estimate; excluded from the default run).
# Freeze inputs for a publication run via E2SFCA_YCM_PATH / E2SFCA_COHORT_PATH;
# the manifest records the SHA-256 of whatever was used either way.
#
# PRIMARY SOURCES (full list + per-function mapping: R/two_step_floating_catchment.R
#   module header). The variants here trace to:
#   base/E2SFCA weights ...... Luo & Qi (2009)      doi:10.1016/j.healthplace.2009.06.002
#   gaussian decay form ...... McGrail (2012)       doi:10.1186/1476-072X-11-50
#   variable urban/rural ..... McGrail & Humphreys (2009) doi:10.1016/j.apgeog.2008.12.003
#   m2sfca penalty ........... Delamater (2013)     doi:10.1016/j.healthplace.2013.07.012
#   (relative access / SPAR .. Wan, Zhan, Zou & Chow (2012) doi:10.1016/j.apgeog.2011.05.001)
#   Original 2SFCA baseline .. Luo & Wang (2003)    doi:10.1068/b29120
# See docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md for how this script is run and gated.
# ==============================================================================
suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
source(file.path(ROOT, "R", "accessibility_stratification.R"))
options(tigris_use_cache = TRUE)
OUT <- file.path(ROOT, "artifacts", "2sfca", "sensitivity")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
CACHE <- file.path(OUT, "cache"); dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[sens] %s\n", sprintf(...)))
RUN_STARTED <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
sha256 <- function(p) if (!is.null(p) && file.exists(p)) digest::digest(file = p, algo = "sha256") else NA_character_
QUICK <- Sys.getenv("QUICK") == "1"
RUN_COMPOSITE <- Sys.getenv("RUN_EXPLORATORY_COMPOSITE") == "1"
YR <- 2020L; ACS_YR <- 2020L
SUBS <- if (QUICK) c("GO") else c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
# SSOT anchor (CONUS_STATE_FIPS): canonical CONUS set in scripts/manuscript_e2sfca_values.R; guarded by tests/testthat/test-ssot-conus-fips.R
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

# ---- parameter variants ------------------------------------------------------
# Each: named cumulative-band weights (monotone non-increasing) + which bands.
# SSOT: canonical base weights come from the engine sourced above
# (E2SFCA_DEFAULT_WEIGHTS in R/two_step_floating_catchment.R). The sharper/slower/
# drop180 vectors below are deliberate sensitivity variants, not copies of the base.
.BASE_W <- E2SFCA_DEFAULT_WEIGHTS
VARIANTS <- list(
  base     = list(w = .BASE_W,                                     res = 1000L),
  sharper  = list(w = c("30"=1.00,"60"=0.42,"120"=0.09,"180"=0.02), res = 1000L),
  slower   = list(w = c("30"=1.00,"60"=0.85,"120"=0.55,"180"=0.30), res = 1000L),
  drop180  = list(w = c("30"=1.00,"60"=0.68,"120"=0.22),            res = 1000L),
  res500   = list(w = .BASE_W,                                     res = 500L),
  # four-band Gaussian-derived zonal decay (McGrail 2012) vs the zonal presets
  gaussian = list(w = gaussian_band_weights(c(30L,60L,120L,180L), sigma = 60), res = 1000L),
  # M2SFCA (Delamater 2013): step-2 access uses diff(W^2) to penalize maldistribution
  m2sfca   = list(w = .BASE_W, step2_power = 2, res = 1000L)
)
if (QUICK) VARIANTS <- VARIANTS[c("base","gaussian","m2sfca")]

# ---- canonical inputs (frozen: explicit path OR newest-by-mtime for smoke) ----
newest <- function(p){f<-list.files(file.path(ROOT,"artifacts"),p,recursive=TRUE,full.names=TRUE)
  f[order(file.info(f)$mtime,decreasing=TRUE)][1]}
pick <- function(env, pat){ p <- Sys.getenv(env, "")
  if (nzchar(p)) { stopifnot("frozen input path does not exist" = file.exists(p)); return(p) }
  newest(pat) }   # mtime selection is a SMOKE convenience; freeze via env for publication
ycm_path    <- pick("E2SFCA_YCM_PATH",    "^step_3_year_coord_map\\.rds$")
cohort_path <- pick("E2SFCA_COHORT_PATH", "^step_2\\.5_final_cohort\\.rds$")
say("inputs: ycm=%s  cohort=%s", basename(ycm_path), basename(cohort_path))
ycm    <- readRDS(ycm_path)
cohort <- readRDS(cohort_path)

# ACS 2020 tract geometry + total-female / White-NH / AIAN female denominators
acs_cf <- file.path(CACHE, "acs2020_tracts.rds")
if (file.exists(acs_cf)) { acs <- readRDS(acs_cf); say("loaded cached ACS 2020 tracts")
} else {
  say("fetching ACS 2020 tract geometry + denominators")
  vars <- c(total_f = "B01001_026", white_f = "B01001H_017", aian_f = "B01001C_017")
  raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=vars, state=s, year=ACS_YR, geometry=TRUE)))
  geom <- raw |> dplyr::distinct(GEOID, .keep_all=TRUE) |> sf::st_as_sf() |> dplyr::select(GEOID)
  geom$GEOID <- as.character(geom$GEOID)
  wide <- raw |> sf::st_drop_geometry() |>
    dplyr::transmute(GEOID=as.character(GEOID), variable, estimate=as.numeric(estimate)) |>
    tidyr::pivot_wider(names_from=variable, values_from=estimate)
  acs <- list(geom=geom, den=wide); saveRDS(acs, acs_cf)
}
# RUCA 2020 -> rurality; split total female into metro/rural weights
ruca <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"), colClasses="character") |>
  dplyr::transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(ruca_code))
den <- acs$den |> dplyr::left_join(ruca, by="GEOID") |>
  dplyr::mutate(dplyr::across(c(total_f,white_f,aian_f), ~tidyr::replace_na(.,0)),
    metro_f = ifelse(rurality %in% "Metropolitan", total_f, 0),
    rural_f = ifelse(rurality %in% "Rural",        total_f, 0))
say("tracts=%d  total F=%.0f  metro=%.0f rural=%.0f  White=%.0f AIAN=%.0f",
    nrow(den), sum(den$total_f), sum(den$metro_f), sum(den$rural_f),
    sum(den$white_f), sum(den$aian_f))

# isochrones (all bands) filtered to 2020 origins across all requested subspecs
sup_all <- setNames(lapply(SUBS, function(s) compute_provider_supply(ycm, cohort, s, YR)), SUBS)
orig_all <- unique(unlist(lapply(sup_all, function(s) as.character(s$coord_id))))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_all <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b){
  x<-readRDS(file.path(ROOT,"artifacts","isochrones",sprintf("isochrones_%dmin_consolidated.rds",b)))
  x$coord_id<-as.character(if("coord_id"%in%names(x)) x$coord_id else x$location_key)
  x<-x[x$coord_id %in% orig_all,,drop=FALSE]; if(!"drive_time_minutes"%in%names(x)) x$drive_time_minutes<-b
  x<-x[,c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x)<-"geometry"; x }))
say("loaded isochrones for %d origins", length(orig_all))

# ---- per-resolution grid + subgroup pop rasters (built once, reused) ---------
build_grid <- function(res){
  gg   <- build_e2sfca_grid_geometry(acs$geom, resolution = res)
  # primary demand denominator = total female (matches production estimand)
  grid <- attach_e2sfca_population(gg, den[,c("GEOID","total_f")], "total_f", alloc="area")
  # subgroup weight rasters on the SAME grid geometry (area-weighted allocation)
  wr <- list(total = grid$pop_rast)
  for (col in c("metro_f","rural_f","white_f","aian_f"))
    wr[[col]] <- attach_e2sfca_population(gg, den[,c("GEOID",col)], col, alloc="area")$pop_rast
  list(grid = grid, wr = wr)
}
GRIDS <- list()  # cache per resolution
get_grid <- function(res){ k<-as.character(res)
  if (is.null(GRIDS[[k]])) { say("building %dm grid + subgroup rasters", res); GRIDS[[k]] <<- build_grid(res) }
  GRIDS[[k]] }

# population-weighted mean of a surface by a weight raster (NA access -> 0)
wmean_rast <- function(surf_scaled, wrast){
  a <- terra::values(surf_scaled)[,1]; w <- terra::values(wrast)[,1]
  a[is.na(a)] <- 0; w[is.na(w)] <- 0
  if (sum(w) <= 0) return(NA_real_)
  sum(a * w) / sum(w)
}

# ---- run all (variant x subspecialty) ---------------------------------------
rows <- list()
for (vn in names(VARIANTS)){
  v <- VARIANTS[[vn]]; res <- v$res; G <- get_grid(res)
  bands <- as.integer(names(v$w))
  iso_v <- iso_all[iso_all$drive_time_minutes %in% bands,,drop=FALSE]
  iso_ctx <- prepare_e2sfca_iso(iso_v, area_crs = E2SFCA_AREA_CRS)
  for (s in SUBS){
    sup_s <- sup_all[[s]]
    iso_s <- prepare_e2sfca_iso(iso_v[iso_v$coord_id %in% as.character(sup_s$coord_id),,drop=FALSE],
                                area_crs = E2SFCA_AREA_CRS)
    r <- compute_e2sfca_raster(G$grid, iso_s, sup_s, weights = v$w,
                               step2_power = if (is.null(v$step2_power)) 1 else v$step2_power,
                               per_capita_scale = 1e5, return_surface = TRUE)
    surf <- r$surface * 1e5
    m_nat   <- r$national$mean_population_weighted_scaled
    m_total <- wmean_rast(surf, G$wr$total)   # cross-check vs m_nat
    m_metro <- wmean_rast(surf, G$wr$metro_f)
    m_rural <- wmean_rast(surf, G$wr$rural_f)
    m_white <- wmean_rast(surf, G$wr$white_f)
    m_aian  <- wmean_rast(surf, G$wr$aian_f)
    rows[[paste(vn,s)]] <- tibble::tibble(variant=vn, res=res, subspec=s,
      national=m_nat, national_check=m_total, metro=m_metro, rural=m_rural,
      white=m_white, aian=m_aian,
      rural_metro_ratio = m_rural/m_metro, aian_white_ratio = m_aian/m_white)
    say("  %-7s %-5s nat=%.3f (chk %.3f) rural/metro=%.3f aian/white=%.3f",
        vn, s, m_nat, m_total, m_rural/m_metro, m_aian/m_white)
  }
}
res_tbl <- dplyr::bind_rows(rows)

# ---- EXPLORATORY metro/rural surface composite (OFF by default) ---------------
# NOTE: this is NOT a consistent dynamic-catchment E2SFCA and NOT a national
# estimate. It builds two COMPLETE national surfaces (urban-sharp, rural-slow) and
# reads metro population from the sharp surface and rural population from the slow
# surface -- a POST-HOC composite whose provider denominators are separately
# recomputed under each full national decay model, not one internally consistent
# location-specific catchment rule applied through both E2SFCA steps. Its value
# also omits micropolitan/other tracts. Do NOT call it national, dynamic-catchment
# E2SFCA, or a McGrail & Humphreys replication; do NOT use for a robustness claim.
# A consistent implementation must apply the catchment rule inside BOTH steps.
if (RUN_COMPOSITE) {
  say("EXPLORATORY metro/rural composite (NOT national, NOT dynamic-catchment E2SFCA)")
  Gv <- get_grid(1000L)
  W_URBAN <- c("30"=1.00,"60"=0.42,"120"=0.09,"180"=0.02)   # tight urban catchment
  W_RURAL <- c("30"=1.00,"60"=0.85,"120"=0.55,"180"=0.30)   # wide rural catchment
  pm <- sum(terra::values(Gv$wr$metro_f)[,1], na.rm=TRUE)
  pr <- sum(terra::values(Gv$wr$rural_f)[,1], na.rm=TRUE)
  var_rows <- list()
  for (s in SUBS){
    sup_s <- sup_all[[s]]
    iso_s <- prepare_e2sfca_iso(
      iso_all[iso_all$coord_id %in% as.character(sup_s$coord_id),,drop=FALSE],
      area_crs = E2SFCA_AREA_CRS)
    su <- compute_e2sfca_raster(Gv$grid, iso_s, sup_s, weights=W_URBAN,
                                per_capita_scale=1e5, return_surface=TRUE)$surface * 1e5
    sr <- compute_e2sfca_raster(Gv$grid, iso_s, sup_s, weights=W_RURAL,
                                per_capita_scale=1e5, return_surface=TRUE)$surface * 1e5
    m_metro <- wmean_rast(su, Gv$wr$metro_f)
    m_rural <- wmean_rast(sr, Gv$wr$rural_f)
    composite <- (m_metro*pm + m_rural*pr) / (pm + pr)   # metro+rural only, NOT national
    var_rows[[s]] <- tibble::tibble(variant="exploratory_metro_rural_composite",
      res=1000L, subspec=s, national=NA_real_, national_check=NA_real_,
      metro=m_metro, rural=m_rural, white=NA_real_, aian=NA_real_,
      rural_metro_ratio=m_rural/m_metro, aian_white_ratio=NA_real_,
      exploratory_metro_rural_composite=composite)
    say("  %-5s EXPLORATORY composite=%.3f (metro=%.3f rural=%.3f) -- not national",
        s, composite, m_metro, m_rural)
  }
  res_tbl <- dplyr::bind_rows(res_tbl, dplyr::bind_rows(var_rows))
} else {
  say("exploratory metro/rural composite skipped (set RUN_EXPLORATORY_COMPOSITE=1 to enable)")
}

# ---- NUMERICAL RUN GATES (fail the run if any contract is violated) ----------
main_rows <- dplyr::filter(res_tbl, variant %in% names(VARIANTS))
{
  # (a) national vs independent cross-check agree
  bad <- dplyr::filter(main_rows, is.finite(national), is.finite(national_check),
                       abs(national - national_check) > 1e-6 * pmax(abs(national), 1))
  if (nrow(bad)) stop(sprintf("GATE: national != national_check for %d rows (worst rel %.2e)",
    nrow(bad), max(abs(bad$national-bad$national_check)/pmax(abs(bad$national),1))))
  # (b) national finite and non-negative
  if (any(!is.finite(main_rows$national))) stop("GATE: non-finite national in a main variant")
  if (any(main_rows$national < 0))         stop("GATE: negative national access")
  # (c) exactly one row per (variant, subspec), all expected cells present
  if (anyDuplicated(main_rows[, c("variant","subspec")])) stop("GATE: duplicate (variant,subspec) rows")
  need <- paste(rep(names(VARIANTS), each=length(SUBS)), SUBS)
  miss <- setdiff(need, paste(main_rows$variant, main_rows$subspec))
  if (length(miss)) stop(sprintf("GATE: missing %d variant x subspec cells (e.g. %s)",
                                 length(miss), miss[1]))
  # (d) M2SFCA national <= base E2SFCA per subspec (Step-2 discounted; Step-1 ratios unchanged)
  jm <- dplyr::inner_join(
    dplyr::filter(main_rows, variant=="base")[,c("subspec","national")],
    dplyr::filter(main_rows, variant=="m2sfca")[,c("subspec","national")],
    by="subspec", suffix=c("_base","_m2"))
  if (any(jm$national_m2 > jm$national_base * (1 + 1e-6)))
    stop("GATE: M2SFCA national exceeds base E2SFCA for some subspecialty")
  say("numerical gates PASSED (%d main-variant rows across %d subspecs)", nrow(main_rows), length(SUBS))
}

CSV <- file.path(OUT, if (QUICK) "sensitivity_2020_QUICK.csv" else "sensitivity_2020.csv")
readr::write_csv(res_tbl, CSV); say("wrote %s", CSV)

# ---- REPRODUCIBILITY MANIFEST (frozen inputs + SHA-256) ----------------------
ISO_PATHS <- file.path(ROOT,"artifacts","isochrones",
                       sprintf("isochrones_%dmin_consolidated.rds", c(30,60,120,180)))
RUCA_PATH <- file.path(ROOT,"data","external","ruca_tract_mapping.csv")
manifest <- list(
  code_commit = tryCatch(system("git rev-parse HEAD", intern=TRUE), error=function(e) NA_character_),
  quick = QUICK, run_composite = RUN_COMPOSITE,
  run_started = RUN_STARTED, run_completed = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  ycm    = list(path = ycm_path,    sha256 = sha256(ycm_path)),
  cohort = list(path = cohort_path, sha256 = sha256(cohort_path)),
  isochrones = lapply(ISO_PATHS, function(p) list(path = p, sha256 = sha256(p))),
  acs_cache  = list(path = acs_cf,   sha256 = sha256(acs_cf)),
  ruca       = list(path = RUCA_PATH, sha256 = sha256(RUCA_PATH)),
  tract_count = nrow(den),
  population_total = sum(den$total_f),
  provider_count_by_subspec = setNames(lapply(SUBS, function(s) sum(sup_all[[s]]$supply)), SUBS),
  variants = lapply(names(VARIANTS), function(vn) list(
    name = vn, res = VARIANTS[[vn]]$res, weights = as.list(VARIANTS[[vn]]$w),
    step2_power = if (is.null(VARIANTS[[vn]]$step2_power)) 1 else VARIANTS[[vn]]$step2_power)),
  subspecialties = SUBS)
MANI <- file.path(OUT, if (QUICK) "sensitivity_2020_QUICK_manifest.json" else "sensitivity_2020_manifest.json")
jsonlite::write_json(manifest, MANI, auto_unbox = TRUE, pretty = TRUE, null = "null")
say("wrote manifest %s", MANI)

# ---- robustness summary ------------------------------------------------------
base <- dplyr::filter(res_tbl, variant=="base")
cat("\n=== ROBUSTNESS SUMMARY (vs base) ===\n")
for (vn in setdiff(names(VARIANTS),"base")){
  vv <- dplyr::filter(res_tbl, variant==vn)
  j <- dplyr::inner_join(base, vv, by="subspec", suffix=c("_b","_v"))
  rho <- suppressWarnings(cor(j$national_b, j$national_v, method="spearman"))
  rc  <- suppressWarnings(cor(j$rural_metro_ratio_b, j$rural_metro_ratio_v))
  cat(sprintf("%-8s: national-mean rank rho=%.3f | rural/metro corr=%.3f | rural<metro in %d/%d | aian<white in %d/%d\n",
    vn, rho, rc, sum(vv$rural_metro_ratio < 1, na.rm=TRUE), nrow(vv),
    sum(vv$aian_white_ratio < 1, na.rm=TRUE), nrow(vv)))
}
cat(sprintf("\nbase: rural<metro in %d/%d subspecs; aian<white in %d/%d subspecs\n",
  sum(base$rural_metro_ratio<1,na.rm=TRUE), nrow(base),
  sum(base$aian_white_ratio<1,na.rm=TRUE), nrow(base)))
cat("DONE\n")
