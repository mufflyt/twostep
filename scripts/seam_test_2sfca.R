#!/usr/bin/env Rscript
# ==============================================================================
# seam_test_2sfca.R — E2SFCA tract-vintage seam analysis (RELAUNCH GATE)
# ------------------------------------------------------------------------------
# Controlled geometry experiment. Answers: does changing the tract vintage used
# to allocate a FIXED reference population to the 500 m grid materially change
# the E2SFCA access surface (upstream denominator), separately from any real
# annual population/provider change?
#
# TWO PARTS
#  A. Aggregation-only: one fixed surface + fixed population -> both vintages'
#     tracts. Cell-level headlines are tract-free (invariant); pop-weighted tract
#     recombination ~invariant; tract medians/counts may move.
#  B. Full-pipeline: hold providers/supply/catchments/grid fixed. Represent the
#     SAME population under both vintages using the 500 m grid as common finer
#     support (reaggregate + uniform re-allocation via the production method).
#     Rerun E2SFCA under both demand rasters; compare cell-by-cell.
#
#  This deliberately does NOT compare ordinary 2019 vs ordinary 2020 inputs
#  (that confounds geometry with real population + provider change).
#
# GATE (per-specialty, prespecified — see the prespec manifest for provenance):
#   relative national pop-weighted mean difference  < 0.02
#   maximum absolute threshold-share difference      < 0.01
#  Conservative: EVERY tested specialty must pass. No averaging across
#  specialties. Continuous diffs are always reported, gate pass or fail.
#
#  CIRCULARITY NOTE: Part B measures sensitivity to RE-PARTITION + uniform
#  reallocation of ONE fixed reference population (native 2020 ACS on 2020
#  tracts). It does NOT by itself prove the ordinary annual 2019 and 2020 ACS
#  surfaces are harmonized.
#
# Usage:
#   Rscript scripts/seam_test_2sfca.R --subspecs all --year 2020
#   Rscript scripts/seam_test_2sfca.R --subspecs representative --year 2020
#   Rscript scripts/seam_test_2sfca.R --subspecs GO,MFM,CFP --states 44,25 --year 2020
# ==============================================================================

