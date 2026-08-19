#!/usr/bin/env Rscript
# =============================================================================
# desjardins7/00_build_data.R
# -----------------------------------------------------------------------------
# Recreate Desjardins et al. (Obstet Gynecol 2023) "Geographic Disparities in
# Potential Accessibility to Gynecologic Oncologists" — extended to ALL SEVEN
# OB/GYN subspecialties, using OUR E2SFCA run (travel-time isochrones,
# 2013-2023, canonical run e2sfca_20260712_190734). One faceted paper.
#
# This script produces the shared data tables the manuscript/figures consume:
#   table1_physicians.csv            Desjardins Table 1 (career stage x rurality)
#   table2_women_quintile_race.csv   Desjardins Table 2 (women x quintile x race)
#   table3_mean_access_rurality.csv  Desjardins Table 3 (mean access x rurality)
#   fig2b_counts.csv                 Desjardins Fig 2B (yearly workforce counts)
#   quintile_tract_2020.csv          per-tract quintile (Desjardins Fig 3 input)
# Anchor cross-section = 2020 (Desjardins' final period); trend = 2013-2023.
# =============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
if (!exists("E2SFCA_FROZEN_RUN_ID")) source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))  # SSOT: frozen E2SFCA run
source(file.path(ROOT, "R", "accessibility_stratification.R"))
say <- function(...) { cat(sprintf("[dj7] %s\n", sprintf(...))); flush.console() }

RUN   <- E2SFCA_FROZEN_RUN_ID
UNP   <- file.path(ROOT, "artifacts", "2sfca", "ec2", RUN, "unpacked")
OUT   <- file.path(ROOT, "artifacts", "desjardins7"); dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
SUBS  <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")      # display order
YR    <- 2020L
NAME2CODE <- c(
  "Gynecologic Oncology"="GO", "CRI"="GO", "Hospice and Palliative Medicine"="GO",
  "Maternal-Fetal Medicine"="MFM", "Reproductive Endocrinology and Infertility"="REI",
  "Female Pelvic Medicine & Reconstructive Surgery"="FPMRS", "MIG"="MIGS",
  "Pediatric & Adolescent Gynecology"="PAG", "Complex Family Planning"="CFP")
RACE_COLS <- c(white_nh="White, non-Hispanic", black="Black alone",
               hispanic="Hispanic (any race)", asian="Asian alone",
               aian="American Indian or Alaska Native", nhpi="Native Hawaiian/Pac. Islander")

# ---- shared inputs ----------------------------------------------------------
acs  <- readRDS(file.path(ROOT, "artifacts", "2sfca", "cell_zero", "cache", "acs2020_allrace.rds"))
den  <- acs$den |> dplyr::mutate(dplyr::across(-GEOID, ~tidyr::replace_na(as.numeric(.), 0)))
ruca <- read.csv(file.path(ROOT, "data", "external", "ruca_tract_mapping.csv"), colClasses = "character") |>
  dplyr::transmute(GEOID = tract_geoid, rurality = rurality_from_ruca(as.integer(ruca_code)))
den  <- den |> dplyr::left_join(ruca, by = "GEOID")
say("ACS 2020 tracts=%d  total female=%.0f", nrow(den), sum(den$total_f))

idx  <- readr::read_csv(file.path(ROOT, "artifacts", "2sfca", "ec2", RUN, "e2sfca_index.csv"),
                        show_col_types = FALSE)
ycm  <- readRDS(file.path(ROOT, "artifacts", "20260702_120134_90bf52ef", "step_3_year_coord_map.rds"))
long <- readr::read_csv(file.path(ROOT, "artifacts", "2sfca", "figures",
                        "allsubspec_allyears_stratified_LONG.csv"), show_col_types = FALSE)

access_path <- function(s) file.path(UNP, sprintf("step_4_2sfca_%s_%d.rds", s, YR))

# =============================================================================
# Fig 2B — yearly active PHYSICIAN counts, 2013-2023.
# NOTE: e2sfca_index.csv$n_providers counts distinct coordinate LOCATIONS
# (GO 2020 = 516), not physicians (890). We count distinct active NPIs per
# (subspecialty, year) from the year-coord map so the trend, Table 1, and the
# 2020 workforce are all in the SAME physician unit.
# =============================================================================
ycm$code <- NAME2CODE[ycm$subspecialty_name]
phys_year <- ycm |>
  dplyr::filter(!is.na(coord_id), !is.na(lat), !is.na(code)) |>
  dplyr::distinct(npi, code, analysis_year) |>
  dplyr::count(code, analysis_year, name = "n_providers") |>
  dplyr::transmute(subspec = code, year = analysis_year, n_providers) |>
  dplyr::filter(subspec %in% SUBS) |>
  dplyr::arrange(match(subspec, SUBS), year)
readr::write_csv(phys_year, file.path(OUT, "fig2b_counts.csv"))
say("fig2b_counts.csv (physicians): %d rows; 2013 total=%d 2020 total=%d 2023 total=%d",
    nrow(phys_year), sum(phys_year$n_providers[phys_year$year==2013]),
    sum(phys_year$n_providers[phys_year$year==2020]),
    sum(phys_year$n_providers[phys_year$year==2023]))

# =============================================================================
# Table 3 — mean access score by rurality (Metro/Rural), 2020 + full trend
# =============================================================================
t3_long <- long |>
  dplyr::filter(stratum_type == "rurality", subspec %in% SUBS) |>
  dplyr::select(subspec, year, rurality = stratum, mean_access, pct_zero, women)
