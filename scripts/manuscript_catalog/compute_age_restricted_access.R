#!/usr/bin/env Rscript
# ============================================================================
# Age-restricted, subspecialty-specific denominators (Chien 2020 / Ray 2018
# peds-workforce approach). The primary estimand uses the full female
# population as the denominator for every discipline; this sensitivity re-scores
# each discipline against its clinically at-risk female age band. Because
# within-tract coverage is geometric (identical across subgroups), age-restricted
# access = sum(agepop_t * percent_{t,d}/100) / sum(agepop_t) — no isochrone
# re-run needed. Per discipline, never pooled.
#
# Clinical age bands (female):
#   MFM, REI, CFP  -> reproductive age 15-44
#   PAG            -> 0-17 (pediatric/adolescent)
#   GO, URPS       -> 40+ (age-rising gyn-cancer / pelvic-floor burden)
#   MIGS           -> 18+ (adult)
#
# ACS 2019-2023 (year=2023, acs5), tract level, CONUS. Output ->
#   manuscript/stats/table_age_restricted_access.csv
# ============================================================================
suppressWarnings(suppressMessages({
  library(tidycensus); library(arrow); library(dplyr); library(tidyr); library(data.table)
}))
BAND <- 3600L
PARQ <- "scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet"
OUT  <- "manuscript/stats"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
CACHE <- "scratchpad/seam_tracts/acs_b01001_female_age_2023.rds"

# Female age variables from B01001 (Sex by Age): _027..._049
fv <- sprintf("B01001_%03d", 27:49)
age_labels <- c("a00_04","a05_09","a10_14","a15_17","a18_19","a20","a21","a22_24",
                "a25_29","a30_34","a35_39","a40_44","a45_49","a50_54","a55_59",
                "a60_61","a62_64","a65_66","a67_69","a70_74","a75_79","a80_84","a85p")
names(fv) <- age_labels
CONUS <- setdiff(c(state.abb, "DC"), c("AK","HI"))

if (file.exists(CACHE)) {
  message("using cached ACS age pull"); age <- readRDS(CACHE)
} else {
  message("pulling ACS B01001 female age bands for ", length(CONUS), " states ...")
  age <- get_acs(geography = "tract", variables = fv, state = CONUS,
                 year = 2023, survey = "acs5", output = "wide") %>%
    as.data.table()
  saveRDS(age, CACHE)
}
setnames(age, "GEOID", "fips_tract")
est <- paste0(age_labels, "E")
for (c in est) if (!c %in% names(age)) age[[c]] <- 0
A <- age[, c("fips_tract", est), with = FALSE]
setnames(A, est, age_labels)

# construct discipline denominators
A[, repro_15_44 := a15_17+a18_19+a20+a21+a22_24+a25_29+a30_34+a35_39+a40_44]
A[, ped_0_17    := a00_04+a05_09+a10_14+a15_17]
A[, ge40        := a40_44+a45_49+a50_54+a55_59+a60_61+a62_64+a65_66+a67_69+a70_74+a75_79+a80_84+a85p]
A[, ge18        := a18_19+a20+a21+a22_24+a25_29+a30_34+a35_39+a40_44+a45_49+a50_54+a55_59+a60_61+a62_64+a65_66+a67_69+a70_74+a75_79+a80_84+a85p]

DENOM <- c("Maternal-Fetal Medicine"="repro_15_44", "Gynecologic Oncology"="ge40",
           "Reproductive Endocrinology & Infertility"="repro_15_44",
           "Female Pelvic Medicine & Reconstructive Surgery"="ge40",
           "Minimally Invasive Gynecologic Surgery"="ge18",
           "Complex Family Planning"="repro_15_44",
           "Pediatric & Adolescent Gynecology"="ped_0_17")
BANDLAB <- c(repro_15_44="15-44", ge40="40+", ge18="18+", ped_0_17="0-17")
ABBR <- c("Maternal-Fetal Medicine"="MFM","Gynecologic Oncology"="GO",
          "Reproductive Endocrinology & Infertility"="REI",
          "Female Pelvic Medicine & Reconstructive Surgery"="URPS",
          "Minimally Invasive Gynecologic Surgery"="MIGS",
          "Complex Family Planning"="CFP","Pediatric & Adolescent Gynecology"="PAG")

ds <- open_dataset(PARQ)
cov <- as.data.table(ds %>% filter(range==BAND, category=="total_female") %>%
  select(fips_tract, subspecialty, percent, total) %>% collect())
setnames(cov, "total", "fem_all")
cov <- merge(cov, A[, c("fips_tract","repro_15_44","ped_0_17","ge40","ge18"), with=FALSE],
             by="fips_tract", all.x=TRUE)
cov[, frac := pmin(pmax(percent/100,0),1)]

res <- rbindlist(lapply(names(DENOM), function(sub) {
  dcol <- DENOM[[sub]]; cc <- cov[subspecialty==sub]
  full <- 100*sum(cc$fem_all*cc$frac,na.rm=TRUE)/sum(cc$fem_all,na.rm=TRUE)
  agev <- 100*sum(cc[[dcol]]*cc$frac,na.rm=TRUE)/sum(cc[[dcol]],na.rm=TRUE)
  data.table(abbrev=ABBR[sub], age_band=BANDLAB[dcol],
             denom_millions=sum(cc[[dcol]],na.rm=TRUE)/1e6,
             access60_full_female=full, access60_age_restricted=agev,
             diff_pp=agev-full)
}))
res <- res[match(c("MFM","GO","REI","URPS","MIGS","CFP","PAG"), abbrev)]
numc <- c("denom_millions","access60_full_female","access60_age_restricted","diff_pp")
res[, (numc) := lapply(.SD, round, 2), .SDcols=numc]
fwrite(res, file.path(OUT, "table_age_restricted_access.csv"))
cat("=== Age-restricted vs full-female 60-min access ===\n")
print(res, row.names=FALSE)
