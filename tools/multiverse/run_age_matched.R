#!/usr/bin/env Rscript
# =============================================================================
# S11: age-matched demand denominators -- execution
# =============================================================================
# Runs the frozen manifest v4 cuts through the engine and reports which
# manuscript claims survive.
#
# BOTH regimes are computed in one run -- all-ages and age-matched -- with
# IDENTICAL supply, isochrones, grid geometry and weights. Only the demand
# denominator differs. Any incomplete-isochrone loss therefore affects both
# equally and cancels in the contrast, so a difference cannot be an artefact of
# the reproduction route.
#
# Supply comes from the frozen run's own RECORDED provider tables, each
# checksum-verified, which is what lets this run at all: the cohort input that
# would otherwise derive them is unrecoverable.
#
# INTERPRETATION RULE, from the manifest: age-matched and all-ages estimates are
# NOT comparable in LEVEL -- different denominators are different estimands.
# Only contrast DIRECTION and claim survival may be compared.
suppressWarnings(suppressMessages({
  library(sf); library(terra); library(dplyr); library(yaml)
}))
# Load the package's functions WITHOUT requiring any package that the frozen
# analysis environment does not already have.
#
# The frozen-run AMI carries sf/terra/exactextractr/dplyr/tidyr/yaml/digest but
# neither devtools nor pkgload, and pkgload cannot be installed there -- its
# dependency `fs` needs a compiler that is not present. Installing a toolchain to
# get a package LOADER would mutate an environment whose entire scientific value
# is that it is pinned to the primary analysis.
#
# So: use load_all() when it is available (local development), and otherwise
# source R/ directly. The two are equivalent for this script, which only calls
# exported functions and already attaches its own libraries above -- and the
# 2020 reproduction gate proves that equivalence numerically rather than
# assuming it.
suppressMessages(
  if (requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(".", quiet = TRUE)
  } else if (requireNamespace("devtools", quietly = TRUE)) {
    devtools::load_all(".", quiet = TRUE)
  } else {
    # Direct sourcing makes these files part of the execution environment, so
    # they are provenance-tracked like a package would be: the ORDER they are
    # sourced in and the sha256 of each, written beside the results.
    .fs <- sort(list.files("R", pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE))
    for (.f in .fs) sys.source(.f, envir = globalenv())
    if (requireNamespace("digest", quietly = TRUE)) {
      dir.create("artifacts/multiverse", showWarnings = FALSE, recursive = TRUE)
      writeLines(c("# ordered source manifest for the direct-sourcing load path",
                   sprintf("# %d files, sourced in this order", length(.fs)),
                   vapply(seq_along(.fs), function(i)
                     sprintf("%02d  %s  %s", i,
                             digest::digest(file = .fs[i], algo = "sha256"), .fs[i]),
                     character(1))),
                 "artifacts/multiverse/sourced_R_files.sums")
    }
  })
S <- Sys.getenv("S"); stopifnot(nzchar(S))
say <- function(...) cat(sprintf("[s11] %s\n", sprintf(...)))

MAN  <- "inst/multiverse/age_matched_denominator.yml"
HASH <- "inst/multiverse/age_matched_denominator.sha256"
rec <- trimws(strsplit(readLines(HASH, warn = FALSE)[1], "\\s+")[[1]][1])
act <- digest::digest(file = MAN, algo = "sha256")
if (!identical(rec, act)) stop("manifest changed since freezing", call. = FALSE)
say("freeze verified %s...", substr(act, 1, 16))
man <- yaml::read_yaml(MAN)

# Year-parameterised; 2020 keeps its original inputs and output path so the
# frozen 2020 results stay reproducible. One script rather than a copy: a
# duplicated E2SFCA loop would drift from this one without anyone noticing.
YEAR <- as.integer(Sys.getenv("E2SFCA_AM_YEAR", "2020"))
if (is.na(YEAR) || YEAR < 2013L || YEAR > 2023L) stop("E2SFCA_AM_YEAR must be 2013-2023")
# Tract geometry has exactly TWO vintages across 2013-2023, verified by querying
# GEOIDs year by year rather than assumed: 2013-2019 are the 2010 tracts and
# 2020-2023 the 2020 tracts. So this needs two cached extracts, not eleven.
GEOM_VINTAGE <- if (YEAR <= 2019L) 2013L else 2020L
CACHE <- "artifacts/2sfca/sensitivity/cache"
acs_path <- file.path(CACHE, sprintf("acs%d_tracts.rds", GEOM_VINTAGE))
if (!file.exists(acs_path)) stop("tract geometry cache missing: ", acs_path)
acs <- readRDS(acs_path)
amd_path <- if (YEAR == 2020L) file.path(CACHE, "age_matched_denominators.rds") else
            file.path(CACHE, sprintf("age_matched_denominators_%d.rds", YEAR))
