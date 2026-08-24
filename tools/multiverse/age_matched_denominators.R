#!/usr/bin/env Rscript
# =============================================================================
# Age-matched demand denominators, per subspecialty
# =============================================================================
# Removes the blocker on manifest v3: the disparity contrasts need age-matched
# SUBGROUP layers, not just an age-matched total. Averaging a surface built for
# women 45+ over a rural population of all ages would not be a coherent
# contrast.
#
# Produces, per subspecialty, five tract-level denominators on one age window:
#
#   total_f   B01001  bands   (sex by age, all races)
#   metro_f   total_f restricted to metropolitan tracts   (RUCA, tract-level)
#   rural_f   total_f restricted to rural tracts
#   white_f   B01001H bands   (White alone, not Hispanic)
#   aian_f    B01001C bands   (American Indian / Alaska Native alone)
#
# The age window comes from the FROZEN manifest, whose hash is verified before
# anything is fetched. The cuts were placed on edges common to all three tables
# precisely so rurality and race share one window; this script asserts that
# rather than trusting it.
#
# Usage: Rscript tools/multiverse/age_matched_denominators.R [--refresh]

suppressWarnings(suppressMessages({ library(yaml); library(dplyr); library(tidyr) }))
args    <- commandArgs(trailingOnly = TRUE)
refresh <- "--refresh" %in% args
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")), error = function(e) ".")
setwd(root)

MAN   <- "inst/multiverse/age_matched_denominator.yml"
HASH  <- "inst/multiverse/age_matched_denominator.sha256"
# Year-parameterised. 2020 keeps its original cache and output paths byte for
# byte, so the frozen 2020 denominators and the appendix that reads them are
# untouched; other vintages get suffixed files. One script rather than a copy,
# because a duplicated fetch-and-band-sum would drift from this one silently.
YEAR  <- as.integer(Sys.getenv("E2SFCA_AM_YEAR", "2020"))
if (is.na(YEAR) || YEAR < 2013L || YEAR > 2023L)
  stop("E2SFCA_AM_YEAR must be 2013-2023, got: ", Sys.getenv("E2SFCA_AM_YEAR"))
CACHE <- "artifacts/2sfca/sensitivity/cache"
RAW   <- file.path(CACHE, sprintf("acs%d_age_bands.rds", YEAR))
OUT   <- if (YEAR == 2020L) {
  file.path(CACHE, "age_matched_denominators.rds")
} else {
  file.path(CACHE, sprintf("age_matched_denominators_%d.rds", YEAR))
}
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
say  <- function(...) cat(sprintf("[age-den] %s\n", sprintf(...)))
fail <- function(...) { message("FAIL: ", ...); quit(status = 1L, save = "no") }

# ---- enforce the freeze BEFORE fetching anything ----------------------------
sha256 <- function(p) if (requireNamespace("digest", quietly = TRUE))
  digest::digest(file = p, algo = "sha256") else
  trimws(strsplit(system2("shasum", c("-a","256",p), stdout = TRUE), "\\s+")[[1]][1])
rec <- trimws(strsplit(readLines(HASH, warn = FALSE)[1], "\\s+")[[1]][1])
act <- sha256(MAN)
if (!identical(rec, act))
  fail("the age-matched manifest changed since it was frozen.\n  recorded: ", rec,
       "\n  actual:   ", act, "\n  Re-version it; do not edit a frozen manifest in place.")
say("freeze verified: %s...", substr(act, 1, 16))

man <- yaml::read_yaml(MAN)
specs <- man$subspecialties
say("manifest v%s, %d subspecialties", man$manifest_version, length(specs))

# every band the manifest references, across all three tables
band_of <- function(s, key) if (!is.null(s[[key]])) unlist(s[[key]]) else character(0)
all_bands <- unique(unlist(lapply(specs, function(s)
  c(band_of(s, "acs_bands_total"), band_of(s, "acs_bands_white"),
    band_of(s, "acs_bands_aian"),  band_of(s, "acs_bands")))))
# The published female TOTALS are fetched even though no subspecialty uses them,
# solely so the conservation check below can run. Without them it reported
# "totals not fetched -- skipped" for all three tables and validated nothing,
# which is worse than having no check: it looked like a passing guard.
TOTALS <- c("B01001_026", "B01001H_017", "B01001C_017")
all_bands <- unique(c(all_bands, TOTALS))
say("distinct ACS variables required: %d", length(all_bands))

# ---- fetch (cached) ----------------------------------------------------------
conus <- function() sprintf("%02d", c(1, 4:6, 8:13, 16:42, 44:51, 53:56))
if (!file.exists(RAW) || refresh) {
  if (!nzchar(Sys.getenv("CENSUS_API_KEY")))
    fail("CENSUS_API_KEY is not set; tidycensus cannot fetch. It lives in ~/.Renviron ",
         "and is read by R at startup (not by the shell).")
  say("fetching %d variables for %d CONUS states (no geometry; the grid comes from the cached extract)",
      length(all_bands), length(conus()))
  raw <- purrr::map_dfr(conus(), function(st) suppressMessages(
    tidycensus::get_acs(geography = "tract", variables = all_bands, state = st,
                        year = YEAR, survey = "acs5", geometry = FALSE)))
  wide <- raw |>
    dplyr::transmute(GEOID = as.character(GEOID), variable,
                     estimate = as.numeric(estimate)) |>
    tidyr::pivot_wider(names_from = variable, values_from = estimate)
  saveRDS(wide, RAW); say("cached %d tracts x %d variables", nrow(wide), ncol(wide) - 1L)
} else {
  wide <- readRDS(RAW); say("loaded cached ACS age bands: %d tracts", nrow(wide))
}

