#!/usr/bin/env Rscript
# ==============================================================================
# inferential_stats_access.R
# ------------------------------------------------------------------------------
# Inferential statistics for the E2SFCA accessibility disparities (default GO).
#
# Uncertainty model: the tract-level access values and the physician catchments
# are DETERMINISTIC (a census of physicians + fixed isochrones), so the only
# sampling error is in the ACS population weights. We therefore quantify
# uncertainty by MONTE-CARLO propagation of the ACS 5-year margins of error (MOE)
# into every population-weighted estimate. This correctly widens intervals for
# small groups (AIAN, NHPI) with large tract-level MOEs, and avoids the fallacy
# of treating ~millions of women as independent Bernoulli trials.
#
#   - 2020 point estimates + 95% MC CIs for: national mean access; metro/rural
#     mean, difference, ratio, and %zero; each race group's mean and %zero;
#     and key between-group differences (metro-rural, AIAN vs Asian/White).
#   - Temporal trend (2013-2022, excluding the 2023 data-maturity year): OLS of
#     the annual point estimates on year -> slope/yr, 95% CI, P, for GO rural and
#     AIAN %zero and the metro:rural ratio (annual estimates from LONG.csv).
# Usage: Rscript scripts/inferential_stats_access.R --access-dir DIR [--subspec GO] [--B 2000]
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
A <- commandArgs(trailingOnly = TRUE); getA<-function(f,d=NULL){i<-which(A==f);if(length(i)&&i<length(A))A[i+1] else d}
ACCDIR <- getA("--access-dir", Sys.getenv("GO_ACCESS_DIR",""))
SUB    <- getA("--subspec","GO")
B      <- as.integer(getA("--B","2000"))
CACHE  <- getA("--acs-cache", Sys.getenv("STRAT_CACHE", file.path(tempdir(),"acs_race_cache")))
OUT    <- file.path(ROOT,"artifacts","2sfca","figures")
stopifnot(nzchar(ACCDIR), dir.exists(ACCDIR)); dir.create(CACHE,showWarnings=FALSE,recursive=TRUE)
say <- function(...) cat(sprintf("[infer] %s\n", sprintf(...)))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

VARS <- c(total_f="B01001_026", white_nh="B01001H_017", hispanic="B01001I_017",
          black="B01001B_017", aian="B01001C_017", asian="B01001D_017", nhpi="B01001E_017")
# ── ACS 2020 with estimate + MOE (cached separately from the estimate-only cache)
cf <- file.path(CACHE, "acs_den_moe_2020.rds")
if (file.exists(cf)) { acs <- readRDS(cf) } else {
  say("fetching ACS 2020 with MOE (7 vars, CONUS)")
  raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=VARS, state=s, year=2020L, geometry=FALSE)))
  acs <- raw |> transmute(GEOID=as.character(GEOID), variable,
                          est=as.numeric(estimate), moe=as.numeric(moe))
  saveRDS(acs, cf)
}
est <- acs |> select(GEOID,variable,est) |> tidyr::pivot_wider(names_from=variable,values_from=est)
moe <- acs |> select(GEOID,variable,moe) |> tidyr::pivot_wider(names_from=variable,values_from=moe,
                                                               names_prefix="moe_")

# ── join access + rurality ───────────────────────────────────────────────────
af <- file.path(ACCDIR, sprintf("step_4_2sfca_%s_2020.rds", SUB)); stopifnot(file.exists(af))
acc <- readRDS(af) |> transmute(GEOID=as.character(GEOID), access=access_mean_population_per100k)
ruca <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=ifelse(as.integer(ruca_code)%in%1:3,"Metropolitan","Rural"))
d <- acc |> inner_join(ruca,by="GEOID") |> inner_join(est,by="GEOID") |> inner_join(moe,by="GEOID")
d$access[is.na(d$access)] <- 0
say("%s 2020 tracts joined: %d", SUB, nrow(d))

