#!/usr/bin/env Rscript
# =============================================================================
# desjardins7/10_rebuild_workforce_recovery.R
# Rebuild the workforce descriptive stats (Table 1) and the ascertainment flow
# after geocoding recovery: the mapped set now = original mapped + 802 recovered.
#   artifacts/desjardins7/table1_physicians_recovered.csv
#   artifacts/desjardins7/workforce_flow_recovered.csv
# =============================================================================
suppressWarnings(suppressMessages({ library(sf); library(dplyr) }))
ROOT <- if (requireNamespace("here", quietly=TRUE)) here::here() else normalizePath(".")
if (!exists("E2SFCA_FROZEN_RUN_ID")) source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))  # SSOT: frozen E2SFCA run
OUT  <- file.path(ROOT,"artifacts","desjardins7")
say  <- function(...) { cat(sprintf("[dj7-wf] %s\n", sprintf(...))); flush.console() }
source(file.path(ROOT,"R","accessibility_stratification.R"))
SUBS <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP"); YR <- 2020L
n2c  <- c("Gynecologic Oncology"="GO","CRI"="GO","Hospice and Palliative Medicine"="GO",
 "Maternal-Fetal Medicine"="MFM","Reproductive Endocrinology and Infertility"="REI",
 "Female Pelvic Medicine & Reconstructive Surgery"="FPMRS","MIG"="MIGS",
 "Pediatric & Adolescent Gynecology"="PAG","Complex Family Planning"="CFP")

acs <- readRDS(file.path(ROOT,"artifacts","2sfca","cell_zero","cache","acs2020_allrace.rds"))
ruca<- read.csv(file.path(ROOT,"data","external","ruca_tract_mapping.csv"),colClasses="character") |>
  transmute(GEOID=tract_geoid, rurality=rurality_from_ruca(as.integer(ruca_code)))
polys <- st_transform(acs$geom[,"GEOID"],5070) |> st_make_valid()

y <- readRDS(file.path(ROOT,"artifacts","20260702_120134_90bf52ef","step_3_year_coord_map.rds"))
y$code <- n2c[y$subspecialty_name]
# original mapped set (2020, coord present) -> per npi cert + tract rurality
act0 <- y |> filter(analysis_year==YR, !is.na(coord_id), !is.na(lat), !is.na(code)) |>
  distinct(npi, code, .keep_all=TRUE) |> transmute(npi=as.character(npi), code, cert=certification_year, lat, lon)
p0 <- st_join(st_transform(st_as_sf(act0, coords=c("lon","lat"), crs=4326),5070), polys, join=st_within)
act0$GEOID <- p0$GEOID
# certification year lookup for recovered
certmap <- y |> filter(!is.na(certification_year)) |> distinct(npi, .keep_all=TRUE) |>
  transmute(npi=as.character(npi), cert=certification_year)
rec <- readr::read_csv(file.path(OUT,"recovered_2020.csv"), show_col_types=FALSE) |>
  mutate(npi=as.character(npi)) |>
  left_join(certmap, by="npi") |> transmute(npi, code, cert, GEOID=as.character(GEOID))

comb <- bind_rows(act0 |> transmute(npi, code, cert, GEOID=as.character(GEOID)), rec) |>
  distinct(npi, code, .keep_all=TRUE) |>
  left_join(ruca, by="GEOID")
comb$rurality[is.na(comb$rurality)] <- "Rural"
comb$stage <- ifelse((YR - comb$cert) <= 15, "early", "late")
say("combined mapped workforce: %d (orig %d + recovered %d)", nrow(comb), nrow(act0), nrow(rec))

t1 <- comb |> group_by(code) |>
  summarise(total=n(), early=sum(stage=="early",na.rm=TRUE),
            metro=sum(rurality=="Metropolitan"), rural=sum(rurality=="Rural"),
            med_yrs_cert=median(YR-cert, na.rm=TRUE), .groups="drop") |>
  mutate(pct_early=100*early/total, pct_rural=100*rural/total) |>
  arrange(match(code,SUBS))
# growth (physician-count trend, unchanged) from existing fig2b
gy <- readr::read_csv(file.path(OUT,"fig2b_counts.csv"), show_col_types=FALSE) |>
  filter(year %in% c(2013,2023)) |> transmute(code=subspec, year, n=n_providers) |>
  tidyr::pivot_wider(names_from=year, values_from=n, names_prefix="n") |>
  mutate(growth_pct=100*(n2023-n2013)/n2013)
t1 <- t1 |> left_join(gy, by="code")
readr::write_csv(t1, file.path(OUT,"table1_physicians_recovered.csv"))

# updated flow: active unchanged, geocoded now includes recovered
flow <- readr::read_csv(file.path(OUT,"workforce_flow.csv"), show_col_types=FALSE)
recn <- rec |> count(code, name="recovered")
flow <- flow |> left_join(recn, by=c("subspec"="code")) |>
  mutate(recovered=tidyr::replace_na(recovered,0),
         geocoded_recovered=geocoded_2020+recovered,
         ungeocoded_after=active_2020-geocoded_recovered) |>
  select(subspec, universe_2013_2023, active_2020, geocoded_2020, recovered,
         geocoded_recovered, ungeocoded_after)
readr::write_csv(flow, file.path(OUT,"workforce_flow_recovered.csv"))

say("mapped 2020: %d -> %d ; unmapped %.2f%% -> %.2f%%",
    sum(flow$geocoded_2020), sum(flow$geocoded_recovered),
    100*(sum(flow$active_2020)-sum(flow$geocoded_2020))/sum(flow$active_2020),
    100*sum(flow$ungeocoded_after)/sum(flow$active_2020))
cat("\n=== Table 1 (recovered) ===\n"); print(as.data.frame(t1 |> transmute(code,total,pct_early=round(pct_early,1),
  metro,rural,pct_rural=round(pct_rural,2))))
cat("\n=== flow ===\n"); print(as.data.frame(flow))