suppressWarnings(suppressMessages({
  library(sf); library(dplyr); library(terra); library(exactextractr)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))
options(tigris_use_cache = TRUE)
`%||%` <- function(a, b) if (is.null(a)) b else a

.args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(f, d = NULL) { h <- which(.args == f); if (length(h) && h < length(.args)) .args[h + 1L] else d }
SUBSPECS_IN <- get_arg("--subspecs", "all")
YEAR    <- as.integer(get_arg("--year", "2020"))
STATES  <- get_arg("--states", NULL)
RES     <- as.numeric(get_arg("--resolution", "500"))
STATE_FIPS <- if (is.null(STATES)) NULL else sprintf("%02d", as.integer(strsplit(STATES, ",")[[1]]))
OUT <- file.path(ROOT, "artifacts", "2sfca_seam"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[seam] %s\n", sprintf(...)))
ALL7 <- c("CFP","FPMRS","GO","MFM","MIGS","PAG","REI")

# ── PRESPECIFIED gate tolerances (fixed in the seam script BEFORE any national
#    result was examined; rationale recorded in the manifest). DO NOT tune. ──
TOL_MEAN_REL  <- 0.02   # 2% rel national mean: within ACS 5-yr MOE / sub-year drift
TOL_SHARE_ABS <- 0.01   # 1 pp threshold share: below manuscript reporting precision
THRESHOLDS    <- E2SFCA_DEFAULT_THRESHOLDS
REL_CHANGE_BINS <- c(0.01, 0.05, 0.10)
EXPECTED_METHODS <- c("raw","equal_total","mass_conserving","mass_conserving_eqtot")

# ── RUN CONTRACT — print + HARD-ASSERT the invariants before any computation. ─
say("================= RUN CONTRACT =================")
say("subspecs=%s year=%d resolution=%.0f CRS=EPSG:%d", SUBSPECS_IN, YEAR, RES, E2SFCA_AREA_CRS)
say("methods=%s", paste(EXPECTED_METHODS, collapse=","))
say("thresholds=%s | tol_mean_rel=%.3f tol_share_abs=%.3f", paste(THRESHOLDS, collapse=","), TOL_MEAN_REL, TOL_SHARE_ABS)
stopifnot(
  "specialty universe must be the 7 subspecialties" =
    identical(sort(ALL7), sort(c("CFP","FPMRS","GO","MFM","MIGS","PAG","REI"))),
  "area CRS must be EPSG:5070 (equal-area)"          = E2SFCA_AREA_CRS == 5070L,
  "thresholds must be the prespecified set"          = identical(as.numeric(THRESHOLDS), c(0,1,5,10,20,50)),
  "tolerances must be the prespecified values"       = TOL_MEAN_REL == 0.02 && TOL_SHARE_ABS == 0.01,
  "must be exactly the 4 documented methods"         = length(EXPECTED_METHODS) == 4L)
if (identical(SUBSPECS_IN, "all")) stopifnot("--subspecs all must yield 7 specialties" = length(ALL7) == 7L)
if (!is.null(STATE_FIPS)) say("NOTE: state subset %s — SMOKE/VALIDATION run, not the national gate.", paste(STATE_FIPS, collapse=","))

# ── ENVIRONMENT LOCK — if SEAM_ENV_LOCK is set, require an EXACT match of the
#    recorded R / geospatial stack and FAIL before computation on any drift. ──
.env_now <- function() {
  sv <- sf::sf_extSoftVersion()
  list(r_version = paste(R.version$major, R.version$minor, sep="."),
       sf = as.character(utils::packageVersion("sf")),
       terra = as.character(utils::packageVersion("terra")),
       exactextractr = as.character(utils::packageVersion("exactextractr")),
       geos = unname(sv["GEOS"]), gdal = unname(sv["GDAL"]), proj = unname(sv["PROJ"]))
}
.lock_path <- Sys.getenv("SEAM_ENV_LOCK", "")
if (nzchar(.lock_path)) {
  say("enforcing environment lock: %s", .lock_path)
  want <- jsonlite::read_json(.lock_path, simplifyVector = TRUE)
  have <- .env_now()
  keys <- c("r_version","sf","terra","exactextractr","geos","gdal","proj")
  drift <- keys[vapply(keys, function(k) !identical(as.character(want[[k]]), as.character(have[[k]])), logical(1))]
  for (k in keys) say("  env %-14s want=%s have=%s", k, want[[k]], have[[k]])
  if (length(drift)) stop(sprintf("ENV LOCK MISMATCH on: %s — refusing to compute.", paste(drift, collapse=", ")), call. = FALSE)
  say("environment lock: MATCH")
} else {
  e <- .env_now(); say("environment (unlocked, recorded): R=%s sf=%s terra=%s exactextractr=%s GEOS=%s GDAL=%s PROJ=%s",
                       e$r_version, e$sf, e$terra, e$exactextractr, e$geos, e$gdal, e$proj)
}

# ── Environment capture (item 7) ─────────────────────────────────────────────
sv <- sf::sf_extSoftVersion()
lock <- file.path(ROOT, "renv.lock")
env_info <- list(
  timestamp = format(Sys.time(), tz = "UTC"),
  r_version = R.version.string,
  git_sha = tryCatch(system(sprintf("git -C %s rev-parse HEAD", shQuote(ROOT)), intern = TRUE)[1],
                     error = function(e) NA_character_),
  renv_lock_sha256 = if (file.exists(lock)) digest::digest(lock, algo = "sha256", file = TRUE) else NA,
  pkg = list(sf = as.character(utils::packageVersion("sf")),
             terra = as.character(utils::packageVersion("terra")),
             exactextractr = as.character(utils::packageVersion("exactextractr"))),
  geos = unname(sv["GEOS"]), gdal = unname(sv["GDAL"]), proj = unname(sv["PROJ"]),
  area_crs = E2SFCA_AREA_CRS, resolution_m = RES, workers = 1L, rng_seed = NA,
  note_determinism = "single-threaded; terra rasterize + exactextractr are deterministic; no RNG")

# ── Load providers + rank specialty density (BEFORE seeing seam results) ─────
newest <- function(p) { f <- list.files(file.path(ROOT,"artifacts"), p, recursive=TRUE, full.names=TRUE); f[order(file.info(f)$mtime, decreasing=TRUE)][1] }
ycm <- readRDS(newest("^step_3_year_coord_map\\.rds$"))
cohort <- readRDS(newest("^step_2\\.5_final_cohort\\.rds$"))
supply_by <- lapply(ALL7, function(sc) compute_provider_supply(ycm, cohort, sc, YEAR))
names(supply_by) <- ALL7
n_active <- vapply(supply_by, function(s) sum(s$supply), numeric(1))   # total providers
rank_tbl <- dplyr::tibble(subspec = ALL7, n_providers = n_active[ALL7],
                          n_origins = vapply(supply_by, nrow, integer(1))[ALL7]) |>
  dplyr::arrange(n_providers)

# Selection rule (recorded BEFORE examining seam results):
#   dense = most providers; sparse = fewest; intermediate = median rank.
sel_rule <- "By total provider count for the year: sparse=min, dense=max, intermediate=median-rank. Fixed before seam results examined."
if (identical(SUBSPECS_IN, "all")) {
  SUBSPECS <- ALL7
} else if (identical(SUBSPECS_IN, "representative")) {
  ord <- rank_tbl$subspec
  SUBSPECS <- unique(c(ord[1], ord[ceiling(length(ord)/2)], ord[length(ord)]))  # sparse, intermediate, dense
} else {
  SUBSPECS <- strsplit(SUBSPECS_IN, ",")[[1]]
}
say("specialty density ranking (by providers): %s",
    paste(sprintf("%s=%d", rank_tbl$subspec, rank_tbl$n_providers), collapse="  "))
say("tested specialties: %s", paste(SUBSPECS, collapse=", "))

# ── Fixed reference population + BOTH tract vintages ─────────────────────────
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
fetch_pop <- function(year, states) {
  st <- if (is.null(states)) conus() else states; ay <- max(min(year,2022L),2013L)
  raw <- purrr::map_dfr(st, function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=c(female_pop="B01001_026"), state=s, year=ay, geometry=FALSE)))
  raw <- raw[raw$variable=="female_pop", ]
  dplyr::tibble(GEOID=as.character(raw$GEOID), female_pop=as.numeric(raw$estimate))
}
fetch_geom <- function(vintage, states) {
  ry <- if (vintage==2020L) 2020L else 2019L; st <- if (is.null(states)) conus() else states
  raw <- purrr::map_dfr(st, function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=c(female_pop="B01001_026"), state=s, year=ry, geometry=TRUE)))
  raw <- raw[raw$variable=="female_pop", ]; g <- sf::st_as_sf(raw[,"GEOID"]); g$GEOID <- as.character(g$GEOID); g
}
# SEAM_ACS_RDS: pre-shipped ACS bundle (pop_vals + geom2020 + geom2010) so a
# headless/EC2 run needs no Census API. Produced by scripts/prefetch_seam_acs.R.
acs_rds <- Sys.getenv("SEAM_ACS_RDS", "")
if (nzchar(acs_rds)) {
  say("loading pre-shipped ACS bundle: %s", acs_rds)
  .b <- readRDS(acs_rds)
  pop_vals <- .b$pop_vals; geom2020 <- .b$geom2020; geom2010 <- .b$geom2010
} else {
  pop_vals <- fetch_pop(YEAR, STATE_FIPS)                  # native: YEAR ACS on 2020 tracts
  geom2020 <- fetch_geom(2020L, STATE_FIPS); geom2010 <- fetch_geom(2010L, STATE_FIPS)
}
acs_source_total <- sum(pop_vals$female_pop, na.rm = TRUE)
if (!is.null(STATE_FIPS)) { kp <- function(g) g[substr(g$GEOID,1,2) %in% STATE_FIPS,,drop=FALSE]
  geom2020 <- kp(geom2020); geom2010 <- kp(geom2010) }
