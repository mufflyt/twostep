#!/usr/bin/env Rscript
# ==============================================================================
# stratify_allyears_access.R
# ------------------------------------------------------------------------------
# Rurality- and race/ethnicity-stratified E2SFCA accessibility over 2013-2023 for
# ANY / ALL of the 7 OB/GYN subspecialties. Generalizes stratify_go_allyears; the
# ACS female denominators are per-YEAR (not per-subspecialty) so they are fetched
# ONCE and reused across every subspecialty.
#
# Tract-vintage aware: 2013-2019 -> 2010 tracts (RUCA 2010, ACS<=2019);
#                      2020-2023 -> 2020 tracts (RUCA 2020, ACS>=2020, 2023->2022).
# Access weight: rurality by total female; each race group by that group's female.
# "% zero" = share of the group's women in tracts with NO reachable subspecialist
#            (access == 0) == Desjardins Q1.
#
# Usage:
#   Rscript scripts/stratify_allyears_access.R --access-dir DIR [--subspec all]
#   Rscript scripts/stratify_allyears_access.R --access-dir DIR --subspec GO,MFM
#   flags: --acs-cache DIR  --out DIR  --no-figures
# Outputs (in --out, default artifacts/2sfca/figures):
#   <SUB>_allyears_access_by_rurality.csv , <SUB>_allyears_access_by_race.csv
#   fig_<SUB>_allyears_access_stratified.png              (per subspecialty)
#   allsubspec_allyears_stratified_LONG.csv               (tidy, all subspecs)
#   fig_allsubspec_equity_summary.png                     (cross-subspecialty)
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(ggplot2); library(patchwork) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
# Weighted-mean / zero-share estimators, ACS-year & tract-vintage maps, and the
# ACS female-variable codes come from the tested SSOT module (guarded by
# tests/testthat/test-accessibility-stratification.R, incl. the Monte-Carlo
# clamp/filter regression test and the B01001[*]_017-not-_026 footgun guard).
source(file.path(ROOT, "R", "accessibility_stratification.R"))
A <- commandArgs(trailingOnly = TRUE)
getA <- function(f, d=NULL){ i<-which(A==f); if(length(i)&&i<length(A)) A[i+1] else d }
hasA <- function(f) f %in% A
ACCDIR   <- getA("--access-dir", Sys.getenv("GO_ACCESS_DIR", ""))
SUBSPEC  <- getA("--subspec", "all")
CACHE    <- getA("--acs-cache", Sys.getenv("STRAT_CACHE", file.path(tempdir(),"acs_race_cache")))
OUT      <- getA("--out", file.path(ROOT,"artifacts","2sfca","figures"))
FIGURES  <- !hasA("--no-figures")
stopifnot(nzchar(ACCDIR), dir.exists(ACCDIR))
dir.create(OUT, showWarnings=FALSE, recursive=TRUE); dir.create(CACHE, showWarnings=FALSE, recursive=TRUE)
say <- function(...) cat(sprintf("[strat] %s\n", sprintf(...)))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

ALL_SUB <- c("CFP","FPMRS","GO","MFM","MIGS","PAG","REI")
SUBS <- if (identical(toupper(SUBSPEC),"ALL")) ALL_SUB else strsplit(SUBSPEC,",")[[1]]
stopifnot(all(SUBS %in% ALL_SUB))
FULL <- c(GO="Gynecologic Oncology", MFM="Maternal-Fetal Medicine", REI="Reproductive Endocrinology",
  FPMRS="Urogynecology (FPMRS)", MIGS="Minimally Invasive Gyn Surgery",
  PAG="Pediatric & Adolescent Gyn", CFP="Complex Family Planning")
YEARS <- 2013:2023
# acs_year_of() is used directly from the SSOT module; alias its tract-vintage map
# to the local name this script has always used.
vintage_of <- tract_vintage_of

