#!/usr/bin/env Rscript
# ==============================================================================
# run_2sfca.R — Enhanced Two-Step Floating Catchment (E2SFCA) accessibility runner
# ------------------------------------------------------------------------------
# Standalone runner (NOT wired into the master DAG). Consumes existing artifacts:
#   * provider catchments : artifacts/isochrones/isochrones_{30,60,120,180}min_consolidated.rds
#   * provider supply     : <run>/step_3_year_coord_map.rds  (per-(npi,year), carries coord_id)
#   * subspecialty codes  : <run>/step_2.5_final_cohort.rds  (npi -> subspecialty_normalized)
#   * demand population    : ACS B01001_026E (total female) per tract-year, via tidycensus
#                            (or a pre-built sf supplied with --tract-pop-rds)
#
# Writes, per (subspecialty, year):
#   <out>/step_4_2sfca_<SUBSPEC>_<YEAR>.rds            (tract accessibility)
#   <out>/step_4_2sfca_<SUBSPEC>_<YEAR>_providers.rds  (provider-to-pop ratios)
# each with a .sha256 provenance sidecar (write_rds_atomic).
#
# Usage:
#   Rscript scripts/run_2sfca.R --subspec GO --years 2018
#   Rscript scripts/run_2sfca.R --subspec all --years 2013:2023 --out artifacts/2sfca
#   Rscript scripts/run_2sfca.R --subspec GO --years 2020 --states 44,25   # RI+MA smoke
#   Rscript scripts/run_2sfca.R --subspec GO --years 2020 --tract-pop-rds path.rds
#
# Demand = TOTAL FEMALE (B01001_026E). Weights = empirically-selected decay, cumulative-band
# weights (30=1.0, 60=0.68, 120=0.22, 180=0.09); override with --weights.
# ==============================================================================

suppressWarnings(suppressMessages({
  library(sf)
  library(dplyr)
}))

# --- locate project root & module --------------------------------------------
if (requireNamespace("here", quietly = TRUE)) {
  ROOT <- here::here()
} else {
  ROOT <- normalizePath(file.path(dirname(sub("--file=", "",
    grep("--file=", commandArgs(FALSE), value = TRUE)[1])), ".."))
}
source(file.path(ROOT, "R", "two_step_floating_catchment.R"))

# --- tiny arg parser ----------------------------------------------------------
.args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  hit <- which(.args == flag)
  if (length(hit) && hit < length(.args)) return(.args[hit + 1L])
  default
}
has_flag <- function(flag) flag %in% .args

parse_years <- function(x) {
  if (grepl(":", x)) {
    b <- as.integer(strsplit(x, ":")[[1]]); return(seq.int(b[1], b[2]))
  }
  as.integer(strsplit(x, ",")[[1]])
}

SUBSPEC_INPUT <- get_arg("--subspec", "GO")
YEARS         <- parse_years(get_arg("--years", "2018"))
OUT_DIR       <- get_arg("--out", file.path(ROOT, "artifacts", "2sfca"))
STATES        <- get_arg("--states", NULL)  # comma FIPS, restricts pop + origins
TRACT_POP_RDS <- get_arg("--tract-pop-rds", NULL)
ACS_BUNDLE    <- get_arg("--acs-bundle", NULL)  # deterministic multi-year ACS (no Census API)
YCM_PATH      <- get_arg("--year-coord-map", NULL)
COHORT_PATH   <- get_arg("--cohort", NULL)
WEIGHTS_ARG   <- get_arg("--weights", NULL)   # "30=1,60=.68,120=.22,180=.09"
ENGINE        <- match.arg(get_arg("--engine", "raster"), c("raster", "vector"))
RESOLUTION    <- as.numeric(get_arg("--resolution", "250"))  # metres (raster engine)
VERBOSE       <- !has_flag("--quiet")

ALL_CODES <- c("CFP", "FPMRS", "GO", "MFM", "MIGS", "PAG", "REI")
SUBSPECS  <- if (identical(toupper(SUBSPEC_INPUT), "ALL")) ALL_CODES else
  strsplit(SUBSPEC_INPUT, ",")[[1]]
stopifnot(all(SUBSPECS %in% ALL_CODES))

WEIGHTS <- if (is.null(WEIGHTS_ARG)) E2SFCA_DEFAULT_WEIGHTS else {
  kv <- strsplit(strsplit(WEIGHTS_ARG, ",")[[1]], "=")
  stats::setNames(as.numeric(vapply(kv, `[`, "", 2L)), vapply(kv, `[`, "", 1L))
}
STATE_FIPS <- if (is.null(STATES)) NULL else sprintf("%02d", as.integer(strsplit(STATES, ",")[[1]]))