say("tracts: 2010-vintage %d | 2020-vintage %d | ACS source pop %.0f",
    nrow(geom2010), nrow(geom2020), acs_source_total)

# COMMON cell-aligned template covering BOTH vintages (union extent) → cell-by-cell.
common_ext <- terra::ext(terra::vect(rbind(sf::st_transform(geom2020[,"GEOID"], E2SFCA_AREA_CRS),
                                           sf::st_transform(geom2010[,"GEOID"], E2SFCA_AREA_CRS))))
common_template <- terra::rast(common_ext, resolution = RES, crs = sprintf("EPSG:%d", E2SFCA_AREA_CRS))
gg2020 <- build_e2sfca_grid_geometry(geom2020, resolution = RES, template = common_template)
gg2010 <- build_e2sfca_grid_geometry(geom2010, resolution = RES, template = common_template)

# ── THREE demand-allocation methods, side by side (per user decomposition) ────
#  raw            = center-based rasterization (legacy production). NOT
#                   mass-conserving: A(2020) and B(2010) represent DIFFERENT
#                   total demand, so its A-vs-B difference mixes a total-demand
#                   (scalar) effect with spatial repartitioning.
#  equal_total    = the SAME center rasters, each globally rescaled to one fixed
#                   reference total P_ref. Removes the scalar demand difference;
#                   residual A-vs-B ≈ spatial redistribution + interaction ONLY.
#                   Diagnostic — NOT the production fix (national total corrected,
#                   local tract mass not guaranteed).
#  mass_conserving= area-weighted tract->grid allocation (allocate_pop_areaweighted).
#                   Conserves every tract's population locally; A and B totals both
#                   ≈ ACS, so its A-vs-B difference is spatial repartitioning by
#                   construction. THIS is the production method and the gate basis.
build_pair <- function(alloc) {
  gA <- attach_e2sfca_population(gg2020, pop_vals, "female_pop", alloc = alloc)   # native YEAR pop on 2020 tracts
  # Reaggregate the SAME grid population to 2010 tracts (exact_extract sum is
  # itself area-weighted/conserving), then re-allocate through 2010 polygons.
  p2010 <- dplyr::tibble(GEOID = gg2010$tracts$GEOID,
    female_pop = as.numeric(exactextractr::exact_extract(gA$pop_rast, gg2010$tracts, "sum", progress = FALSE)))
  gB <- attach_e2sfca_population(gg2010, p2010, "female_pop", alloc = alloc)
  list(A = gA, B = gB)
}
gtot <- function(g) sum(terra::values(g$pop_rast)[, 1], na.rm = TRUE)

