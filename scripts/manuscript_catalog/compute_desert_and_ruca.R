#!/usr/bin/env Rscript
# ============================================================================
# (a) Subspecialty Access Desert (SAD) — two-vector operational definition
#     adapted from Ryerson 2022 (driver-training deserts): a tract is a desert
#     for discipline d if it clears BOTH a travel-impedance threshold (not
#     reached at 60 min: tract coverage <50%) AND a disadvantage threshold
#     (rural, RUCA >=4). Reported per discipline (never pooled). Rurality is a
#     transparent, locally available disadvantage vector; a validated
#     socioeconomic composite (SDI; Buchongo 2025) is the ideal second vector
#     and is noted as such in the text.
# (b) RUCA 4-level coverage stratification (Halada 2024): population-weighted
#     60-min access by metro / micropolitan / small-town / rural, per discipline.
# Output -> manuscript/stats/table_access_deserts.csv, tableS_ruca4_access.csv
# ============================================================================
suppressWarnings(suppressMessages({ library(arrow); library(dplyr); library(tidyr); library(data.table) }))
BAND <- 3600L
PARQ <- "scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet"
OUT  <- "manuscript/stats"; dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
ABBR <- c("Maternal-Fetal Medicine"="MFM","Gynecologic Oncology"="GO",
          "Reproductive Endocrinology & Infertility"="REI",
          "Female Pelvic Medicine & Reconstructive Surgery"="URPS",
          "Minimally Invasive Gynecologic Surgery"="MIGS",
          "Complex Family Planning"="CFP","Pediatric & Adolescent Gynecology"="PAG")
ORD <- c("MFM","GO","REI","URPS","MIGS","CFP","PAG")

ds <- open_dataset(PARQ)
cov <- as.data.table(ds %>% filter(range==BAND, category=="total_female") %>%
  select(fips_tract, subspecialty, percent, total, ruca_code) %>% collect())
setnames(cov, "total", "fem")
cov[, abbrev := ABBR[subspecialty]]
cov[, reached := as.integer(!is.na(percent) & percent >= 50)]
cov[, rural := as.integer(!is.na(ruca_code) & ruca_code >= 4)]
# RUCA 4-level (standard: 1-3 metro, 4-6 micropolitan, 7-9 small town, 10 rural)
cov[, ruca4 := fifelse(ruca_code <= 3, "Metropolitan",
                fifelse(ruca_code <= 6, "Micropolitan",
                 fifelse(ruca_code <= 9, "Small town", "Rural")))]

# (a) SAD deserts: not reached AND rural
sad <- cov[, {
  fem_tot <- sum(fem, na.rm=TRUE)
  d <- (reached == 0L) & (rural == 1L)
  .(desert_tracts = sum(d, na.rm=TRUE),
    desert_women_M = sum(fem[d], na.rm=TRUE)/1e6,
    pct_women_desert = 100*sum(fem[d], na.rm=TRUE)/fem_tot,
    rural_unreached_of_all_unreached = 100*sum(fem[d],na.rm=TRUE)/sum(fem[reached==0L],na.rm=TRUE))
}, by = abbrev]
sad <- sad[order(match(abbrev, ORD))]
sad[, `:=`(desert_women_M=round(desert_women_M,2), pct_women_desert=round(pct_women_desert,1),
           rural_unreached_of_all_unreached=round(rural_unreached_of_all_unreached,1))]
fwrite(sad, file.path(OUT, "table_access_deserts.csv"))
cat("=== (a) Subspecialty Access Deserts (not reached @60min AND rural) ===\n")
print(sad, row.names=FALSE)

# (b) RUCA 4-level pop-weighted 60-min access
ruca4 <- cov[, .(access60 = 100*sum(fem*pmin(pmax(percent/100,0),1),na.rm=TRUE)/sum(fem,na.rm=TRUE),
                 women_M = sum(fem,na.rm=TRUE)/1e6),
             by = .(abbrev, ruca4)]
w <- dcast(ruca4, ruca4 ~ abbrev, value.var="access60")
lev <- c("Metropolitan","Micropolitan","Small town","Rural")
w <- w[match(lev, w$ruca4)]
num <- intersect(ORD, names(w)); w[, (num) := lapply(.SD, round, 1), .SDcols=num]
setcolorder(w, c("ruca4", intersect(ORD, names(w))))
fwrite(w, file.path(OUT, "tableS_ruca4_access.csv"))
cat("\n=== (b) 60-min access by RUCA 4-level (pop-weighted %) ===\n")
print(w, row.names=FALSE)