RUN_ID        <- get_arg("--run-id", NULL)   # immutable id for the national run
SEAM_GATE_RDS <- get_arg("--seam-gate-rds", NULL)  # authoritative seam-gate artifact

log_msg <- function(...) if (VERBOSE) cat(sprintf("[2sfca] %s\n", sprintf(...)))

# --- ALLOCATOR IDENTITY GATE (prelaunch requirement, fail-closed) -------------
# The 11-year production run MUST invoke the exact mass-conserving area-overlap
# allocator (allocate_pop_areaweighted) that generated the passing seam
# `mass_conserving` rows: population allocated by polygon-cell overlap, every
# source tract conserved, native annual totals, NO center-based rasterization,
# NO equal-total normalization. We bind that identity three ways and stop() on
# any drift BEFORE any specialty calculation:
#   (1) content sha256 of the module that DEFINES the allocator must equal the
#       seam-validated hash (the allocator identifier saved with the seam run);
#   (2) the allocator function must exist after sourcing;
#   (3) the production dispatch default must resolve to "area" (never "center").
PROD_ALLOCATOR        <- "allocate_pop_areaweighted"  # polygon-cell overlap, mass-conserving
PROD_ALLOC_MODE       <- "area"
# Re-pinned 2026-07-24. The seam test validated the allocator at commit ff3aac4a
# (whole-file sha256 2b78718b...). Post-freeze changes to SIBLING functions
# (M2SFCA / Gaussian-zonal / SPAR) and documentation (primary-source citations,
# roxygen @examples / @family tags) moved the WHOLE-FILE hash, but
# allocate_pop_areaweighted() and its grid helpers (build_e2sfca_raster_grid,
# rasterize_tract_geometry, build_e2sfca_raster_grid_year) are byte-identical to
# ff3aac4a (verified: git show ff3aac4a:R/... vs working tree), so the allocation
# the seam gate certified is unchanged. This gate hashes the WHOLE file, so it
# trips on any edit; if allocate_pop_areaweighted's BODY ever changes, do NOT
# re-pin here -- re-run the seam test and pin from that run.
#   seam-validated ancestor (ff3aac4a): 2b78718bf65c2ecb7a1c99fb027d4aa52aeabc345faf6ec71291197e3fe25c43
#
# Re-pinned 2026-08-18, when twostep became the canonical owner of the E2SFCA
# study layer. The pin was STALE: it still carried 11abdec3, while this repo's
# R/two_step_floating_catchment.R hashed to e162507c after the 2026-08-16 engine
# work (53cfd45, 998ad40, a5ed663, ce7841c). The gate was therefore failing
# closed against this repo's own engine.
#
# Evidence gathered before re-pinning, by PARSING both file versions and hashing
# the DEPARSED definitions -- not by line ranges:
#
#   BYTE-IDENTICAL between this engine and isochrones@origin/main (whose copy is
#   in turn certified byte-identical to the seam-validated ancestor ff3aac4a):
#     allocate_pop_areaweighted   (f25bfdfaff3a)   <- the gated allocator itself
#     build_e2sfca_raster_grid    (0ea5d3135509)
#     build_e2sfca_grid_geometry  (4e42d9a390ac)
#     e2sfca_cell_summaries       (5e612404610f)
#     compute_provider_supply     (79d204f4320f)
#     e2sfca_incremental_weights  (f5bc77a8138a)   <- so step2_power/M2SFCA match
#
#   DIFFERENT (this repo is AHEAD of isochrones, deliberately):
#     attach_e2sfca_population    (629d7dc3014f vs d7ead42bb104)
#     compute_e2sfca_raster       (03e712a55000 vs 1aca21611cbf)
#
# The allocator BODY is unchanged, which is what this gate's own protocol
# requires for a re-pin. But read the second list honestly: those two engine
# deltas are this repo's OWN reviewed changes -- "missing population is not zero
# population" (998ad40) and "stop reporting unreached tracts as measured zeros"
# (53cfd45). They are INTENTIONALLY NOT numerically neutral: an unreached tract
# now reports NA rather than a measured 0. So, unlike the isochrones re-pin of
# 2026-08-16, NO claim of 0.000e+00 equivalence is made or implied here.
#
# CONSEQUENCE: this pin re-certifies the ALLOCATION (mass conservation, area
# overlap), not the full surface numerics. The seam test should be re-run against
# this engine to re-certify those, and this constant re-pinned from that run.
# Tracked in inst/doc-provenance/E2SFCA_PORT_FROM_ISOCHRONES_2026-08-18.md.
# Re-pinned 2026-08-20. The engine changed from e162507c to 88c561f0 for a
# DOCUMENTATION-ONLY reason: four roxygen prose lines had an unescaped "%",
# which is the Rd comment character, so the rendered documentation was silently
# truncating text and one malformed .Rd made R CMD check emit 2 WARNINGs across
# every platform.
#
# Evidence gathered by this gate's own protocol -- PARSING both file versions
# and hashing the DEPARSED definitions, not line ranges. All 14 functions in the
# module, including every gated one, are BYTE-IDENTICAL across the change:
#
#   allocate_pop_areaweighted   a1b1110b5380   <- the gated allocator itself
#   build_e2sfca_raster_grid    3d208454e0ac
#   build_e2sfca_grid_geometry  d717f19382ff
#   e2sfca_cell_summaries       243ac6409b42
#   compute_provider_supply     28e6dcb40ea2
#   e2sfca_incremental_weights  a65121ae4bc6
#   attach_e2sfca_population    d7a653ec6f49
#   compute_e2sfca_raster       211ef2d7e62b
#   compute_e2sfca              fa8b4f839f7a
#
#   functions added: none.  removed: none.  bodies changed: NONE.
#
# This re-pin therefore carries NO numerical claim beyond the previous one: it
# certifies that the module is byte-identical in behaviour to e162507c, which is
# a strictly weaker and fully verified statement. The seam-test caveat recorded
# above for e162507c still stands unchanged and is NOT discharged by this.
# Re-pinned again 2026-08-22, 88c561f0 -> 0736d4d7. Unlike the previous re-pin
# this one is NOT documentation-only: compute_e2sfca_raster gained a
# precondition check. Stated plainly rather than buried:
#
#   CHANGED:   compute_e2sfca_raster            (the guard added below)
#   IDENTICAL: allocate_pop_areaweighted  a1b1110b5380   <- the gated allocator
#              and the other 12 functions in the module
#   added: none.  removed: none.
#
# The protocol's condition for a re-pin -- the allocator BODY unchanged -- is
# met, and compute_e2sfca_raster is already recorded above as a function where
# this repo is deliberately ahead of isochrones.
#
# WHAT THE CHANGE DOES, and why it carries no numerical claim: it adds a
# fail-closed check for supply origins that appear in no isochrone band. On
# inputs that PASS the check the arithmetic is untouched -- the guard runs
# before any geometry work and either stops or warns. So this cannot move a
# valid surface; it can only refuse an invalid one.
#
# WHY IT EXISTS: reproducing the frozen run from its own recorded supply table
# gave a national mean 0.786% BELOW the published value. Five of 516 origins
# carried 7 of 890 supply units (0.787%) and had no isochrone locally. Their
# supply evaporated and the engine reported success. The seam caveat recorded
# above still stands and is not discharged here.
# RE-PIN 2026-08-23: 0736d4d7 -> 08b14e8f.
#
# The entire diff since the previous pin is ONE character inside a roxygen
# comment: `0.786%` became `0.786\%` in the @param for unmatched_supply_policy.
# `%` is Rd's comment character, so the unescaped form truncated the generated
# Rd and R CMD check failed on all five platforms with "unexpected section
# header". Docs only -- not one executable line changed:
#
#   git diff a67f29c..HEAD -- R/two_step_floating_catchment.R
#
# The protocol's condition for a re-pin -- the allocator BODY unchanged -- is
# therefore met trivially. Recorded rather than waved through because the pin
# hashes the whole FILE, so a comment edit trips it exactly as a logic edit
# would. That is deliberate and worth keeping: it costs a documented re-pin and
# it makes an unreviewed engine edit impossible.
SEAM_ALLOCATOR_SHA256 <- Sys.getenv(
  "E2SFCA_SEAM_ALLOCATOR_SHA256",
  "08b14e8fdfad40e32f8bed9d05d16c2def883b6fb69d3aa82fad51bf8d000d7e")