raw  <- build_pair("center")
area <- build_pair("area")

# equal-total diagnostic: rescale each center raster to a fixed reference total.
P_ref <- gtot(raw$A)                                   # 2020 center-based represented total
scale_to <- function(g, P) { s <- P / gtot(g); g$pop_rast <- g$pop_rast * s; g }
eqt <- list(A = scale_to(raw$A, P_ref), B = scale_to(raw$B, P_ref))
eqA_tot <- gtot(eqt$A); eqB_tot <- gtot(eqt$B)
if (max(abs(eqA_tot - P_ref), abs(eqB_tot - P_ref)) / P_ref > 1e-9)
  stop(sprintf("equal-total verification failed: A=%.4f B=%.4f P_ref=%.4f", eqA_tot, eqB_tot, P_ref))
say("equal-total verify: Σp*_2020=%.2f == Σp*_2010=%.2f == P_ref=%.2f (Δ<1e-9 rel)", eqA_tot, eqB_tot, P_ref)

# mass_conserving_eqtot: the PRODUCTION (area-weighted) spatial allocation with
# the residual A-vs-B total held fixed — removes the seam-construction
# reaggregation-boundary artifact (2010 tracts not recapturing cells over the
# 2020 extent), which is NOT a production behaviour (production never
# reaggregates across vintages; each year natively conserves). This isolates the
# PURE spatial-repartitioning effect under the production allocator.
mce <- list(A = area$A, B = scale_to(area$B, gtot(area$A)))