ruca_2020 <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"), colClasses="character")
ruca_2010 <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping_2010.csv"), colClasses="character")
# rurality_from_ruca() (SSOT module) returns Metropolitan for RUCA 1-3, Rural for
# 4-10, and NA for uncoded tracts — chiefly RUCA 99, the ~368 zero-population
# "not coded" tracts in the 2020 vintage (parks, airports, water). We drop those
# NA rows so they never form a phantom rurality group; they carry zero female
# population, so excluding them leaves every weighted statistic unchanged.
ruca_of <- function(y){ r <- if (vintage_of(y)==2020L) ruca_2020 else ruca_2010
  transmute(r, GEOID=tract_geoid, rurality=rurality_from_ruca(ruca_code)) |> filter(!is.na(rurality)) }

# Female-population codes from the SSOT module: total (B01001_026) + the six
# race-iterated female totals (B01001[*]_017). Keeping these in one tested place
# is the guard against the _026-on-a-race-table footgun.
VARS <- c(total_f = unname(TOTAL_FEMALE_VAR), RACE_FEMALE_VARS)
fetch_den <- function(ay){ cf<-file.path(CACHE,sprintf("acs_den_%d.rds",ay))
  if (file.exists(cf)) return(readRDS(cf))
  say("fetching ACS %d denominators (not cached)", ay)
  raw<-purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=VARS, state=s, year=ay, geometry=FALSE)))
  den<-raw|>transmute(GEOID=as.character(GEOID),variable,estimate=as.numeric(estimate))|>
    tidyr::pivot_wider(names_from=variable,values_from=estimate)
  saveRDS(den,cf); den }
DEN <- setNames(lapply(unique(vapply(YEARS,acs_year_of,0L)), fetch_den),
                as.character(unique(vapply(YEARS,acs_year_of,0L))))

# Wire the point-estimate weighted mean / zero-share to the tested module. The
# module sums over ALL elements; we first zero out any NA value/weight so a
# missing tract contributes nothing to numerator or denominator — identical to
# the historical `!is.na & w>0` filter for the non-negative ACS count weights
# used here. zero_access_share() returns a PERCENT, so /100 to keep the callers'
# `100 * zshare(...)` unchanged.
wmean  <- function(x, w){ bad <- is.na(x) | is.na(w); x[bad] <- 0; w[bad] <- 0; weighted_mean_all(x, w) }
zshare <- function(a, w){ bad <- is.na(a) | is.na(w); a[bad] <- 0; w[bad] <- 0; zero_access_share(a, w) / 100 }
GRP <- tibble::tribble(~key,~label,
  "white_nh","White, non-Hispanic","black","Black alone","hispanic","Hispanic (any race)",
  "asian","Asian alone","aian","Am. Indian/Alaska Native","nhpi","Nat. Hawaiian/Pac. Isl.")

stratify_one <- function(sub){
  rl<-list(); cl<-list()
  for (y in YEARS){
    af<-file.path(ACCDIR,sprintf("step_4_2sfca_%s_%d.rds",sub,y)); stopifnot(file.exists(af))
    acc<-readRDS(af)|>transmute(GEOID=as.character(GEOID),access=access_mean_population_per100k)
    d<-acc|>inner_join(ruca_of(y),by="GEOID")|>inner_join(DEN[[as.character(acs_year_of(y))]],by="GEOID")
    d$access[is.na(d$access)]<-0
    rl[[as.character(y)]]<-d|>group_by(rurality)|>summarise(year=y,
      mean_access=wmean(access,total_f), pct_zero=100*zshare(access,total_f),
      women=sum(total_f,na.rm=TRUE), .groups="drop")
    cl[[as.character(y)]]<-purrr::map_dfr(seq_len(nrow(GRP)),function(i){w<-d[[GRP$key[i]]]
      tibble(year=y,group=GRP$label[i],mean_access=wmean(d$access,w),
             pct_zero=100*zshare(d$access,w),women=sum(w,na.rm=TRUE))})
  }
  list(rur=bind_rows(rl), race=bind_rows(cl))
}

