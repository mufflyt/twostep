#!/usr/bin/env Rscript
# ============================================================================
# Comparator-informed manuscript additions (Green Journal revision).
# Builds four PER-DISCIPLINE (never pooled) tract-derived products from the
# corrected 2023 step-4 tract coverage:
#   (1) provider-density table  : subspecialists per 10,000 women + 60-min access
#   (2) per-state x subspecialty : 60-min population-weighted access (heat-map tbl)
#   (3) exclusive-access table   : women reachable by exactly one / by N disciplines
#   (4) ecological logistic reg  : P(tract reached at 60 min) ~ race + rurality
#
# Canonical input: scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet
#   (the corrected step-4 coverage used to rebuild the manuscript catalog).
# Grain: one row per (fips_tract, range, subspecialty, category).
#   count/total/percent = covered / denom / % of that tract-category population.
#   range in seconds: 1800/3600/7200/10800 = 30/60/120/180 min.
# All access is POPULATION-WEIGHTED: sum(total*percent)/sum(total).
# "reached" (binary, for exclusive-access + logistic) = tract percent >= 50
#   (majority of the tract's women within 60 min of a subspecialist in THAT
#   discipline); documented threshold, applied per discipline.
# NO pooling across disciplines anywhere (subspecialists serve distinct
# populations; CLAUDE.md #16). Outputs -> manuscript/stats/.
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(tidyr); library(data.table)
}))
BAND <- 3600L
PARQ <- "scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet"
OUT  <- "manuscript/stats"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
stopifnot(file.exists(PARQ))

# canonical discipline label -> abbrev (matches manuscript)
ABBR <- c(
  "Maternal-Fetal Medicine" = "MFM",
  "Gynecologic Oncology" = "GO",
  "Reproductive Endocrinology & Infertility" = "REI",
  "Female Pelvic Medicine & Reconstructive Surgery" = "URPS",
  "Minimally Invasive Gynecologic Surgery" = "MIGS",
  "Complex Family Planning" = "CFP",
  "Pediatric & Adolescent Gynecology" = "PAG")

ds <- open_dataset(PARQ)

# --- 60-min coverage per (tract, subspecialty) + tract female pop + rurality ----
cov <- as.data.table(ds %>%
  filter(range == BAND, category == "total_female") %>%
  select(fips_tract, subspecialty, percent, total, ruca_code) %>%
  collect())
setnames(cov, "total", "fem")
cov[, reached := as.integer(!is.na(percent) & percent >= 50)]
cov[, abbrev := ABBR[subspecialty]]

# --- tract race/ethnicity composition (range-invariant; take band 3600, any subspec)
race <- as.data.table(ds %>%
  filter(range == BAND, subspecialty == "Gynecologic Oncology") %>%
  select(fips_tract, category, total) %>% collect())
racew <- dcast(race, fips_tract ~ category, value.var = "total", fun.aggregate = function(x) x[1])
setnames(racew, gsub("^total_female_?", "", names(racew)))
setnames(racew, "V1", "fem", skip_absent = TRUE)  # if bare total_female -> ""
if ("" %in% names(racew)) setnames(racew, "", "fem")

# ============================================================================
# (1) PROVIDER-DENSITY TABLE
# ============================================================================
cat_counts <- local({
  c <- readRDS(local({
    p <- Sys.getenv("STATISTICS_CATALOG_PATH", "")
    if (nzchar(p) && file.exists(p)) p
    else if (file.exists("manuscript/data/statistics_catalog.rds")) "manuscript/data/statistics_catalog.rds"
    else "scratchpad/manuscript_stage/statistics_catalog.rds"
  }))
  cf <- c$cohort_flow
  data.table(
    subspecialty = names(ABBR),
    abbrev = unname(ABBR),
    n_subspecialists = c(cf$n_mfm, cf$n_gyn_onc, cf$n_rei, cf$n_urogyn,
                         cf$n_migs, cf$n_cfp, cf$n_pag))
})
fem_total <- cov[subspecialty == "Gynecologic Oncology", sum(fem, na.rm = TRUE)]  # unique tracts
acc60 <- cov[, .(access60 = 100 * sum(fem * percent / 100, na.rm = TRUE) /
                             sum(fem, na.rm = TRUE)), by = .(subspecialty)]