.module_path <- file.path(ROOT, "R", "two_step_floating_catchment.R")
.module_sha  <- digest::digest(file = .module_path, algo = "sha256")
log_msg("ALLOCATOR IDENTITY: fn=%s()  mode=%s  module=%s", PROD_ALLOCATOR,
        PROD_ALLOC_MODE, basename(.module_path))
log_msg("ALLOCATOR IDENTITY: module sha256 = %s", .module_sha)
log_msg("ALLOCATOR IDENTITY: seam   sha256 = %s", SEAM_ALLOCATOR_SHA256)
if (!identical(.module_sha, SEAM_ALLOCATOR_SHA256)) {
  stop(sprintf(paste0("ALLOCATOR IDENTITY MISMATCH: %s sha256=%s != seam-validated ",
       "%s. The production allocator is NOT the exact one validated by the seam ",
       "gate; refusing to launch the 11-year series."),
       basename(.module_path), .module_sha, SEAM_ALLOCATOR_SHA256), call. = FALSE)
}
if (!exists(PROD_ALLOCATOR, mode = "function")) {
  stop(sprintf("ALLOCATOR IDENTITY: %s() not found after sourcing the module.",
               PROD_ALLOCATOR), call. = FALSE)
}
.alloc_default <- eval(formals(attach_e2sfca_population)$alloc)[1]
if (!identical(.alloc_default, PROD_ALLOC_MODE)) {
  stop(sprintf(paste0("ALLOCATOR IDENTITY: attach_e2sfca_population default alloc ",
       "is '%s', expected '%s' (mass-conserving). Refusing to launch."),
       .alloc_default, PROD_ALLOC_MODE), call. = FALSE)
}
log_msg("ALLOCATOR IDENTITY: VERIFIED — mass-conserving area-overlap allocation (matches seam gate).")