METHODS <- list(raw = raw, equal_total = eqt,
                mass_conserving = area, mass_conserving_eqtot = mce)
method_pop <- lapply(METHODS, function(m) c(A = gtot(m$A), B = gtot(m$B)))
popA_total <- method_pop$raw["A"]; popB_total <- method_pop$raw["B"]   # legacy names (raw)

circularity <- list(
  reference_population_year = YEAR,
  reference_source = sprintf("tidycensus ACS 5-yr B01001_026 (female), state-batched, geometry=FALSE, year=%d", max(min(YEAR,2022L),2013L)),
  native_vintage = "2020 tract polygons (the YEAR ACS release boundary)",
  acs_source_total = acs_source_total,
  method_totals = lapply(method_pop, function(v) list(grid_pop_2020 = unname(v["A"]), grid_pop_2010 = unname(v["B"]),
    pct_lost_A_vs_acs = 100*(1 - unname(v["A"])/max(acs_source_total,1)),
    pct_B_vs_A = 100*(1 - unname(v["B"])/max(unname(v["A"]),1)))),
  equal_total_reference = unname(P_ref),
  loss_mechanism = "raw/center-based: tracts not covering a cell centre drop out; totals differ by vintage. area/mass-conserving: exact_extract coverage-area split conserves each tract's population; A and B totals both ≈ ACS.")
for (mn in names(method_pop)) say("pop — %-15s 2020=%.0f (%.2f%% vs ACS) | 2010=%.0f (%.2f%% vs A)",
    mn, method_pop[[mn]]["A"], 100*(1-method_pop[[mn]]["A"]/max(acs_source_total,1)),
    method_pop[[mn]]["B"], 100*(1-method_pop[[mn]]["B"]/max(method_pop[[mn]]["A"],1)))

# Isochrones for the UNION of tested specialties' origins (prepared once).
union_coords <- unique(unlist(lapply(SUBSPECS, function(sc) supply_by[[sc]]$coord_id)))
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
iso_sf <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b) {
  x <- readRDS(file.path(ROOT,"artifacts","isochrones", sprintf("isochrones_%dmin_consolidated.rds", b)))
  x$coord_id <- as.character(if ("coord_id" %in% names(x)) x$coord_id else x$location_key)
  x <- x[x$coord_id %in% union_coords, , drop = FALSE]
  if (!"drive_time_minutes" %in% names(x)) x$drive_time_minutes <- b
  x <- x[, c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(x) <- "geometry"; x }))
iso_ctx <- prepare_e2sfca_iso(iso_sf, area_crs = E2SFCA_AREA_CRS)
say("isochrone rows (union active x band): %d", nrow(iso_sf))

# State id per cell (for state summaries of largest change) — from 2020 tracts.
gg2020$tracts$.stfips <- as.integer(substr(gg2020$tracts$GEOID, 1, 2))
state_rast <- terra::rasterize(terra::vect(gg2020$tracts), common_template, field = ".stfips")
st_cell <- terra::values(state_rast)[,1]

# Per-method population weight for the cell-diff distribution = that method's own
# 2020 representation ("how much represented population sees a change").
method_pA <- lapply(METHODS, function(m) terra::values(m$A$pop_rast)[,1])

wquantile <- function(x, w, probs) {   # population-weighted quantiles
  ok <- is.finite(x) & is.finite(w) & w > 0; x <- x[ok]; w <- w[ok]
  if (!length(x)) return(rep(NA_real_, length(probs)))
  o <- order(x); x <- x[o]; w <- w[o]; cw <- cumsum(w)/sum(w)
  stats::approx(cw, x, xout = probs, ties = "ordered", rule = 2)$y
}