if (!file.exists(amd_path)) stop("age-matched denominators missing for ", YEAR, ": ", amd_path)
amd <- readRDS(amd_path)
say("year %d (geometry vintage %d)", YEAR, GEOM_VINTAGE)
if (!identical(amd$manifest_sha256, act))
  stop("the denominators were built from a different manifest version", call. = FALSE)

ruca_path <- Sys.getenv("E2SFCA_RUCA_PATH")
src <- new.env(); sys.source("R/accessibility_stratification.R", envir = src)
ruca <- utils::read.csv(ruca_path, colClasses = "character") |>
  dplyr::transmute(GEOID = tract_geoid, rurality = src$rurality_from_ruca(ruca_code))
# The all-ages comparator has to be the same vintage as the age-matched arm,
# otherwise the two regimes differ by year as well as by denominator and the
# contrast stops being attributable to age. Built from that year's own bands.
.bands_path <- file.path(CACHE, sprintf("acs%d_age_bands.rds", YEAR))
if (!file.exists(.bands_path)) stop("ACS age bands missing for ", YEAR, ": ", .bands_path)
.bd <- readRDS(.bands_path)
acs_den_year <- dplyr::tibble(GEOID = .bd$GEOID,
                              total_f = .bd$B01001_026,
                              white_f = .bd$B01001H_017,
                              aian_f  = .bd$B01001C_017)
all_ages <- acs_den_year |> dplyr::left_join(ruca, by = "GEOID") |>
  dplyr::mutate(dplyr::across(c(total_f, white_f, aian_f), ~tidyr::replace_na(., 0)),
                metro_f = ifelse(rurality %in% "Metropolitan", total_f, 0),
                rural_f = ifelse(rurality %in% "Rural", total_f, 0))
say("all-ages denominator: %.0f women", sum(all_ages$total_f))

gg <- build_e2sfca_grid_geometry(acs$geom, resolution = 1000L)
say("grid geometry built (reused by every specification)")

iso_dir <- Sys.getenv("E2SFCA_ISO_DIR")
iso_cache <- new.env()
pop_cache <- new.env()   # keyed by denominator CONTENT, see below
W <- c(`30` = 1.00, `60` = 0.68, `120` = 0.22, `180` = 0.09)
# ordered so subspecialties sharing an age window run consecutively
SUBS <- c("GO","FPMRS","MFM","REI","MIGS","PAG","CFP")

load_iso <- function(sup_ids) {
  key <- digest::digest(sort(sup_ids))
  if (!is.null(iso_cache[[key]])) return(iso_cache[[key]])
  x <- do.call(rbind, lapply(c(30L,60L,120L,180L), function(b) {
    z <- readRDS(file.path(iso_dir, sprintf("isochrones_%dmin_consolidated.rds", b)))
    z$coord_id <- as.character(if ("coord_id" %in% names(z)) z$coord_id else z$location_key)
    z <- z[z$coord_id %in% sup_ids, , drop = FALSE]
    if (!"drive_time_minutes" %in% names(z)) z$drive_time_minutes <- b
    z <- z[, c("coord_id","drive_time_minutes","geometry")]; sf::st_geometry(z) <- "geometry"; z }))
  ctx <- prepare_e2sfca_iso(x, area_crs = E2SFCA_AREA_CRS)
  assign(key, ctx, envir = iso_cache); ctx
}

wmean <- function(surf, wr) {
  a <- terra::values(surf)[,1]; w <- terra::values(wr)[,1]
  a[is.na(a)] <- 0; w[is.na(w)] <- 0
  if (sum(w) <= 0) return(NA_real_); sum(a*w)/sum(w)
}