# National-total conservation tripwire: under area allocation the raster total
# equals the source ACS total (~0% drop); center-based rasterization drops
# ~1.06%. A drop beyond this bound means the allocator is NOT the validated one.
NATIONAL_CONSERVATION_TOL <- as.numeric(Sys.getenv("E2SFCA_NATIONAL_CONS_TOL", "0.005"))

# --- auto-detect newest run-scoped artifact if not supplied -------------------
newest <- function(pattern) {
  f <- list.files(file.path(ROOT, "artifacts"), pattern = pattern,
                  recursive = TRUE, full.names = TRUE)
  if (!length(f)) return(NULL)
  f[order(file.info(f)$mtime, decreasing = TRUE)][1]
}
if (is.null(YCM_PATH))    YCM_PATH    <- newest("^step_3_year_coord_map\\.rds$")
if (is.null(COHORT_PATH)) COHORT_PATH <- newest("^step_2\\.5_final_cohort\\.rds$")
stopifnot(!is.null(YCM_PATH), file.exists(YCM_PATH))
stopifnot(!is.null(COHORT_PATH), file.exists(COHORT_PATH))
log_msg("year_coord_map : %s", YCM_PATH)
log_msg("cohort         : %s", COHORT_PATH)

year_coord_map <- readRDS(YCM_PATH)
cohort         <- readRDS(COHORT_PATH)

# --- supply for every requested cell; collect the union of active origins -----
supply_cache <- list()
active_coords <- character(0)
for (sc in SUBSPECS) for (yr in YEARS) {
  s <- compute_provider_supply(year_coord_map, cohort, sc, yr)
  supply_cache[[paste(sc, yr, sep = "_")]] <- s
  active_coords <- union(active_coords, s$coord_id)
}
log_msg("active provider origins across all cells: %d", length(active_coords))
if (!length(active_coords)) stop("No active providers for the requested cells.", call. = FALSE)

# --- load isochrone polygons (only the active origins) ------------------------
load_iso_active <- function(active) {
  # SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
  bands <- c(30L, 60L, 120L, 180L)
  parts <- lapply(bands, function(b) {
    f <- file.path(ROOT, "artifacts", "isochrones",
                   sprintf("isochrones_%dmin_consolidated.rds", b))
    if (!file.exists(f)) stop("Missing isochrone artifact: ", f, call. = FALSE)
    log_msg("reading %s", basename(f))
    x <- readRDS(f)
    # Consolidated artifacts key the origin as `location_key` ("lat_lon"); the
    # year_coord_map keys the same origin as `coord_id`. Normalize to coord_id.
    if (!"coord_id" %in% names(x) && "location_key" %in% names(x)) {
      x$coord_id <- as.character(x$location_key)
    } else {
      x$coord_id <- as.character(x$coord_id)
    }
    x <- x[x$coord_id %in% active, , drop = FALSE]
    if (!"drive_time_minutes" %in% names(x)) x$drive_time_minutes <- b
    x <- x[, c("coord_id", "drive_time_minutes", "geometry")]
    sf::st_geometry(x) <- "geometry"
    x
  })
  do.call(rbind, parts)
}
iso_sf <- load_iso_active(active_coords)
log_msg("isochrone rows (active origins x bands): %d", nrow(iso_sf))

# --- demand population + tract geometry ---------------------------------------
# Isochrone geometry is year-agnostic and tract boundaries change only at the
# 2010->2020 vintage break, so we fetch heavy geometry ONCE per vintage and
# cheap population VALUES once per year (geometry = FALSE), then join by GEOID.
if (requireNamespace("tigris", quietly = TRUE)) options(tigris_use_cache = TRUE)