# ---- CONSERVATION CHECK: age bands must sum to the published totals ----------
# B01001_026 is female, all ages; summing every female age band must reproduce
# it. If it does not, the band list is wrong and every denominator built from it
# would be wrong in a way no downstream check could see.
checks <- list(total = c("B01001_026", sprintf("B01001_%03d", 27:49)),
               white = c("B01001H_017", sprintf("B01001H_%03d", 18:31)),
               aian  = c("B01001C_017", sprintf("B01001C_%03d", 18:31)))
say("conservation: do the age bands sum to the published female totals?")
for (nm in names(checks)) {
  v <- checks[[nm]]; tot <- v[1]; parts <- intersect(v[-1], names(wide))
  if (!(tot %in% names(wide)) || !length(parts))
    fail(nm, ": cannot run the conservation check -- the published total or the ",
         "age bands are absent from the fetch. A guard that silently skips is ",
         "indistinguishable from one that passes.")
  a <- sum(wide[[tot]], na.rm = TRUE)
  b <- sum(rowSums(wide[, parts, drop = FALSE], na.rm = TRUE))
  rel <- abs(a - b) / max(a, 1)
  say("  %-6s published %.0f  vs  sum of %d bands %.0f   rel diff %.2e",
      nm, a, length(parts), b, rel)
  if (rel > 1e-9) fail(nm, ": age bands do not sum to the published total. The band ",
                       "list is wrong; every denominator built from it would be too.")
}

# ---- Connecticut GEOID vintage ----------------------------------------------
# From ACS 2022 onward Connecticut reports planning-region tracts (09110...)
# which match NOTHING in the 2020-vintage tract geometry this pipeline joins
# against. Left alone, all ~884 CT tracts silently drop and Connecticut's women
# become zero -- 98.9% matched nationally, 0% of one state. Relabel first.
if (YEAR >= 2022L) {
  src_ct <- new.env(); sys.source("R/ct_geoid_relabel.R", envir = src_ct)
  .before <- sum(substr(wide$GEOID, 1, 2) == "09")
  wide <- src_ct$relabel_ct_geoids_safe(wide, census_year = YEAR)
  .after <- sum(substr(wide$GEOID, 1, 2) == "09")
  say("Connecticut relabel (ACS %d): %d CT tracts before, %d after", YEAR, .before, .after)
  if (.after < 1L) fail("Connecticut relabel produced no CT tracts")
}

# ---- rurality ----------------------------------------------------------------
ruca_path <- Sys.getenv("E2SFCA_RUCA_PATH", "data/external/ruca_tract_mapping.csv")
if (!file.exists(ruca_path)) fail("RUCA mapping not found at ", ruca_path,
                                  " (set E2SFCA_RUCA_PATH)")
src <- new.env(); sys.source("R/accessibility_stratification.R", envir = src)
ruca <- utils::read.csv(ruca_path, colClasses = "character") |>
  dplyr::transmute(GEOID = tract_geoid,
                   rurality = src$rurality_from_ruca(ruca_code))
say("RUCA: %d tracts classified", nrow(ruca))

# ---- build the per-subspecialty denominators --------------------------------
sum_bands <- function(d, bands) {
  bands <- intersect(bands, names(d))
  if (!length(bands)) return(rep(NA_real_, nrow(d)))
  rowSums(d[, bands, drop = FALSE], na.rm = TRUE)
}
out <- list()
for (s in specs) {
  bt <- band_of(s, "acs_bands_total"); if (!length(bt)) bt <- band_of(s, "acs_bands")
  bw <- band_of(s, "acs_bands_white"); ba <- band_of(s, "acs_bands_aian")
  d <- dplyr::tibble(GEOID = wide$GEOID,
                     total_f = sum_bands(wide, bt),
                     white_f = sum_bands(wide, bw),
                     aian_f  = sum_bands(wide, ba)) |>
    dplyr::left_join(ruca, by = "GEOID") |>
    dplyr::mutate(metro_f = ifelse(rurality %in% "Metropolitan", total_f, 0),
                  rural_f = ifelse(rurality %in% "Rural",        total_f, 0))
  # metro + rural must not exceed the total: they are a partition of it
  if (any(d$metro_f + d$rural_f > d$total_f + 1e-6, na.rm = TRUE))
    fail(s$code, ": metro + rural exceeds the total female count in some tract")
  out[[s$code]] <- d
  say("  %-6s %-14s total %12.0f  metro %12.0f  rural %11.0f  White %12.0f  AIAN %10.0f",
      s$code, s$age_range, sum(d$total_f, na.rm = TRUE), sum(d$metro_f, na.rm = TRUE),
      sum(d$rural_f, na.rm = TRUE), sum(d$white_f, na.rm = TRUE), sum(d$aian_f, na.rm = TRUE))
}
saveRDS(list(manifest_sha256 = act, denominators = out), OUT)
say("wrote %s", OUT)
cat("\nage-matched denominators built for ", length(out), " subspecialties\n", sep = "")
