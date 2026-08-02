#!/usr/bin/env Rscript
# PORTED into twostep (2026-08-02) from isochrones/scripts/manuscript_trend_hac.R
# to close the reproducibility gap: this is the IN-REPO producer for the frozen
# artifact artifacts/2sfca/figures/trend_hac.rds (HAC temporal trends). Verified to
# reproduce that artifact's values exactly. Requires sandwich + lmtest (pinned).
# ==============================================================================
# manuscript_trend_hac.R
# ------------------------------------------------------------------------------
# Autocorrelation-robust temporal trends for the E2SFCA disparity series
# (addresses the overlapping-ACS / serially-correlated-cohort concern). For each
# annual series (2013-2022) we report the OLS slope with both the naive OLS P
# value and a Newey-West heteroskedasticity- and autocorrelation-consistent (HAC)
# P value. The HAC lag is PRESPECIFIED at 4 because ACS 5-year estimates for years
# t and t+k share window years whenever |k| < 5, so autocorrelation is expected up
# to lag 4; with only 10 annual observations this is a known limitation and the
# HAC intervals are wide. Trends are interpreted descriptively.
# ==============================================================================
suppressWarnings(suppressMessages({
  library(dplyr); library(sandwich); library(lmtest)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
FIG  <- file.path(ROOT, "artifacts", "2sfca", "figures")
LONG <- readr::read_csv(file.path(FIG, "allsubspec_allyears_stratified_LONG.csv"),
                        show_col_types = FALSE)
HAC_LAG <- 4L

#' OLS slope of `value` on year over 2013-2022 with OLS and Newey-West HAC P.
#' @return named numeric c(slope, p_ols, p_hac).
trend_hac <- function(year, value, hac_lag = HAC_LAG) {
  d <- data.frame(year = as.numeric(year), value = as.numeric(value))
  d <- d[stats::complete.cases(d) & d$year <= 2022, ]
  if (nrow(d) < 4) return(c(slope = NA, p_ols = NA, p_hac = NA))
  fit <- stats::lm(value ~ year, d)
  p_ols <- summary(fit)$coefficients["year", "Pr(>|t|)"]
  vc <- sandwich::NeweyWest(fit, lag = hac_lag, prewhite = FALSE, adjust = TRUE)
  p_hac <- lmtest::coeftest(fit, vcov. = vc)["year", "Pr(>|t|)"]
  c(slope = unname(coef(fit)["year"]), p_ols = unname(p_ols),
    p_hac = unname(p_hac))
}

specs <- c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
# per-subspecialty zero-access trends: Rural and AIAN
rows <- list()
for (s in specs) for (grp in c("Rural","Am. Indian/Alaska Native")) {
  ser <- LONG |> filter(subspec == s, stratum == grp) |> arrange(year)
  tr <- trend_hac(ser$year, ser$pct_zero)
  rows[[paste(s, grp)]] <- tibble(subspecialty = s,
    group = ifelse(grp == "Rural", "Rural", "AIAN"),
    slope_pp_yr = unname(tr["slope"]), p_ols = unname(tr["p_ols"]),
    p_hac = unname(tr["p_hac"]))
}
trend_tbl <- bind_rows(rows)

# GO metropolitan-to-rural accessibility ratio trend
go_ratio <- LONG |> filter(subspec == "GO", stratum %in% c("Metropolitan","Rural")) |>
  select(year, stratum, mean_access) |>
  tidyr::pivot_wider(names_from = stratum, values_from = mean_access) |>
  mutate(ratio = Metropolitan / Rural)
go_ratio_tr <- trend_hac(go_ratio$year, go_ratio$ratio)

readr::write_csv(trend_tbl, file.path(FIG, "trend_hac_table.csv"))
saveRDS(list(trend_tbl = trend_tbl, go_ratio = go_ratio_tr, hac_lag = HAC_LAG),
        file.path(FIG, "trend_hac.rds"))

fmt_p <- function(p) if (is.na(p)) "NA" else if (p < 0.001) "<0.001" else
  sprintf("%.3f", p)
cat(sprintf("Newey-West HAC lag = %d; 2013-2022; n = 10 annual estimates\n\n", HAC_LAG))
cat("=== GO metro:rural ratio trend ===\n")
cat(sprintf("  slope=%+.4f/yr  P(OLS)=%s  P(HAC)=%s\n",
    go_ratio_tr["slope"], fmt_p(go_ratio_tr["p_ols"]), fmt_p(go_ratio_tr["p_hac"])))
cat("\n=== per-subspecialty %zero trends (slope pp/yr; OLS P; HAC P) ===\n")
print(as.data.frame(trend_tbl |> mutate(
  slope = sprintf("%+.3f", slope_pp_yr),
  `P(OLS)` = vapply(p_ols, fmt_p, ""), `P(HAC)` = vapply(p_hac, fmt_p, "")) |>
  select(subspecialty, group, slope, `P(OLS)`, `P(HAC)`)), row.names = FALSE)
cat("\nwrote trend_hac_table.csv, trend_hac.rds\n")