# CONUS = 48 states + DC; excludes AK(02)/HI(15) and territories.
# SSOT anchor (CONUS_STATE_FIPS): canonical CONUS set in scripts/manuscript_e2sfca_values.R; guarded by tests/testthat/test-ssot-conus-fips.R
conus_states <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

# Deterministic multi-year ACS bundle (no Census API on EC2). Structure:
#   list(pop_by_year = list("2013"=tibble(GEOID,female_pop), ... "2022"=...),
#        geom_by_vintage = list("2010"=sf(GEOID,geom), "2020"=sf(GEOID,geom)))
# Population keyed by the ACS 5-yr year (clamp(year,2013,2022)); geometry by
# vintage (2010 for years<=2019, 2020 for years>=2020). Fail-closed: every
# requested ACS-year and vintage MUST be present.
.ACS <- NULL
acs_year_of <- function(year) as.character(max(min(year, 2022L), 2013L))
if (!is.null(ACS_BUNDLE)) {
  stopifnot(file.exists(ACS_BUNDLE))
  .ACS <- readRDS(ACS_BUNDLE)
  stopifnot(is.list(.ACS), !is.null(.ACS$pop_by_year), !is.null(.ACS$geom_by_vintage))
  need_years <- unique(vapply(YEARS, acs_year_of, ""))
  miss_y <- setdiff(need_years, names(.ACS$pop_by_year))
  if (length(miss_y)) stop(sprintf("--acs-bundle missing pop for ACS year(s): %s",
                                    paste(miss_y, collapse=", ")), call. = FALSE)
  need_vint <- unique(vapply(YEARS, function(y) as.character(if (y >= 2020L) 2020L else 2010L), ""))
  miss_v <- setdiff(need_vint, names(.ACS$geom_by_vintage))
  if (length(miss_v)) stop(sprintf("--acs-bundle missing geometry for vintage(s): %s",
                                    paste(miss_v, collapse=", ")), call. = FALSE)
  log_msg("ACS bundle: %d pop-years [%s], %d vintages [%s]",
          length(.ACS$pop_by_year), paste(names(.ACS$pop_by_year), collapse=","),
          length(.ACS$geom_by_vintage), paste(names(.ACS$geom_by_vintage), collapse=","))
}

# Female population (B01001_026E) VALUES for one year (no geometry — fast).
load_female_pop_values <- function(year, states = NULL) {
  if (!is.null(.ACS)) {
    tp <- .ACS$pop_by_year[[acs_year_of(year)]]
    out <- dplyr::tibble(GEOID = as.character(tp$GEOID), female_pop = as.numeric(tp$female_pop))
    if (!is.null(states)) out <- out[substr(out$GEOID, 1L, 2L) %in% states, , drop = FALSE]
    return(out)
  }
  if (!is.null(TRACT_POP_RDS)) {
    tp <- readRDS(TRACT_POP_RDS)
    return(dplyr::tibble(GEOID = as.character(tp$GEOID),
                         female_pop = as.numeric(tp$female_pop)))
  }
  st <- if (is.null(states)) conus_states() else states
  acs_year <- max(min(year, 2022L), 2013L)   # ACS 5-yr availability window
  log_msg("get_acs female_pop values %d (%d state[s])", acs_year, length(st))
  raw <- purrr::map_dfr(st, function(s) suppressMessages(tidycensus::get_acs(
    geography = "tract", variables = c(female_pop = "B01001_026"),
    state = s, year = acs_year, geometry = FALSE)))
  raw <- raw[raw$variable == "female_pop", , drop = FALSE]
  dplyr::tibble(GEOID = as.character(raw$GEOID), female_pop = as.numeric(raw$estimate))
}

# Tract GEOMETRY for a vintage (fetched at a representative year: 2010-boundary
# tracts via ACS 2019, 2020-boundary via ACS 2020). Geometry only; no pop values.
load_tract_geometry <- function(vintage, states = NULL) {
  if (!is.null(.ACS)) {
    g <- .ACS$geom_by_vintage[[as.character(as.integer(vintage))]]
    g <- sf::st_as_sf(g); g$GEOID <- as.character(g$GEOID)
    if (!is.null(states)) g <- g[substr(g$GEOID, 1L, 2L) %in% states, , drop = FALSE]
    return(g[, "GEOID"])
  }
  if (!is.null(TRACT_POP_RDS)) {
    tp <- readRDS(TRACT_POP_RDS)
    if (!inherits(tp, "sf")) stop("--tract-pop-rds must be an sf with GEOID + geometry.")
    return(sf::st_as_sf(dplyr::tibble(GEOID = as.character(tp$GEOID),
                                      geometry = sf::st_geometry(tp))))
  }
  rep_year <- if (identical(as.integer(vintage), 2020L)) 2020L else 2019L
  st <- if (is.null(states)) conus_states() else states
  log_msg("get_acs tract geometry (vintage %s via %d, %d state[s])", vintage, rep_year, length(st))
  raw <- purrr::map_dfr(st, function(s) suppressMessages(tidycensus::get_acs(
    geography = "tract", variables = c(female_pop = "B01001_026"),
    state = s, year = rep_year, geometry = TRUE)))
  raw <- raw[raw$variable == "female_pop", , drop = FALSE]
  g <- sf::st_as_sf(raw[, "GEOID"])
  g$GEOID <- as.character(g$GEOID)
  g
}