# ── per-subspecialty 3-panel trend figure (reusable) ─────────────────────────
make_fig <- function(sub, rur, race){
  th <- theme_minimal(base_size=12)+theme(plot.title=element_text(size=rel(1.1),face="bold"),
        plot.title.position="plot", panel.grid.minor=element_blank())
  labr<-rur|>filter(year==2023)
  pA<-ggplot(rur,aes(year,mean_access,colour=rurality))+geom_line(linewidth=1)+geom_point(size=1.5)+
    geom_text(data=labr,aes(label=rurality),hjust=-0.1,size=9,size.unit="pt",fontface="bold")+
    scale_colour_manual(values=c(Metropolitan="#2171b5",Rural="#cb4b16"),guide="none")+
    scale_x_continuous(breaks=2013:2023,limits=c(2013,2024.8),guide=guide_axis(check.overlap=TRUE))+
    labs(title="A. Mean access by rurality",x=NULL,y="Access (per 100k women)")+th
  ord<-race$group[race$year==2020][order(race$mean_access[race$year==2020])]
  pal6<-setNames(c("#6a51a3","#238b45","#e6550d","#2171b5","#d94801","#31a354"),ord)
  labc<-race|>filter(year==2023)
  pB<-ggplot(race,aes(year,mean_access,colour=group))+geom_line(linewidth=0.9)+geom_point(size=1.2)+
    geom_text(data=labc,aes(label=group),hjust=-0.05,size=8,size.unit="pt")+
    scale_colour_manual(values=pal6,guide="none")+
    scale_x_continuous(breaks=2013:2023,limits=c(2013,2026.8),guide=guide_axis(check.overlap=TRUE))+
    labs(title="B. Mean access by race / ethnicity",x=NULL,y="Access (per 100k women)")+th
  zdf<-bind_rows(
    rur|>filter(rurality=="Rural")|>transmute(year,who="Rural (all races)",pct_zero),
    rur|>filter(rurality=="Metropolitan")|>transmute(year,who="Metropolitan",pct_zero),
    race|>filter(group=="Am. Indian/Alaska Native")|>transmute(year,who="Am. Indian/Alaska Native",pct_zero))
  labz<-zdf|>filter(year==2023)
  pC<-ggplot(zdf,aes(year,pct_zero,colour=who))+geom_line(linewidth=1)+geom_point(size=1.5)+
    geom_text(data=labz,aes(label=who),hjust=-0.05,size=8,size.unit="pt",fontface="bold")+
    scale_colour_manual(values=c("Rural (all races)"="#cb4b16","Metropolitan"="#2171b5",
      "Am. Indian/Alaska Native"="#6a51a3"),guide="none")+
    scale_x_continuous(breaks=2013:2023,limits=c(2013,2027.2),guide=guide_axis(check.overlap=TRUE))+
    labs(title="C. Share of women with NO reachable subspecialist",
         subtitle="Does the gap improve over time? (== Desjardins Q1)",x=NULL,y="% women, access = 0")+th
  (pA|pB)/pC + plot_annotation(
    title=sprintf("%s accessibility disparities over time, 2013-2023 — E2SFCA (CONUS)", FULL[[sub]]),
    subtitle="Population-weighted travel-time catchment access by rurality and race/ethnicity",
    caption="Production mass-conserving E2SFCA. Rurality = USDA RUCA (vintage-matched). Race = ACS B01001[*]_017 female totals.",
    theme=theme(plot.title=element_text(size=rel(1.25),face="bold"),plot.title.position="plot"))
}

