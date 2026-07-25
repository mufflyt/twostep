#!/usr/bin/env Rscript
# Compile the cross-subspecialty inferential summary table: 2020 MC 95% CIs
# (from <SUB>_2020_inferential_MC_CI.csv) + 2013-2022 OLS trend (from LONG.csv).
suppressWarnings(suppressMessages(library(dplyr)))
ROOT <- if (requireNamespace("here", quietly=TRUE)) here::here() else normalizePath(".")
FIG <- file.path(ROOT,"artifacts","2sfca","figures")
SUBS <- c("GO","MFM","REI","FPMRS","MIGS","PAG","CFP")
long <- readr::read_csv(file.path(FIG,"allsubspec_allyears_stratified_LONG.csv"), show_col_types=FALSE)

ci <- function(csv,m,dg=3){ d<-read.csv(csv); r<-d[d$metric==m,]
  sprintf(paste0("%.",dg,"f (%.",dg,"f-%.",dg,"f)"), r$point, r$lo, r$hi) }
trend <- function(sub, stratum, ycol="pct_zero"){
  df <- long |> filter(subspec==sub, stratum==!!stratum, year<=2022)
  if (nrow(df) < 3) return(c(slope=NA, p=NA))
  m <- lm(reformulate("year", ycol), df); s <- summary(m)$coefficients["year",]
  c(slope=unname(s[["Estimate"]]), p=unname(s[["Pr(>|t|)"]])) }

rows <- lapply(SUBS, function(s){
  f <- file.path(FIG, sprintf("%s_2020_inferential_MC_CI.csv", s))
  ta <- trend(s,"Am. Indian/Alaska Native"); tr <- trend(s,"Rural")
  tibble(
    subspecialty = s,
    national_mean = ci(f,"nat_mean"),
    metro_rural_ratio = ci(f,"metro_rural_ratio",2),
    rural_pct_zero = ci(f,"rural_zero",2),
    aian_mean = ci(f,"mean_aian"),
    aian_pct_zero = ci(f,"zero_aian",2),
    aian_minus_white_zero = ci(f,"aianzero_minus_whitezero",2),
    aian_zero_trend = sprintf("%+.3f/yr (P=%.3f)", ta[["slope"]], ta[["p"]]),
    rural_zero_trend = sprintf("%+.3f/yr (P=%.3f)", tr[["slope"]], tr[["p"]])) })
tab <- bind_rows(rows)
readr::write_csv(tab, file.path(FIG,"allsubspec_2020_inferential_TABLE.csv"))
cat("wrote allsubspec_2020_inferential_TABLE.csv\n\n")
# pretty print
print(as.data.frame(tab), right=FALSE, row.names=FALSE)