density <- merge(cat_counts, acc60, by = "subspecialty")
density[, density_per_10k := n_subspecialists / (fem_total / 1e4)]
density <- density[order(-access60)]
fwrite(density[, .(subspecialty, abbrev, n_subspecialists,
                   density_per_10k = round(density_per_10k, 3),
                   access60_pct = round(access60, 1))],
       file.path(OUT, "table2_provider_density.csv"))
cat(sprintf("[1] provider density | female denom = %.1fM\n", fem_total / 1e6))
print(density[, .(abbrev, n_subspecialists, density_per_10k = round(density_per_10k,3),
                  access60 = round(access60,1))], row.names = FALSE)

# ============================================================================
# (2) PER-STATE x SUBSPECIALTY 60-min ACCESS (heat-map table)
# ============================================================================
data(fips_codes, package = "tigris", envir = environment())  # may not exist; fallback below
cov[, state_fips := substr(fips_tract, 1, 2)]
st <- tryCatch({
  fc <- unique(as.data.table(tigris::fips_codes)[, .(state_fips = state_code, st = state)])
  fc[!duplicated(state_fips)]
}, error = function(e) NULL)
per_state <- cov[, .(access60 = 100 * sum(fem * percent / 100, na.rm = TRUE) /
                                 sum(fem, na.rm = TRUE),
                     fem = sum(fem, na.rm = TRUE)),
                 by = .(state_fips, abbrev)]
wide <- dcast(per_state, state_fips ~ abbrev, value.var = "access60")
if (!is.null(st)) wide <- merge(st, wide, by = "state_fips", all.y = TRUE)
ord <- c("MFM","GO","REI","URPS","MIGS","CFP","PAG")
setcolorder(wide, c(setdiff(names(wide), ord), intersect(ord, names(wide))))
num <- intersect(ord, names(wide)); wide[, (num) := lapply(.SD, round, 1), .SDcols = num]
fwrite(wide, file.path(OUT, "tableS_per_state_access60.csv"))
cat(sprintf("\n[2] per-state x subspecialty 60-min access | %d states/DC\n", nrow(wide)))

# ============================================================================
# (3) EXCLUSIVE-ACCESS (per discipline; women reachable by exactly one / by N)
# ============================================================================
w <- dcast(cov, fips_tract + fem ~ abbrev, value.var = "reached", fill = 0L)
discs <- intersect(ord, names(w))
w[, n_disc := rowSums(.SD), .SDcols = discs]
# distribution: women by number of disciplines reaching their tract
dist_n <- w[, .(women = sum(fem, na.rm = TRUE)), by = n_disc][order(n_disc)]
dist_n[, pct := 100 * women / sum(women)]
fwrite(dist_n, file.path(OUT, "tableS_access_breadth.csv"))
# per-discipline: total reached, exclusive (only this discipline), % exclusive
excl <- rbindlist(lapply(discs, function(d) {
  reached_pop <- w[get(d) == 1L, sum(fem, na.rm = TRUE)]
  excl_pop    <- w[get(d) == 1L & n_disc == 1L, sum(fem, na.rm = TRUE)]
  data.table(abbrev = d, reached_millions = reached_pop / 1e6,
             exclusive_millions = excl_pop / 1e6,
             pct_of_reached_exclusive = 100 * excl_pop / reached_pop)
}))
excl <- excl[order(-reached_millions)]
fwrite(excl[, .(abbrev, reached_millions = round(reached_millions,2),
                exclusive_millions = round(exclusive_millions,3),
                pct_of_reached_exclusive = round(pct_of_reached_exclusive,1))],
       file.path(OUT, "table_exclusive_access.csv"))
cat("\n[3] exclusive access (60-min, reached = tract >=50%)\n")
print(excl[, .(abbrev, reached_M = round(reached_millions,2),
               excl_M = round(exclusive_millions,3),
               pct_excl = round(pct_of_reached_exclusive,1))], row.names = FALSE)