# Tract boundary vintage: <=2019 -> 2010 tracts, >=2020 -> 2020 tracts.
vintage_of <- function(year) if (year >= 2020L) 2020L else 2010L

if (!is.null(ACS_BUNDLE) || !is.null(TRACT_POP_RDS) || requireNamespace("tidycensus", quietly = TRUE)) {} else {
  stop("no ACS source: supply --acs-bundle or --tract-pop-rds, or install tidycensus.", call. = FALSE)
}

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

overlap_by_vintage   <- list()   # cache: tract x band overlap per vintage (vector)
geom_by_vintage      <- list()   # cache: tract geometry sf per vintage
geom_grid_by_vintage <- list()   # cache: rasterized tract geometry per vintage (raster)
results_index  <- list()
national_index <- list()   # authoritative cell-level national summaries per cell

log_msg("engine: %s%s", ENGINE,
        if (ENGINE == "raster") sprintf(" (%.0f m)", RESOLUTION) else "")
iso_ctx <- NULL
if (ENGINE == "raster") {
  library(terra); library(exactextractr)
  log_msg("preparing isochrones (transform + validate, once)")
  iso_ctx <- prepare_e2sfca_iso(iso_sf, area_crs = E2SFCA_AREA_CRS)
}

# Load tract geometry once per vintage (shared across years of that vintage).
get_geom <- function(vint) {
  if (is.null(geom_by_vintage[[vint]])) {
    g <- load_tract_geometry(as.integer(vint), STATE_FIPS)
    if (!is.null(STATE_FIPS)) g <- g[substr(g$GEOID, 1, 2) %in% STATE_FIPS, , drop = FALSE]
    geom_by_vintage[[vint]] <<- g
  }
  geom_by_vintage[[vint]]
}