WV <- names(VARS)                                  # total_f, white_nh, ...
se <- lapply(WV, function(v){ s <- d[[paste0("moe_",v)]]/1.645; s[is.na(s)] <- 0; s })
names(se) <- WV
pt <- setNames(lapply(WV, function(v){ x<-d[[v]]; x[is.na(x)]<-0; x }), WV)

# Weighted-mean / zero-share helpers come from the tested SSOT module (guarded by
# tests/testthat/test-accessibility-stratification.R, incl. the MC-unbiasedness
# regression test). They sum over ALL elements — see the module for why the
# w>0-filter is a bug for the Monte-Carlo draws.
source(file.path(ROOT, "R", "accessibility_stratification.R"))
wmean <- weighted_mean_all
zsh   <- zero_access_share
is_metro <- d$rurality=="Metropolitan"; is_rural <- !is_metro
acc_v <- d$access

# point estimates (from actual ACS estimates)
metric_set <- function(wtot, wrace){
  c(nat_mean = wmean(acc_v, wtot$total_f),
    metro_mean = wmean(acc_v[is_metro], wtot$total_f[is_metro]),
    rural_mean = wmean(acc_v[is_rural], wtot$total_f[is_rural]),
    metro_zero = zsh(acc_v[is_metro], wtot$total_f[is_metro]),
    rural_zero = zsh(acc_v[is_rural], wtot$total_f[is_rural]),
    setNames(sapply(c("white_nh","black","hispanic","asian","aian","nhpi"),
      function(g) wmean(acc_v, wrace[[g]])), paste0("mean_",c("white_nh","black","hispanic","asian","aian","nhpi"))),
    setNames(sapply(c("white_nh","black","hispanic","asian","aian","nhpi"),
      function(g) zsh(acc_v, wrace[[g]])), paste0("zero_",c("white_nh","black","hispanic","asian","aian","nhpi"))))
}
derive <- function(m){ c(m,
  metro_minus_rural = unname(m["metro_mean"]-m["rural_mean"]),
  metro_rural_ratio = unname(m["metro_mean"]/m["rural_mean"]),
  aian_minus_asian  = unname(m["mean_aian"]-m["mean_asian"]),
  aian_minus_white  = unname(m["mean_aian"]-m["mean_white_nh"]),
  aianzero_minus_whitezero = unname(m["zero_aian"]-m["zero_white_nh"])) }
POINT <- derive(metric_set(pt, pt))

# Monte-Carlo over ACS MOE
set.seed(20260713L)
# Draw tract weights ~ Normal(estimate, MOE/1.645). We do NOT clamp negatives:
# the draws enter only aggregate sums (weighted means / shares), where
# E[sum] = sum(estimate) is unbiased; clamping would inject spurious positive
# weight into the many zero-estimate tracts and bias sparse groups (AIAN/NHPI)
# upward (point estimate would fall outside the interval). This matches ACS
# aggregate-MOE semantics (variance of a sum = sum of tract variances).
draw <- function(v){ rnorm(nrow(d), pt[[v]], se[[v]]) }
MC <- matrix(NA_real_, B, length(POINT), dimnames=list(NULL, names(POINT)))
for (b in seq_len(B)){
  wt <- setNames(lapply(WV, draw), WV)
  MC[b,] <- derive(metric_set(wt, wt))
}
ci <- function(nm){ q<-quantile(MC[,nm], c(.025,.975), na.rm=TRUE); sprintf("%.3f (95%% CI %.3f-%.3f)", POINT[[nm]], q[1], q[2]) }
ci2<- function(nm){ q<-quantile(MC[,nm], c(.025,.975), na.rm=TRUE); sprintf("%.2f (95%% CI %.2f-%.2f)", POINT[[nm]], q[1], q[2]) }