cat("  breadth (women by # disciplines reaching tract):\n")
print(dist_n[, .(n_disc, women_M = round(women/1e6,1), pct = round(pct,1))], row.names = FALSE)

# ============================================================================
# (4) ECOLOGICAL PER-DISCIPLINE LOGISTIC REGRESSION
#     outcome: tract reached (>=50% within 60 min) by discipline d
#     predictors: race/ethnicity shares (per +10 pp, white_nh reference/omitted)
#                 + rural indicator (RUCA code >= 4). One model PER discipline.
#
#     Comparator: Diaz et al. 2019 (J Gastrointest Surg 23:1652-60, [@Diaz2019])
#     ran the analogous logistic model at the PERSON level -- P(living within a
#     straight-line 30-mi major-surgical-hospital service area) ~ demographics --
#     and found minority race was associated with living WITHIN service areas
#     (Hispanic multivariable OR 13.2, African-American 3.8), reflecting urban
#     concentration of both hospitals and minority populations. Our model is at
#     the TRACT level with a DRIVE-TIME (not Euclidean) outcome and per-discipline
#     subspecialist networks, so a negative race coefficient here (high-minority-
#     share tracts less likely reached) is not contradictory: it isolates the
#     within-region access gap that a national person-level service-area model
#     cannot resolve. Keep the two framings distinct when citing.
# ============================================================================
rc <- copy(racew)
den <- rc$fem; den[den <= 0] <- NA_real_
for (g in c("black","hispanic","asian","aian","other","two_or_more")) {
  if (g %in% names(rc)) rc[[paste0("p_", g)]] <- 100 * rc[[g]] / den / 10  # per 10 pp
}
rur <- unique(cov[, .(fips_tract, ruca_code)])
rc <- merge(rc, rur, by = "fips_tract", all.x = TRUE)
rc[, rural := as.integer(!is.na(ruca_code) & ruca_code >= 4)]
preds <- intersect(c("p_black","p_hispanic","p_asian","p_aian","p_other","p_two_or_more","rural"),
                   names(rc))

fit_disc <- function(d) {
  y <- cov[abbrev == d, .(fips_tract, reached)]
  dd <- merge(y, rc[, c("fips_tract", preds), with = FALSE], by = "fips_tract")
  dd <- dd[complete.cases(dd)]
  # univariable
  uni <- rbindlist(lapply(preds, function(p) {
    m <- glm(reached ~ get(p), data = dd, family = binomial())
    ci <- suppressMessages(confint.default(m))
    data.table(term = p, uni_or = exp(coef(m)[2]),
               uni_lo = exp(ci[2,1]), uni_hi = exp(ci[2,2]))
  }))
  # multivariable
  f <- as.formula(paste("reached ~", paste(preds, collapse = " + ")))
  m <- glm(f, data = dd, family = binomial())
  ci <- suppressMessages(confint.default(m))
  mult <- data.table(term = preds, multi_or = exp(coef(m)[preds]),
                     multi_lo = exp(ci[preds,1]), multi_hi = exp(ci[preds,2]))
  out <- merge(uni, mult, by = "term")
  out[, `:=`(subspecialty = d, n_tracts = nrow(dd),
             pct_reached = round(100*mean(dd$reached),1))]
  out
}
logit <- rbindlist(lapply(discs, fit_disc))
setcolorder(logit, c("subspecialty","n_tracts","pct_reached","term",
                     "uni_or","uni_lo","uni_hi","multi_or","multi_lo","multi_hi"))
numcols <- c("uni_or","uni_lo","uni_hi","multi_or","multi_lo","multi_hi")
logit[, (numcols) := lapply(.SD, round, 3), .SDcols = numcols]
fwrite(logit, file.path(OUT, "table_poor_access_logistic.csv"))
cat("\n[4] ecological per-discipline logistic (OR per +10 pp share; rural vs urban)\n")
print(logit[subspecialty == "GO", .(term, uni_or, multi_or, multi_lo, multi_hi)], row.names = FALSE)
cat("  (full 7-discipline table -> table_poor_access_logistic.csv)\n")
cat("\nDONE. Wrote 6 CSVs to manuscript/stats/\n")
