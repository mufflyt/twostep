#!/usr/bin/env Rscript
# PRE-SPECIFIED ANALYSIS: what the Connecticut correction changes.
#
# Written and committed BEFORE the corrected cells finished computing, so the
# comparison cannot be shaped by having seen the answer.
#
# THE QUESTION
#
#   After restoring Connecticut to BOTH the E2SFCA Step-1 demand denominator and
#   the population-weighted outcome denominator, how much do the 2022-2023
#   estimates change, and does any manuscript inference change?
#
# WHY THE DECOMPOSITION MATTERS
#
# A zero-population Connecticut did two separate things:
#
#   (a) OUTCOME DENOMINATOR. CT tracts had an undefined population-weighted
#       zonal mean (NaN -> NA) and so dropped out of every population-weighted
#       statistic. 1,842,121 women.
#
#   (b) DEMAND DENOMINATOR. CT women were absent from Step-1 weighted demand for
#       every provider whose catchment reaches the state, inflating those
#       providers' supply-to-demand ratios -- and therefore inflating access in
#       NEIGHBOURING states (NY, MA, RI), not only in Connecticut.
#
# An earlier bound imputed CT's 2022-2023 access from its 2021 values. That
# captures (a) and CANNOT capture (b), because it never re-runs Step 1. It was
# suggested there that (b) "should partially offset" (a). That is plausible but
# it is a guess; with a real rebuild the net sign and size are measurable, so
# this script MEASURES it and does not carry the guess forward.
#
# THE DECOMPOSITION is additive and exact:
#
#   mean_frozen        = sum_{nonCT} P*A_frozen / sum_{nonCT} P
#   mean_nonCT_corr    = sum_{nonCT} P*A_corr   / sum_{nonCT} P
#   mean_corrected     = sum_{all}   P*A_corr   / sum_{all}   P
#
#   second-order effect (b) = mean_nonCT_corr - mean_frozen
#     -- non-CT tracts only, so any movement here is caused solely by CT
#        entering the Step-1 demand of providers that reach it.
#   direct effect (a)       = mean_corrected  - mean_nonCT_corr
#     -- adding Connecticut back into the outcome denominator.
#
# Usage:
#   Rscript scripts/analyze_ct_correction.R --corrected <dir> --frozen <dir> \
#     [--out artifacts/ct_correction]

suppressMessages({ library(dplyr) })

args <- commandArgs(trailingOnly = TRUE)
arg <- function(f, d = NA_character_) { i <- which(args == f); if (length(i)) args[i + 1L] else d }

CORR <- arg("--corrected")
FROZ <- arg("--frozen")
OUT  <- arg("--out", "artifacts/ct_correction")
SPECS <- c("CFP", "FPMRS", "GO", "MFM", "MIGS", "PAG", "REI")
YEARS <- c(2022L, 2023L)

stopifnot(!is.na(CORR), dir.exists(CORR))
stopifnot(!is.na(FROZ), dir.exists(FROZ))

# Ported from isochrones 2026-08-18. There the relabel lived in
# R/census_data_fetcher.R alongside the ACS fetchers; in twostep it is a
# first-class export of its own module. Same function, same equivalency table.
source(file.path("R", "ct_geoid_relabel.R"))
BUNDLE <- readRDS(file.path("artifacts", "2sfca_seam", "acs_bundle_2013_2022.rds"))

# Population on the LEGACY GEOID vocabulary the tract layer uses. This is the
# SAME relabel the pipeline now applies, so the analysis denominator and the
# production denominator cannot silently diverge.
acs_year_of <- function(y) as.character(max(min(y, 2022L), 2013L))
pop_of <- function(y) {
  p <- BUNDLE$pop_by_year[[acs_year_of(y)]]
  p <- tibble(GEOID = as.character(p$GEOID), pop = as.numeric(p$female_pop))
  p <- suppressMessages(relabel_ct_geoids_safe(p, as.integer(acs_year_of(y))))
  stats::setNames(p$pop, p$GEOID)
}
POP <- lapply(stats::setNames(c(2013L, 2021L, YEARS), c("2013", "2021", YEARS)), pop_of)

read_cell <- function(dir, s, y) {
  f <- file.path(dir, sprintf("step_4_2sfca_%s_%d.rds", s, y))
  if (!file.exists(f)) return(NULL)
  d <- readRDS(f)
  tibble(GEOID = as.character(d$GEOID), a = as.numeric(d$access_mean_population_per100k))
}
read_prov <- function(dir, s, y) {
  f <- file.path(dir, sprintf("step_4_2sfca_%s_%d_providers.rds", s, y))
  if (!file.exists(f)) return(NULL)
  as.data.frame(readRDS(f))
}

is_ct <- function(g) substr(g, 1, 2) == "09"

wmean <- function(a, p) {
  ok <- !is.na(a) & !is.na(p) & p > 0
  if (!any(ok)) return(NA_real_)
  sum(a[ok] * p[ok]) / sum(p[ok])
}

# ---------------------------------------------------------------- per cell ---