say("========== %s 2020 — point estimate (95%% MC CI from ACS MOE, B=%d) ==========", SUB, B)
cat(sprintf("National mean access      : %s\n", ci("nat_mean")))
cat(sprintf("Metropolitan mean         : %s\n", ci("metro_mean")))
cat(sprintf("Rural mean                : %s\n", ci("rural_mean")))
cat(sprintf("Metro - Rural (diff)      : %s   -> CI excludes 0: %s\n", ci("metro_minus_rural"),
    all(quantile(MC[,"metro_minus_rural"],c(.025,.975))>0)))
cat(sprintf("Metro : Rural (ratio)     : %s\n", ci2("metro_rural_ratio")))
cat(sprintf("Metro %%zero               : %s\n", ci("metro_zero")))
cat(sprintf("Rural %%zero               : %s\n", ci("rural_zero")))
cat("--- race/ethnicity mean access (95% CI) ---\n")
for (g in c("asian","black","hispanic","nhpi","white_nh","aian"))
  cat(sprintf("  %-9s mean: %s | %%zero: %s\n", g, ci(paste0("mean_",g)), ci(paste0("zero_",g))))
cat(sprintf("AIAN - Asian mean (diff)  : %s  -> CI excludes 0: %s\n", ci("aian_minus_asian"),
    all(quantile(MC[,"aian_minus_asian"],c(.025,.975))<0)))
cat(sprintf("AIAN - White mean (diff)  : %s  -> CI excludes 0: %s\n", ci("aian_minus_white"),
    all(quantile(MC[,"aian_minus_white"],c(.025,.975))<0)))
cat(sprintf("AIAN - White %%zero (diff) : %s  -> CI excludes 0: %s\n", ci("aianzero_minus_whitezero"),
    all(quantile(MC[,"aianzero_minus_whitezero"],c(.025,.975))>0)))

# ── temporal trend (2013-2022; exclude 2023 data-maturity year) ──────────────
long <- readr::read_csv(file.path(OUT,"allsubspec_allyears_stratified_LONG.csv"), show_col_types=FALSE)
trend <- function(df, ycol){ df <- df |> filter(year<=2022); m<-lm(reformulate("year", ycol), df)
  s<-summary(m)$coefficients["year",]; cf<-confint(m)["year",]
  sprintf("slope=%+.4f/yr (95%% CI %+.4f to %+.4f), P=%.3f", s[["Estimate"]], cf[1], cf[2], s[["Pr(>|t|)"]]) }
say("========== %s temporal trend, 2013-2022 (OLS on annual estimates) ==========", SUB)
gl <- long |> filter(subspec==SUB)
cat(sprintf("Rural %%zero          : %s\n", trend(gl|>filter(stratum=="Rural"),"pct_zero")))
cat(sprintf("Metropolitan %%zero   : %s\n", trend(gl|>filter(stratum=="Metropolitan"),"pct_zero")))
cat(sprintf("AIAN %%zero           : %s\n", trend(gl|>filter(stratum=="Am. Indian/Alaska Native"),"pct_zero")))
cat(sprintf("Rural mean access    : %s\n", trend(gl|>filter(stratum=="Rural"),"mean_access")))
cat(sprintf("AIAN mean access     : %s\n", trend(gl|>filter(stratum=="Am. Indian/Alaska Native"),"mean_access")))
ratio_df <- gl |> filter(stratum %in% c("Metropolitan","Rural")) |>
  tidyr::pivot_wider(id_cols=year, names_from=stratum, values_from=mean_access) |>
  mutate(ratio=Metropolitan/Rural)
cat(sprintf("Metro:Rural ratio    : %s\n", trend(ratio_df,"ratio")))

# save MC CI table
ci_tbl <- tibble(metric=names(POINT), point=POINT,
                 lo=apply(MC,2,quantile,.025,na.rm=TRUE), hi=apply(MC,2,quantile,.975,na.rm=TRUE))
readr::write_csv(ci_tbl, file.path(OUT, sprintf("%s_2020_inferential_MC_CI.csv", SUB)))
say("wrote %s_2020_inferential_MC_CI.csv", SUB)