# ── run all requested subspecialties ─────────────────────────────────────────
LONG <- list()
for (sub in SUBS){
  say("=== %s ===", sub)
  r <- stratify_one(sub)
  readr::write_csv(r$rur,  file.path(OUT, sprintf("%s_allyears_access_by_rurality.csv", sub)))
  readr::write_csv(r$race, file.path(OUT, sprintf("%s_allyears_access_by_race.csv", sub)))
  LONG[[sub]] <- bind_rows(
    r$rur  |> transmute(subspec=sub, year, stratum_type="rurality", stratum=rurality, mean_access, pct_zero, women),
    r$race |> transmute(subspec=sub, year, stratum_type="race",     stratum=group,    mean_access, pct_zero, women))
  if (FIGURES){
    fp <- file.path(OUT, sprintf("fig_%s_allyears_access_stratified.png", sub))
    ggsave(fp, make_fig(sub, r$rur, r$race), width=13, height=10, dpi=200, bg="white")
    say("wrote %s", fp)
  }
  say("  %s: rural %%zero %.1f%%->%.1f%%  AIAN %%zero %.1f%%->%.1f%% (2013->2023)",
      sub, r$rur$pct_zero[r$rur$rurality=="Rural"&r$rur$year==2013],
      r$rur$pct_zero[r$rur$rurality=="Rural"&r$rur$year==2023],
      r$race$pct_zero[r$race$group=="Am. Indian/Alaska Native"&r$race$year==2013],
      r$race$pct_zero[r$race$group=="Am. Indian/Alaska Native"&r$race$year==2023])
}
long <- bind_rows(LONG)
readr::write_csv(long, file.path(OUT, "allsubspec_allyears_stratified_LONG.csv"))
say("wrote combined tidy table: allsubspec_allyears_stratified_LONG.csv (%d rows)", nrow(long))

# ── cross-subspecialty equity summary: %zero for Rural and AIAN, all subspecs ─
if (FIGURES && length(SUBS) > 1){
  sord <- long |> filter(stratum=="Rural", year==2020) |> arrange(desc(pct_zero)) |> pull(subspec)
  spal <- setNames(scales::hue_pal()(length(ALL_SUB)), ALL_SUB)
  mk <- function(df, ttl, sub_ttl){
    lab <- df |> group_by(subspec) |> filter(year==max(year)) |> ungroup()
    ggplot(df, aes(year, pct_zero, colour=subspec)) + geom_line(linewidth=0.9)+geom_point(size=1.2)+
      geom_text(data=lab, aes(label=subspec), hjust=-0.1, size=8, size.unit="pt", fontface="bold")+
      scale_colour_manual(values=spal, guide="none")+
      scale_x_continuous(breaks=2013:2023, limits=c(2013,2025), guide=guide_axis(check.overlap=TRUE))+
      labs(title=ttl, subtitle=sub_ttl, x=NULL, y="% women, access = 0")+
      theme_minimal(base_size=12)+theme(plot.title=element_text(size=rel(1.1),face="bold"),
        plot.title.position="plot", panel.grid.minor=element_blank())
  }
  pRur <- mk(long|>filter(stratum=="Rural"),
             "A. Rural women with NO reachable subspecialist", "by subspecialty, 2013-2023")
  pAIAN<- mk(long|>filter(stratum=="Am. Indian/Alaska Native"),
             "B. Am. Indian/Alaska Native women with NO reachable subspecialist", "by subspecialty, 2013-2023")
  sfig <- (pRur | pAIAN) + plot_annotation(
    title="Access deserts by subspecialty — E2SFCA, 2013-2023 (CONUS)",
    subtitle="Share of at-risk women who cannot reach ANY subspecialist within the travel-time catchment; rarer subspecialties (CFP, PAG) leave the most women with zero access",
    caption="Production mass-conserving E2SFCA (run e2sfca_20260712_190734). Higher = worse. == Desjardins Q1 (zero-access quintile).",
    theme=theme(plot.title=element_text(size=rel(1.25),face="bold"),plot.title.position="plot"))
  sf <- file.path(OUT, "fig_allsubspec_equity_summary.png")
  ggsave(sf, sfig, width=14, height=6.5, dpi=200, bg="white")
  say("wrote %s", sf)
}
say("DONE — %d subspecialties", length(SUBS))