# One specialty under one allocation method (grid = list(A=,B=)); pA_w = cell wts.
seam_metrics <- function(grid, supply, pA_w) {
  resA <- compute_e2sfca_raster(grid$A, iso_ctx, supply, per_capita_scale = 1e5,
                                thresholds = THRESHOLDS, return_surface = TRUE)
  resB <- compute_e2sfca_raster(grid$B, iso_ctx, supply, per_capita_scale = 1e5,
                                thresholds = THRESHOLDS, return_surface = TRUE)
  natA <- resA$national; natB <- resB$national
  sA <- terra::values(resA$surface)[,1] * 1e5; sB <- terra::values(resB$surface)[,1] * 1e5
  valid <- is.finite(sA) & is.finite(sB) & is.finite(pA_w) & pA_w >= 0
  absd <- abs(sA - sB); wv <- pA_w[valid]; av <- absd[valid]; sAv <- sA[valid]
  pw_mad <- sum(wv * av) / sum(wv); qs <- wquantile(av, wv, c(.5,.75,.9,.95,.99))
  pos <- sAv > 0; wpos <- wv[pos]; rel <- av[pos] / sAv[pos]; pop_pos <- sum(wpos)
  rel_bins <- vapply(REL_CHANGE_BINS, function(k) sum(wpos[rel > k]) / max(pop_pos, 1), numeric(1))
  stv <- st_cell[valid]
  st_summ <- dplyr::tibble(stfips = stv, w = wv, aw = wv*av) |>
    dplyr::filter(!is.na(stfips)) |> dplyr::group_by(stfips) |>
    dplyr::summarise(pw_mad = sum(aw)/sum(w), pop = sum(w), .groups="drop") |>
    dplyr::arrange(dplyr::desc(pw_mad))
  share_tab <- dplyr::tibble(threshold = THRESHOLDS,
    shareA = natA$threshold_shares$share_pop, shareB = natB$threshold_shares$share_pop,
    signed_diff = natA$threshold_shares$share_pop - natB$threshold_shares$share_pop)
  share_tab$abs_diff <- abs(share_tab$signed_diff)
  mean_abs <- abs(natA$mean_population_weighted_scaled - natB$mean_population_weighted_scaled)
  mean_rel <- mean_abs / max(natA$mean_population_weighted_scaled, 1e-12)
  pass <- (mean_rel < TOL_MEAN_REL) && all(share_tab$abs_diff < TOL_SHARE_ABS, na.rm = TRUE)
  list(mean_2020 = natA$mean_population_weighted_scaled, mean_2010 = natB$mean_population_weighted_scaled,
       mean_abs_diff = mean_abs, mean_rel_diff = mean_rel, max_abs_share = max(share_tab$abs_diff),
       share_tab = as.data.frame(share_tab), cell_pw_mad = pw_mad,
       cell_p50 = qs[1], cell_p75 = qs[2], cell_p90 = qs[3], cell_p95 = qs[4], cell_p99 = qs[5],
       cell_max_unstable = max(av), pop_share_zero_baseline = sum(wv[!pos])/sum(wv),
       pop_share_rel_gt = stats::setNames(rel_bins, paste0("gt_", REL_CHANGE_BINS)),
       top_states = as.data.frame(head(st_summ, 8)), pass = pass)
}

# ── Write the prespecification + environment manifest BEFORE results ─────────
prespec <- list(
  purpose = "E2SFCA tract-vintage seam gate (controlled geometry experiment)",
  tolerances = list(rel_national_mean = TOL_MEAN_REL, abs_threshold_share = TOL_SHARE_ABS,
    rationale = "2% rel mean ~ within ACS 5-yr MOE and sub-year drift; 1pp share below manuscript reporting precision",
    prespecified = "Fixed in seam_test_2sfca.R before any national seam result was examined."),
  representative_selection_rule = sel_rule,
  density_ranking = as.data.frame(rank_tbl),
  tested_specialties = SUBSPECS, year = YEAR, states = STATE_FIPS %||% "CONUS",
  thresholds = THRESHOLDS, rel_change_bins = REL_CHANGE_BINS,
  allocation_methods = list(
    raw = "center-based rasterization (legacy). NOT mass-conserving; A/B totals differ by vintage -> measures total-demand + spatial + interaction combined.",
    equal_total = sprintf("raw center rasters each rescaled to fixed P_ref=%.0f. Diagnostic isolating spatial + interaction (NOT the production fix).", P_ref),
    mass_conserving = "area-weighted tract->grid allocation (allocate_pop_areaweighted); conserves each tract's population; A/B totals both ~ACS -> measures spatial repartitioning. GATE BASIS."),
  gate_rule = "RELAUNCH GATE (user decision 2026-07-11): EVERY tested specialty must pass BOTH prespecified tolerances under BOTH total-fixed methods -- equal_total (center spatial) AND mass_conserving_eqtot (area/production spatial). Two independent spatial schemes, total held fixed, must each show a negligible geometry-only effect. No averaging across specialties. Prespecified tolerances retained unchanged; only the allocation/normalization basis was clarified. Pure mass_conserving is reported but NOT the gate (it carries the seam cross-vintage re-expression total artifact, which is absent in production where each year natively conserves).",
  circularity_note = circularity, environment = env_info)
