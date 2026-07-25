#!/usr/bin/env Rscript
# ==============================================================================
# stratify_go_allyears_access.R
# ------------------------------------------------------------------------------
# Rurality- and race/ethnicity-stratified GO accessibility for ALL 11 years
# (2013-2023) — answers Desjardins et al.'s temporal question: do the rural and
# racial access gaps improve over time?
#
# Tract-vintage aware:
#   years 2013-2019 -> 2010-vintage tracts -> RUCA 2010 + ACS<=2019
#   years 2020-2023 -> 2020-vintage tracts -> RUCA 2020 + ACS>=2020 (2023->2022)
# Access: per-tract access_mean_population_per100k (production mass-conserving).
# Race  : ACS B01001[*]_017 female totals (per year); rurality weight = total F.
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(ggplot2); library(patchwork) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
OUT  <- file.path(ROOT, "artifacts", "2sfca", "figures")
CACHE <- Sys.getenv("STRAT_CACHE", file.path(tempdir(), "acs_race_cache"))
dir.create(OUT, showWarnings = FALSE, recursive = TRUE); dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[strat-all] %s\n", sprintf(...)))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
ACCDIR <- Sys.getenv("GO_ACCESS_DIR")                       # dir holding step_4_2sfca_GO_<yr>.rds
stopifnot(nzchar(ACCDIR), dir.exists(ACCDIR))
YEARS <- 2013:2023

acs_year_of <- function(y) max(min(y, 2022L), 2013L)
vintage_of  <- function(y) if (y >= 2020L) 2020L else 2010L
ruca_2020 <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"), colClasses="character")
ruca_2010 <- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping_2010.csv"), colClasses="character")
ruca_of <- function(y) {
  r <- if (vintage_of(y) == 2020L) ruca_2020 else ruca_2010
  transmute(r, GEOID = tract_geoid, rurality = ifelse(as.integer(ruca_code) %in% 1:3, "Metropolitan", "Rural"))
}

VARS <- c(total_f="B01001_026", white_nh="B01001H_017", hispanic="B01001I_017",
          black="B01001B_017", aian="B01001C_017", asian="B01001D_017", nhpi="B01001E_017")
fetch_den <- function(acs_year) {                            # cached per ACS-year
  cf <- file.path(CACHE, sprintf("acs_den_%d.rds", acs_year))
  if (file.exists(cf)) return(readRDS(cf))
  say("fetching ACS %d female denominators (total + 6 groups)", acs_year)
  raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=VARS, state=s, year=acs_year, geometry=FALSE)))
  den <- raw |> transmute(GEOID=as.character(GEOID), variable, estimate=as.numeric(estimate)) |>
    tidyr::pivot_wider(names_from=variable, values_from=estimate)
  saveRDS(den, cf); den
}

wmean <- function(x, w){ ok<-!is.na(x)&!is.na(w)&w>0; sum(x[ok]*w[ok])/sum(w[ok]) }
zshare<- function(a, w){ ok<-!is.na(w)&w>0; sum(w[ok][a[ok]==0])/sum(w[ok]) }
GRP <- tibble::tribble(~key,~label,
  "white_nh","White, non-Hispanic","black","Black alone","hispanic","Hispanic (any race)",
  "asian","Asian alone","aian","Am. Indian/Alaska Native","nhpi","Nat. Hawaiian/Pac. Isl.")

rur_all <- list(); race_all <- list()
for (y in YEARS) {
  af <- file.path(ACCDIR, sprintf("step_4_2sfca_GO_%d.rds", y))
  stopifnot(file.exists(af))
  acc <- readRDS(af) |> transmute(GEOID=as.character(GEOID), access=access_mean_population_per100k)
  den <- fetch_den(acs_year_of(y))
  d <- acc |> inner_join(ruca_of(y), by="GEOID") |> inner_join(den, by="GEOID")
  d$access[is.na(d$access)] <- 0
  rur_all[[as.character(y)]] <- d |> group_by(rurality) |>
    summarise(year=y, mean_access=wmean(access,total_f), pct_zero=100*zshare(access,total_f),
              women=sum(total_f,na.rm=TRUE), .groups="drop")
  race_all[[as.character(y)]] <- purrr::map_dfr(seq_len(nrow(GRP)), function(i){
    w<-d[[GRP$key[i]]]; tibble(year=y, group=GRP$label[i],
      mean_access=wmean(d$access,w), pct_zero=100*zshare(d$access,w), women=sum(w,na.rm=TRUE)) })
  say("%d done (tracts=%d, vintage=%d, ACS=%d)", y, nrow(d), vintage_of(y), acs_year_of(y))
}
rur <- bind_rows(rur_all); race <- bind_rows(race_all)
readr::write_csv(rur,  file.path(OUT,"go_allyears_access_by_rurality.csv"))
readr::write_csv(race, file.path(OUT,"go_allyears_access_by_race.csv"))