for (yr in YEARS) {
  vint <- as.character(vintage_of(yr))
  geom <- get_geom(vint)

  # Per-year population values, joined to this vintage's geometry.
  pop_vals <- load_female_pop_values(yr, STATE_FIPS)
  if (!is.null(STATE_FIPS)) {
    pop_vals <- pop_vals[substr(pop_vals$GEOID, 1, 2) %in% STATE_FIPS, , drop = FALSE]
  }
  tracts_yr <- dplyr::left_join(geom, pop_vals, by = "GEOID")
  tracts_yr$female_pop[is.na(tracts_yr$female_pop)] <- 0

  if (ENGINE == "raster") {
    # Rasterize tract geometry once per vintage; attach population per year.
    if (is.null(geom_grid_by_vintage[[vint]])) {
      log_msg("rasterizing tract geometry for vintage %s (%d tracts, %.0f m)",
              vint, nrow(geom), RESOLUTION)
      geom_grid_by_vintage[[vint]] <- build_e2sfca_grid_geometry(
        geom, resolution = RESOLUTION)
    }
    log_msg("attaching %d population to grid (%d)", yr, yr)
    # EXPLICIT alloc = "area": mass-conserving area-overlap allocation (the exact
    # allocator validated by the seam `mass_conserving` rows). Never rely on the
    # default here — an accidental default drift must not silently switch method.
    grid <- attach_e2sfca_population(geom_grid_by_vintage[[vint]], pop_vals,
                                     "female_pop", alloc = PROD_ALLOC_MODE)
  } else {
    if (is.null(overlap_by_vintage[[vint]])) {
      log_msg("computing tract x band overlap (vector) for vintage %s (%d tracts)",
              vint, nrow(geom))
      overlap_by_vintage[[vint]] <- compute_band_tract_overlap(iso_sf, geom, verbose = VERBOSE)
    }
    overlap <- overlap_by_vintage[[vint]]
  }

  for (sc in SUBSPECS) {
    key <- paste(sc, yr, sep = "_")
    supply <- supply_cache[[key]]
    if (!nrow(supply)) { log_msg("skip %s %d — no active providers", sc, yr); next }

    res <- if (ENGINE == "raster") {
      compute_e2sfca_raster(grid, iso_ctx, supply, weights = WEIGHTS, per_capita_scale = 1e5)
    } else {
      compute_e2sfca(overlap, sf::st_drop_geometry(tracts_yr)[, c("GEOID", "female_pop")],
                     supply, weights = WEIGHTS, pop_col = "female_pop", per_capita_scale = 1e5)
    }

    access <- dplyr::mutate(res$access, subspecialty = sc, year = yr, .before = 1)
    provs  <- dplyr::mutate(res$provider_ratios, subspecialty = sc, year = yr, .before = 1)

    out_access <- file.path(OUT_DIR, sprintf("step_4_2sfca_%s_%d.rds", sc, yr))
    out_provs  <- file.path(OUT_DIR, sprintf("step_4_2sfca_%s_%d_providers.rds", sc, yr))
    if (!exists("write_rds_atomic")) source(file.path(ROOT, "R", "utils", "write_rds_atomic.R"))
    write_rds_atomic(access, out_access); write_rds_atomic(provs, out_provs)

    # --- authoritative cell-level national headline (raster engine only) ------
    nat <- res$national
    if (!is.null(nat)) {
      # Log raster-derived population vs the source ACS population so any
      # allocation discrepancy is visible (small tracts that miss a cell centre
      # drop out of the raster). NEVER assume these are exactly equal.
      acs_pop_source <- sum(pop_vals$female_pop[pop_vals$GEOID %in% grid$tracts$GEOID], na.rm = TRUE)
      # HARD national-conservation gate (requirement 5): fail the year if the
      # raster population differs from the source ACS population beyond the
      # validated tolerance. Under the mass-conserving allocator this drop is ~0;
      # a breach means population was lost (i.e. the allocator is not the
      # validated area-overlap one) and the year's result is not trustworthy.
      cons_drop <- abs(1 - nat$pop_raster_total / max(acs_pop_source, 1))
      if (cons_drop > NATIONAL_CONSERVATION_TOL) {
        stop(sprintf(paste0("NATIONAL CONSERVATION FAIL (%s %d): raster pop %.0f vs ",
             "ACS source %.0f = %.4f%% drop > tol %.4f%%. Population was not ",
             "conserved; refusing to emit a non-conserving year."),
             sc, yr, nat$pop_raster_total, acs_pop_source,
             100 * cons_drop, 100 * NATIONAL_CONSERVATION_TOL), call. = FALSE)
      }
      thr <- nat$threshold_shares
      log_msg(paste0("wrote %s  tracts=%d providers=%d | NATIONAL(cell): ",
              "pop-wt mean/100k=%.3f  share>=10=%.4f | pop_raster=%.0f acs_src=%.0f ",
              "(%.2f%% dropped) excl_missing_access_pop=%.0f"),
              basename(out_access), nrow(access), nrow(provs),
              nat$mean_population_weighted_scaled,
              thr$share_pop[thr$threshold == 10],
              nat$pop_raster_total, acs_pop_source,
              100 * (1 - nat$pop_raster_total / max(acs_pop_source, 1)),
              nat$pop_excluded_missing_access)
      nat_row <- data.frame(subspecialty = sc, year = yr,
        n_cells_total = nat$n_cells_total, n_cells_valid = nat$n_cells_valid,
        pop_raster_total = nat$pop_raster_total, acs_pop_source = acs_pop_source,
        pop_valid_total = nat$pop_valid_total,
        pop_excluded_missing_access = nat$pop_excluded_missing_access,
        pop_excluded_missing_pop = nat$pop_excluded_missing_pop,
        mean_pop_weighted_per100k = nat$mean_population_weighted_scaled,
        stringsAsFactors = FALSE)
      for (r in seq_len(nrow(thr))) {
        nat_row[[sprintf("share_ge_%g", thr$threshold[r])]] <- thr$share_pop[r]
      }
      national_index[[key]] <- nat_row
    } else {
      log_msg("wrote %s  (tracts=%d, providers=%d)", basename(out_access),
              nrow(access), nrow(provs))
    }
    results_index[[key]] <- data.frame(subspecialty = sc, year = yr,
      n_tracts = nrow(access), n_providers = nrow(provs),
      access_file = out_access, stringsAsFactors = FALSE)
  }
}