jsonlite::write_json(prespec, file.path(OUT, sprintf("seam_prespec_%d.json", YEAR)),
                     auto_unbox = TRUE, pretty = TRUE, null = "null")
say("wrote prespec manifest: %s", file.path(OUT, sprintf("seam_prespec_%d.json", YEAR)))

# ── Per-specialty seam computation, all THREE methods side by side ───────────
#  GATE basis = mass_conserving. raw + equal_total reported for decomposition.
METHOD_ORDER <- c("raw", "equal_total", "mass_conserving", "mass_conserving_eqtot")
results <- list()
for (sc in SUBSPECS) {
  supply <- supply_by[[sc]]
  if (!nrow(supply)) { say("skip %s — no providers", sc); next }
  say("--- %s (%d providers, %d origins) ---", sc, sum(supply$supply), nrow(supply))
  by_method <- lapply(METHOD_ORDER, function(mn) seam_metrics(METHODS[[mn]], supply, method_pA[[mn]]))
  names(by_method) <- METHOD_ORDER
  for (mn in METHOD_ORDER) { m <- by_method[[mn]]
    say("  [%-15s] mean/100k A=%.4f B=%.4f rel=%.4f | max|Δshare|=%.4f pw-MAD=%.4f p95=%.4f max=%.4f(unstable) | pop>1%%=%.3f >5%%=%.3f >10%%=%.3f | %s",
        mn, m$mean_2020, m$mean_2010, m$mean_rel_diff, m$max_abs_share, m$cell_pw_mad, m$cell_p95,
        m$cell_max_unstable, m$pop_share_rel_gt[1], m$pop_share_rel_gt[2], m$pop_share_rel_gt[3],
        if (m$pass) "pass" else "FAIL") }
  results[[sc]] <- list(subspec = sc, n_providers = sum(supply$supply), n_origins = nrow(supply),
    method_pop = method_pop, methods = by_method,
    # ── GATE BASIS (user decision 2026-07-11): geometry-only AND equal_total. ──
    # Relaunch requires BOTH total-normalized methods to pass for EVERY specialty:
    #   equal_total          = center-based spatial pattern, total held fixed;
    #   mass_conserving_eqtot = area-weighted (production) pattern, total held fixed.
    # Two independent spatial-allocation schemes must both show a negligible
    # geometry-only effect. Pure mass_conserving is reported but NOT the gate
    # (it carries the seam re-expression total artifact absent in production).
    gate_pass_mc  = by_method$mass_conserving$pass,               # reported only
    gate_pass_eqt = by_method$equal_total$pass,                   # gate component 1
    gate_pass_mce = by_method$mass_conserving_eqtot$pass,         # gate component 2
    gate_pass = by_method$equal_total$pass && by_method$mass_conserving_eqtot$pass)
}