readr::write_csv(t3_long, file.path(OUT, "table3_mean_access_rurality.csv"))
t3_2020 <- t3_long |> dplyr::filter(year == YR) |>
  tidyr::pivot_wider(id_cols = subspec, names_from = rurality,
                     values_from = c(mean_access, pct_zero)) |>
  dplyr::mutate(metro_rural_ratio = mean_access_Metropolitan /
                  pmax(mean_access_Rural, .Machine$double.eps))
readr::write_csv(t3_2020, file.path(OUT, "table3_mean_access_rurality_2020_wide.csv"))
say("table3: %d subspec-year rows; 2020 metro:rural ratio range %.2f-%.2f",
    nrow(t3_long), min(t3_2020$metro_rural_ratio), max(t3_2020$metro_rural_ratio))

# =============================================================================
# Table 1 — physician descriptive statistics (career stage x rurality), 2020
#   career: early-to-mid = <=15 yr since certification; late = >15 yr
#   rurality: physician practice tract -> RUCA (Metropolitan / Rural)
# =============================================================================
act <- ycm |>
  dplyr::filter(analysis_year == YR, !is.na(coord_id), !is.na(lat), !is.na(code)) |>
  dplyr::distinct(npi, code, .keep_all = TRUE) |>
  dplyr::transmute(npi, code, cert = certification_year, lat, lon)
# assign each physician a tract -> rurality (planar join in EPSG:5070)
pts   <- sf::st_as_sf(act, coords = c("lon","lat"), crs = 4326) |> sf::st_transform(5070)
polys <- sf::st_transform(acs$geom, 5070)
jn    <- sf::st_join(pts, polys[, "GEOID"], join = sf::st_within)
act$GEOID <- jn$GEOID
act <- act |> dplyr::left_join(ruca, by = "GEOID")
act$rurality[is.na(act$rurality)] <- "Rural"           # unmatched (offshore/border) -> rural
act$stage <- ifelse((YR - act$cert) <= 15, "Early-to-mid", "Late")

t1 <- act |>
  dplyr::group_by(code) |>
  dplyr::summarise(
    total        = dplyr::n(),
    early         = sum(stage == "Early-to-mid"),
    late          = sum(stage == "Late"),
    metro         = sum(rurality == "Metropolitan"),
    rural         = sum(rurality == "Rural"),
    early_metro   = sum(stage == "Early-to-mid" & rurality == "Metropolitan"),
    late_metro    = sum(stage == "Late"         & rurality == "Metropolitan"),
    early_rural   = sum(stage == "Early-to-mid" & rurality == "Rural"),
    late_rural    = sum(stage == "Late"         & rurality == "Rural"),
    med_yrs_cert  = median(YR - cert), .groups = "drop") |>
  dplyr::mutate(
    pct_early = 100 * early / total, pct_rural = 100 * rural / total)
# workforce growth 2013 -> 2023 from PHYSICIAN counts (same unit as `total`)
growth <- phys_year |> dplyr::filter(year %in% c(2013, 2023)) |>
  dplyr::transmute(code = subspec, year, n_providers) |>
  tidyr::pivot_wider(names_from = year, values_from = n_providers, names_prefix = "n") |>
  dplyr::mutate(growth_pct = 100 * (n2023 - n2013) / n2013)
t1 <- t1 |> dplyr::left_join(growth, by = "code") |>
  dplyr::arrange(match(code, SUBS))
readr::write_csv(t1, file.path(OUT, "table1_physicians.csv"))
say("table1: totals %s", paste(t1$code, t1$total, sep="=", collapse=" "))

# =============================================================================
# Table 2 — at-risk adult women within each accessibility quintile, by race
#   Q1 = zero-access tracts; Q2-Q5 = quartiles of positive-access tract values.
# Also emits per-tract quintile (Fig 3 input).
# =============================================================================
quintile_rows <- list(); table2_rows <- list()
for (s in SUBS) {
  acc <- readRDS(access_path(s)) |>
    dplyr::transmute(GEOID = as.character(GEOID),
                     access = access_mean_population_per100k)
  d <- den |> dplyr::left_join(acc, by = "GEOID")
  d$access[is.na(d$access)] <- 0
  pos <- d$access[d$access > 0]
  brk <- stats::quantile(pos, probs = c(.25, .5, .75), na.rm = TRUE)
  d$quintile <- with(d, dplyr::case_when(
    access <= 0                 ~ 1L,
    access <= brk[1]            ~ 2L,
    access <= brk[2]            ~ 3L,
    access <= brk[3]            ~ 4L,
    TRUE                        ~ 5L))
  quintile_rows[[s]] <- d |> dplyr::transmute(subspec = s, GEOID, access, quintile)
  # women by race x quintile
  for (rc in names(RACE_COLS)) {
    tot <- sum(d[[rc]])
    agg <- tapply(d[[rc]], d$quintile, sum)
    for (q in 1:5) {
      n <- ifelse(is.na(agg[as.character(q)]), 0, agg[as.character(q)])
      table2_rows[[length(table2_rows) + 1]] <- data.frame(
        subspec = s, race = RACE_COLS[[rc]], quintile = q,
        women = as.numeric(n), pct = 100 * as.numeric(n) / tot)
    }
  }
  say("  %s: Q1 zero-access women (total female)=%.1f%%",
      s, 100 * sum(d$total_f[d$quintile == 1]) / sum(d$total_f))
}
q_tbl <- dplyr::bind_rows(quintile_rows)
readr::write_csv(q_tbl, file.path(OUT, "quintile_tract_2020.csv"))
t2 <- dplyr::bind_rows(table2_rows)
readr::write_csv(t2, file.path(OUT, "table2_women_quintile_race.csv"))
say("table2: %d rows; quintile_tract: %d rows", nrow(t2), nrow(q_tbl))

cat("\n=== DONE — outputs in artifacts/desjardins7/ ===\n")
print(list.files(OUT))