rows <- list()
for (sp in SUBS) {
  supf <- file.path(S, "sup/run_e2sfca_20260712_190734",
                    sprintf("step_4_2sfca_%s_%d_providers.rds", sp, YEAR))
  if (!file.exists(supf)) stop("supply missing for ", sp, " ", YEAR, ": ", supf)
  sup <- readRDS(supf) |> dplyr::select(coord_id, supply)
  iso <- load_iso(as.character(sup$coord_id))
  n_iso <- length(unique(unlist(lapply(iso$bands, function(b) as.character(b$coord_id)))))

  for (regime in c("all_ages","age_matched")) {
    den <- if (regime == "all_ages") all_ages else {
      d <- amd$denominators[[sp]]
      if (is.null(d)) { say("  %s: no age-matched denominator, skipped", sp); next }
      d
    }
    # Population allocation dominates the runtime -- five area-weighted
    # allocations over 83,776 CONUS tracts per cell -- and most of them are
    # IDENTICAL across cells. The all-ages denominator is the same for all seven
    # subspecialties; GO and FPMRS share 45+; MFM and REI share 15-44. Building
    # them per cell means 70 allocations where 30 distinct ones exist.
    #
    # Cached on the CONTENT of the denominator columns, not on the subspecialty
    # name, so two subspecialties sharing a window provably share the layers
    # rather than being assumed to.
    dkey <- digest::digest(list(den$GEOID, den$total_f, den$metro_f,
                                den$rural_f, den$white_f, den$aian_f))
    if (is.null(pop_cache[[dkey]])) {
      g0 <- attach_e2sfca_population(gg, den[, c("GEOID","total_f")], "total_f",
                                     alloc = "area", na_pop_policy = "zero")
      w0 <- list(total = g0$pop_rast)
      for (col in c("metro_f","rural_f","white_f","aian_f"))
        w0[[col]] <- attach_e2sfca_population(gg, den[, c("GEOID", col)], col,
                                              alloc = "area", na_pop_policy = "zero")$pop_rast
      assign(dkey, list(grid = g0, wr = w0), envir = pop_cache)
      say("    built population layers for a new denominator (%d cached)",
          length(ls(pop_cache)))
    } else say("    reusing cached population layers")
    pc <- pop_cache[[dkey]]; grid <- pc$grid; wr <- pc$wr
    r <- suppressWarnings(compute_e2sfca_raster(
      grid, iso, sup, weights = W, per_capita_scale = 1e5, return_surface = TRUE,
      # FAIL CLOSED. This was "drop", and it is what produced the 0.786%
      # shortfall: five of 516 GO origins had no catchment, their supply
      # evaporated, and the run reported success. The engine's "error" path
      # already names the offending coord_ids and quantifies the supply share
      # they carry, so a year whose isochrones do not cover its providers now
      # stops loudly instead of returning a plausible number.
      unmatched_supply_policy = "error"))
    surf <- r$surface * 1e5
    m <- vapply(c("total","metro_f","rural_f","white_f","aian_f"),
                function(k) wmean(surf, wr[[k]]), numeric(1))
    rows[[length(rows)+1L]] <- data.frame(
      year = YEAR, regime = regime, subspec = sp,
      age_range = if (regime=="all_ages") "all ages" else
        Filter(function(z) z$code==sp, man$subspecialties)[[1]]$age_range,
      denominator = sum(den$total_f, na.rm = TRUE),
      national = m[["total"]], metro = m[["metro_f"]], rural = m[["rural_f"]],
      white = m[["white_f"]], aian = m[["aian_f"]],
      rural_metro_ratio = m[["rural_f"]]/m[["metro_f"]],
      aian_white_ratio  = m[["aian_f"]]/m[["white_f"]],
      n_supply_origins = nrow(sup), n_iso_origins = n_iso,
      stringsAsFactors = FALSE)
    say("  %-6s %-12s den=%11.0f  nat=%.4f  rural/metro=%.4f  aian/white=%.4f",
        sp, regime, sum(den$total_f), m[["total"]],
        m[["rural_f"]]/m[["metro_f"]], m[["aian_f"]]/m[["white_f"]])
  }
}
res <- do.call(rbind, rows)
dir.create("artifacts/multiverse", showWarnings = FALSE, recursive = TRUE)
out_csv <- if (YEAR == 2020L) "artifacts/multiverse/age_matched_results.csv" else
           sprintf("artifacts/multiverse/age_matched_results_%d.csv", YEAR)
utils::write.csv(res, out_csv, row.names = FALSE)
say("wrote %s", out_csv)