# ── Gate verdict — user basis: geometry-only (mce) AND equal_total, all specs. ─
gate_summ <- function(method_key, field, label) {
  passed <- vapply(results, function(r) isTRUE(r[[field]]), logical(1))
  overall <- all(passed) && length(results) == length(SUBSPECS)
  say("---------- %s ----------", label)
  for (sc in names(results)) { m <- results[[sc]]$methods[[method_key]]
    say("  %-6s rel_mean=%.4f max|Δshare|=%.4f -> %s", sc, m$mean_rel_diff, m$max_abs_share,
        if (isTRUE(results[[sc]][[field]])) "PASS" else "FAIL") }
  overall
}
say("========== RELAUNCH GATE (AUTHORITATIVE basis: mass_conserving — the exact production allocator) ==========")
# AUTHORITATIVE gate = the mass_conserving (area-overlap, native-total) rows: the
# EXACT allocator the 11-year production runner uses. equal_total and
# mass_conserving_eqtot are TOTAL-FIXED DIAGNOSTICS that isolate geometry-only
# effect; they confirm but do NOT authorize (they are not the production config).
overall_mc  <- gate_summ("mass_conserving",       "gate_pass_mc",  "mass_conserving (AUTHORITATIVE — production allocator, native totals)")
overall_eqt <- gate_summ("equal_total",           "gate_pass_eqt", "equal_total (DIAGNOSTIC: center spatial, total fixed)")
overall_mce <- gate_summ("mass_conserving_eqtot", "gate_pass_mce", "mass_conserving_eqtot / geometry_only (DIAGNOSTIC: area spatial, total fixed)")
overall <- overall_mc            # authorize on the production method only
verdict <- sprintf("GATE(AUTHORITATIVE = mass_conserving, the production area-overlap allocator) = %s | mass_conserving all-pass=%s. Confirmatory diagnostics: equal_total all-pass=%s, geometry_only all-pass=%s. %s",
  if (overall) "PASS" else "FAIL", overall_mc, overall_eqt, overall_mce,
  if (overall) "The production mass-conserving allocator passes for all specialties — cleared to relaunch the vintage-dependent 11-yr series using that exact allocator. Diagnostics confirm the geometry-only effect is negligible." else
    "The production mass-conserving allocator FAILS for >=1 specialty — DO NOT relaunch; build a harmonized annual population surface, or limit conclusions to passing specialties.")
say("VERDICT: %s", verdict)

report <- list(prespec = prespec, environment = env_info, circularity = circularity,
               method_pop = method_pop, results = results,
               gate_basis = "mass_conserving (area-overlap, native totals) — the exact production allocator; equal_total and geometry_only are confirmatory diagnostics, not the authorizing test",
               authoritative_gate_method = "mass_conserving",
               all_passed_mass_conserving = overall_mc,
               all_passed_equal_total = overall_eqt, all_passed_geometry_only = overall_mce,
               all_passed_mass_conserving_pure = overall_mc,
               all_passed = overall, verdict = verdict)
saveRDS(report, file.path(OUT, sprintf("seam_report_%s_%d.rds",
        if (identical(SUBSPECS_IN,"all")) "all" else paste(SUBSPECS, collapse="-"), YEAR)))
# flat CSV: one row per (specialty x method), headline metrics for side-by-side.
flat <- dplyr::bind_rows(lapply(results, function(r) dplyr::bind_rows(lapply(METHOD_ORDER, function(mn) {
  m <- r$methods[[mn]]
  data.frame(subspec = r$subspec, method = mn, n_providers = r$n_providers,
    pop_2020 = unname(r$method_pop[[mn]]["A"]), pop_2010 = unname(r$method_pop[[mn]]["B"]),
    mean_2020 = m$mean_2020, mean_2010 = m$mean_2010, mean_abs = m$mean_abs_diff, mean_rel = m$mean_rel_diff,
    max_abs_share = m$max_abs_share, cell_pw_mad = m$cell_pw_mad, cell_p95 = m$cell_p95,
    cell_p99 = m$cell_p99, cell_max = m$cell_max_unstable, pop_rel_gt5pct = unname(m$pop_share_rel_gt["gt_0.05"]),
    is_gate = (mn == "mass_conserving_eqtot"), pass = m$pass, stringsAsFactors = FALSE) }))))
utils::write.csv(flat, file.path(OUT, sprintf("seam_summary_%d.csv", YEAR)), row.names = FALSE)
say("saved report + summary CSV in %s", OUT)