analyze <- function(s, y) {
  fr <- read_cell(FROZ, s, y); co <- read_cell(CORR, s, y)
  if (is.null(fr) || is.null(co)) return(NULL)
  # Align on GEOID; both should be the same tract layer.
  stopifnot(setequal(fr$GEOID, co$GEOID))
  co <- co[match(fr$GEOID, co$GEOID), ]
  g <- fr$GEOID
  P <- POP[[as.character(y)]][g]
  ct <- is_ct(g)

  # --- headline means ------------------------------------------------------
  m_frozen     <- wmean(fr$a, P)
  m_corrected  <- wmean(co$a, P)
  m_nonCT_froz <- wmean(fr$a[!ct], P[!ct])
  m_nonCT_corr <- wmean(co$a[!ct], P[!ct])

  # --- exclusion accounting ------------------------------------------------
  zero_f <- !is.na(fr$a) & fr$a == 0; zero_c <- !is.na(co$a) & co$a == 0
  na_f   <- is.na(fr$a);              na_c   <- is.na(co$a)
  pop_tot <- sum(P, na.rm = TRUE)

  # --- supply conservation residual (exact at step2_power = 1) -------------
  # access is per-100k, so divide by 1e5 before weighting by population.
  resid <- function(dir, acc) {
    pv <- read_prov(dir, s, y)
    if (is.null(pv)) return(NA_real_)
    # SCHEMA DRIFT, handled explicitly rather than assumed away. The frozen
    # engine's provider table has no `zero_demand` column -- that field was
    # added later, together with `ratio_for_surface` and `excluded_supply`.
    # "Included" means the same thing in both: a provider whose weighted demand
    # is strictly positive. Deriving it from weighted_demand makes the two arms
    # comparable instead of silently NA for the frozen side.
    zd <- if ("zero_demand" %in% names(pv)) as.logical(pv$zero_demand)
          else !(as.numeric(pv$weighted_demand) > 0)
    included <- sum(pv$supply[!zd], na.rm = TRUE)
    lhs <- sum(P * acc / 1e5, na.rm = TRUE)
    if (included == 0) return(NA_real_)
    (lhs - included) / included
  }

  # --- Connecticut itself, treated as newly estimable ----------------------
  ct_frozen <- wmean(fr$a[ct], P[ct])      # expected NA / near-absent
  ct_corr   <- wmean(co$a[ct], P[ct])

  tibble(
    subspecialty = s, year = y,
    pop_eligible = pop_tot,
    mean_frozen = m_frozen, mean_corrected = m_corrected,
    delta_pct = 100 * (m_corrected - m_frozen) / m_frozen,
    # additive decomposition
    second_order = m_nonCT_corr - m_nonCT_froz,
    direct       = m_corrected - m_nonCT_corr,
    second_order_pct = 100 * (m_nonCT_corr - m_nonCT_froz) / m_frozen,
    direct_pct       = 100 * (m_corrected - m_nonCT_corr) / m_frozen,
    n_zero_frozen = sum(zero_f), n_zero_corr = sum(zero_c),
    pop_zero_frozen_pct = 100 * sum(P[zero_f], na.rm = TRUE) / pop_tot,
    pop_zero_corr_pct   = 100 * sum(P[zero_c], na.rm = TRUE) / pop_tot,
    n_na_frozen = sum(na_f), n_na_corr = sum(na_c),
    pop_na_frozen_pct = 100 * sum(P[na_f], na.rm = TRUE) / pop_tot,
    pop_na_corr_pct   = 100 * sum(P[na_c], na.rm = TRUE) / pop_tot,
    conservation_resid_frozen = resid(FROZ, fr$a),
    conservation_resid_corr   = resid(CORR, co$a),
    ct_mean_frozen = ct_frozen, ct_mean_corrected = ct_corr
  )
}

res <- bind_rows(lapply(SPECS, function(s) bind_rows(lapply(YEARS, function(y) analyze(s, y)))))

# ------------------------------------------------------------- temporal ------

# Baseline years are unaffected by the CT fix (ACS < 2022 carries no
# planning-region GEOIDs), so they are read from the frozen set for BOTH arms --
# stated explicitly rather than assumed.
base_mean <- function(s, y) {
  d <- read_cell(FROZ, s, y)
  if (is.null(d)) return(NA_real_)
  wmean(d$a, POP[[as.character(y)]][d$GEOID])
}

temporal <- bind_rows(lapply(SPECS, function(s) {
  m13 <- base_mean(s, 2013L); m21 <- base_mean(s, 2021L)
  r22 <- res[res$subspecialty == s & res$year == 2022L, ]
  r23 <- res[res$subspecialty == s & res$year == 2023L, ]
  if (!nrow(r22) || !nrow(r23)) return(NULL)
  pc <- function(a, b) 100 * (b - a) / a
  tibble(
    subspecialty = s,
    d2122_frozen = pc(m21, r22$mean_frozen),    d2122_corr = pc(m21, r22$mean_corrected),
    d2223_frozen = pc(r22$mean_frozen, r23$mean_frozen),
    d2223_corr   = pc(r22$mean_corrected, r23$mean_corrected),
    d1323_frozen = pc(m13, r23$mean_frozen),    d1323_corr = pc(m13, r23$mean_corrected),
    sign_flip_2122 = sign(pc(m21, r22$mean_frozen)) != sign(pc(m21, r22$mean_corrected)),
    sign_flip_2223 = sign(pc(r22$mean_frozen, r23$mean_frozen)) !=
                     sign(pc(r22$mean_corrected, r23$mean_corrected)),
    sign_flip_1323 = sign(pc(m13, r23$mean_frozen)) != sign(pc(m13, r23$mean_corrected))
  )
}))