# ── figure: trends 2013-2023 ─────────────────────────────────────────────────
xsc <- list(scale_x_continuous(breaks=2013:2023, guide=guide_axis(check.overlap=TRUE)))
th  <- theme_minimal(base_size=12) + theme(plot.title=element_text(size=rel(1.1),face="bold"),
        plot.title.position="plot", panel.grid.minor=element_blank())
rpal_rur <- c(Metropolitan="#2171b5", Rural="#cb4b16")
lab_rur <- rur |> filter(year==2023)
pA <- ggplot(rur, aes(year, mean_access, colour=rurality)) +
  geom_line(linewidth=1) + geom_point(size=1.6) +
  geom_text(data=lab_rur, aes(label=rurality), hjust=-0.1, size=9, size.unit="pt", fontface="bold") +
  scale_colour_manual(values=rpal_rur, guide="none") + xsc +
  scale_x_continuous(breaks=2013:2023, limits=c(2013,2024.6), guide=guide_axis(check.overlap=TRUE)) +
  labs(title="A. Mean access by rurality", x=NULL, y="GO access (per 100k women)") + th

pal6 <- setNames(c("#6a51a3","#238b45","#e6550d","#2171b5","#d94801","#31a354"),
                 race$group[race$year==2020][order(race$mean_access[race$year==2020])])
lab_race <- race |> filter(year==2023)
pB <- ggplot(race, aes(year, mean_access, colour=group)) +
  geom_line(linewidth=0.9) + geom_point(size=1.3) +
  geom_text(data=lab_race, aes(label=group), hjust=-0.05, size=8, size.unit="pt") +
  scale_colour_manual(values=pal6, guide="none") +
  scale_x_continuous(breaks=2013:2023, limits=c(2013,2026.5), guide=guide_axis(check.overlap=TRUE)) +
  labs(title="B. Mean access by race / ethnicity", x=NULL, y="GO access (per 100k women)") + th

# Panel C: % with ZERO reachable GO over time — the worst-off (Rural, AIAN)
zero_df <- bind_rows(
  rur |> filter(rurality=="Rural") |> transmute(year, who="Rural (all races)", pct_zero),
  rur |> filter(rurality=="Metropolitan") |> transmute(year, who="Metropolitan", pct_zero),
  race|> filter(group=="Am. Indian/Alaska Native") |> transmute(year, who="Am. Indian/Alaska Native", pct_zero))
lab_z <- zero_df |> filter(year==2023)
pC <- ggplot(zero_df, aes(year, pct_zero, colour=who)) +
  geom_line(linewidth=1) + geom_point(size=1.6) +
  geom_text(data=lab_z, aes(label=who), hjust=-0.05, size=8, size.unit="pt", fontface="bold") +
  scale_colour_manual(values=c("Rural (all races)"="#cb4b16","Metropolitan"="#2171b5",
                               "Am. Indian/Alaska Native"="#6a51a3"), guide="none") +
  scale_x_continuous(breaks=2013:2023, limits=c(2013,2027), guide=guide_axis(check.overlap=TRUE)) +
  labs(title="C. Share of women with NO reachable GO", subtitle="Does the gap improve over time?",
       x=NULL, y="% women, access = 0") + th

fig <- (pA | pB) / pC +
  plot_annotation(
    title="GO accessibility disparities over time, 2013-2023 - E2SFCA (CONUS)",
    subtitle="Population-weighted travel-time catchment access by rurality and race/ethnicity; a temporal parallel to Desjardins et al. 2023",
    # SSOT anchor (E2SFCA_FROZEN_RUN_ID): this display label names the frozen run
    # (scripts/manuscript_e2sfca_values.R). The data dir is GO_ACCESS_DIR (line 22);
    # if that is overridden to another run the label must be updated to match.
    caption="Production mass-conserving E2SFCA (run e2sfca_20260712_190734). Rurality = USDA RUCA (vintage-matched). Race = ACS B01001[*]_017 female totals (H=White NH, I=Hispanic; B/C/D/E race-alone).",
    theme=theme(plot.title=element_text(size=rel(1.25),face="bold"), plot.title.position="plot"))
out_png <- file.path(OUT, "fig_go_allyears_access_stratified.png")
ggsave(out_png, fig, width=13, height=10, dpi=200, bg="white")
say("wrote %s", out_png)
# compact console summary
say("=== RURAL mean access + %%zero by year ===")
print(as.data.frame(rur |> filter(rurality=="Rural") |> select(year,mean_access,pct_zero)), digits=3)
say("=== AIAN mean access + %%zero by year ===")
print(as.data.frame(race |> filter(group=="Am. Indian/Alaska Native") |> select(year,mean_access,pct_zero)), digits=3)