idx <- dplyr::bind_rows(results_index)
if (nrow(idx)) {
  utils::write.csv(idx, file.path(OUT_DIR, "e2sfca_index.csv"), row.names = FALSE)
  log_msg("DONE — %d cell(s). Index: %s", nrow(idx), file.path(OUT_DIR, "e2sfca_index.csv"))
} else {
  log_msg("DONE — no cells produced output.")
}
nat_idx <- dplyr::bind_rows(national_index)
if (nrow(nat_idx)) {
  utils::write.csv(nat_idx, file.path(OUT_DIR, "e2sfca_national_summary.csv"), row.names = FALSE)
  log_msg("Authoritative cell-level national summaries: %s",
          file.path(OUT_DIR, "e2sfca_national_summary.csv"))
}

# --- national run manifest (provenance + allocator identity + seam-gate) ------
# Records the exact allocator, its module hash bound to the seam, the seam-gate
# artifact path + checksum, prespecified tolerances, environment, and per-(spec,
# year) conservation. Headline means/threshold shares come SOLELY from the
# cell-level national summary above (requirement 7).
sha_or_na <- function(p) if (!is.null(p) && file.exists(p))
  digest::digest(file = p, algo = "sha256") else NA_character_
cons_tbl <- if (nrow(nat_idx)) lapply(seq_len(nrow(nat_idx)), function(i) {
  r <- nat_idx[i, ]
  list(subspecialty = r$subspecialty, year = r$year,
       pop_raster_total = r$pop_raster_total, acs_pop_source = r$acs_pop_source,
       conservation_drop = abs(1 - r$pop_raster_total / max(r$acs_pop_source, 1)))
}) else list()
git_sha <- Sys.getenv("E2SFCA_GIT_SHA", "")
if (!nzchar(git_sha)) git_sha <- tryCatch(
  system("git rev-parse HEAD", intern = TRUE, ignore.stderr = TRUE)[1],
  error = function(e) NA_character_)
manifest <- list(
  run_id = if (is.null(RUN_ID)) NA_character_ else RUN_ID,
  created = format(Sys.time(), tz = "UTC", usetz = TRUE),
  git_sha = git_sha,
  years = YEARS, subspecialties = SUBSPECS, engine = ENGINE,
  resolution_m = RESOLUTION, crs = as.character(E2SFCA_AREA_CRS),
  weights = as.list(WEIGHTS),
  allocator = list(
    method_id = "mass_conserving",
    population_allocator = PROD_ALLOCATOR, mode = PROD_ALLOC_MODE,
    description = "polygon-cell area-overlap allocation; conserves every source tract; native annual totals; no center-based rasterization; no equal-total normalization",
    module = basename(.module_path), module_sha256 = .module_sha,
    seam_validated_sha256 = SEAM_ALLOCATOR_SHA256,
    identity_verified = identical(.module_sha, SEAM_ALLOCATOR_SHA256)),
  # SSOT: record the allocator tolerance the engine actually uses (its function
  # default), read live from the sourced engine, so the manifest can never restate a
  # value that disagrees with allocate_pop_areaweighted(). The engine file is sha-gated
  # (allocator identity, lines ~110-123), so we read its default rather than edit it.
  tolerances = list(allocator_conservation_tol =
                      eval(formals(allocate_pop_areaweighted)$conservation_tol),
                    national_conservation_tol = NATIONAL_CONSERVATION_TOL),
  seam_gate = list(
    artifact = if (is.null(SEAM_GATE_RDS)) NA_character_ else SEAM_GATE_RDS,
    sha256 = sha_or_na(SEAM_GATE_RDS),
    authoritative_gate_method = "mass_conserving (area-overlap, native totals)"),
  acs_source = list(
    acs_bundle = if (is.null(ACS_BUNDLE)) NA_character_ else ACS_BUNDLE,
    acs_bundle_sha256 = sha_or_na(ACS_BUNDLE),
    tract_pop_rds = if (is.null(TRACT_POP_RDS)) NA_character_ else TRACT_POP_RDS),
  environment = list(
    r_version = paste(R.version$major, R.version$minor, sep = "."),
    sf = as.character(utils::packageVersion("sf")),
    terra = as.character(utils::packageVersion("terra")),
    exactextractr = as.character(utils::packageVersion("exactextractr")),
    geos = unname(sf::sf_extSoftVersion()["GEOS"]),
    gdal = unname(sf::sf_extSoftVersion()["GDAL"]),
    proj = unname(sf::sf_extSoftVersion()["PROJ"])),
  conservation = cons_tbl,
  headline_source = "e2sfca_national_summary.csv (cell-level population-weighted)",
  n_outputs = nrow(idx))
mf_path <- file.path(OUT_DIR, "e2sfca_run_manifest.json")
writeLines(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null"), mf_path)
log_msg("national run manifest: %s", mf_path)