# Ranking of subspecialties by access -- an inference that could change even if
# no individual value moves much.
rank_change <- bind_rows(lapply(YEARS, function(y) {
  r <- res[res$year == y, ]
  tibble(year = y,
         rank_frozen = paste(r$subspecialty[order(-r$mean_frozen)], collapse = " > "),
         rank_corrected = paste(r$subspecialty[order(-r$mean_corrected)], collapse = " > "),
         ranking_changed = !identical(order(-r$mean_frozen), order(-r$mean_corrected)))
}))

dir.create(OUT, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(res, file.path(OUT, "per_cell.csv"), row.names = FALSE)
utils::write.csv(temporal, file.path(OUT, "temporal.csv"), row.names = FALSE)
utils::write.csv(rank_change, file.path(OUT, "ranking.csv"), row.names = FALSE)

# ------------------------------------------------------------------ report ---

cat("\n== HEADLINE: population-weighted E2SFCA mean (per 100k) ==\n")
cat(sprintf("%-6s %5s %11s %11s %8s | %10s %10s\n",
            "spec", "year", "frozen", "corrected", "delta%", "2nd-order%", "direct%"))
for (i in seq_len(nrow(res))) with(res[i, ],
  cat(sprintf("%-6s %5d %11.4f %11.4f %+7.2f%% | %+9.3f%% %+9.3f%%\n",
              subspecialty, year, mean_frozen, mean_corrected, delta_pct,
              second_order_pct, direct_pct)))

cat("\n== EXCLUSION ACCOUNTING ==\n")
cat(sprintf("%-6s %5s %12s %12s %12s %12s\n",
            "spec", "year", "NA_n frozen", "NA_n corr", "pop_NA% froz", "pop_NA% corr"))
for (i in seq_len(nrow(res))) with(res[i, ],
  cat(sprintf("%-6s %5d %12d %12d %11.3f%% %11.3f%%\n",
              subspecialty, year, n_na_frozen, n_na_corr,
              pop_na_frozen_pct, pop_na_corr_pct)))

cat("\n== SUPPLY CONSERVATION RESIDUAL (exact at p=1; |x| should be ~0) ==\n")
for (i in seq_len(nrow(res))) with(res[i, ],
  cat(sprintf("  %-6s %d  frozen %+10.3e   corrected %+10.3e\n",
              subspecialty, year, conservation_resid_frozen, conservation_resid_corr)))

cat("\n== CONNECTICUT, newly estimable ==\n")
for (i in seq_len(nrow(res))) with(res[i, ],
  cat(sprintf("  %-6s %d  frozen %s   corrected %.4f\n", subspecialty, year,
              if (is.na(ct_mean_frozen)) "     ABSENT" else sprintf("%10.4f", ct_mean_frozen),
              ct_mean_corrected)))

cat("\n== TEMPORAL ==\n")
cat(sprintf("%-6s %18s %18s %18s\n", "spec", "2021->2022", "2022->2023", "2013->2023"))
for (i in seq_len(nrow(temporal))) with(temporal[i, ],
  cat(sprintf("%-6s %8.2f%%/%7.2f%% %8.2f%%/%7.2f%% %8.2f%%/%7.2f%%\n",
              subspecialty, d2122_frozen, d2122_corr, d2223_frozen, d2223_corr,
              d1323_frozen, d1323_corr)))

cat("\n== INFERENCE CHANGES ==\n")
# A zero count from an EMPTY temporal table would read as "no sign flips" when
# it actually means "no comparison was made". Say which it is.
if (!nrow(temporal)) {
  cat("  temporal comparison NOT RUN -- baseline cells absent from the frozen dir\n")
} else {
  cat(sprintf("  sign flips 2021->2022 : %d\n", sum(temporal$sign_flip_2122, na.rm = TRUE)))
  cat(sprintf("  sign flips 2022->2023 : %d\n", sum(temporal$sign_flip_2223, na.rm = TRUE)))
  cat(sprintf("  sign flips 2013->2023 : %d\n", sum(temporal$sign_flip_1323, na.rm = TRUE)))
}
for (i in seq_len(nrow(rank_change))) with(rank_change[i, ],
  cat(sprintf("  ranking %d changed    : %s\n     frozen    : %s\n     corrected : %s\n",
              year, ranking_changed, rank_frozen, rank_corrected)))
cat(sprintf("  max |delta| on any cell: %.3f%%\n", max(abs(res$delta_pct), na.rm = TRUE)))
cat("\n  SPAR: not materialized by compute_e2sfca_raster(); identity mean(SPAR)==1\n")
cat("        cannot be evaluated on real outputs. Reported as not applicable.\n")
