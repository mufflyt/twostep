#!/usr/bin/env Rscript
# Build a deterministic multi-year ACS bundle for the 11-year E2SFCA production
# run, so EC2 needs no Census API. Population VALUES per ACS year (2013-2022);
# tract GEOMETRY reused from the seam bundle (identical tract sets => consistent
# with the validated seam gate). Bundle schema consumed by run_2sfca.R --acs-bundle:
#   list(pop_by_year = list("2013"=tibble(GEOID,female_pop), ... "2022"=...),
#        geom_by_vintage = list("2010"=sf, "2020"=sf))
suppressWarnings(suppressMessages({ library(sf); library(dplyr) }))
options(tigris_use_cache = TRUE)
say <- function(...) cat(sprintf("[prefetch-2sfca] %s\n", sprintf(...)))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))
ACS_YEARS <- 2013:2022   # clamp(year,2013,2022) for study years 2013-2023

fetch_pop <- function(year, states) {
  raw <- purrr::map_dfr(states, function(s) suppressMessages(tidycensus::get_acs(
    geography="tract", variables=c(female_pop="B01001_026"),
    state=s, year=year, geometry=FALSE)))
  raw <- raw[raw$variable=="female_pop", ]
  dplyr::tibble(GEOID=as.character(raw$GEOID), female_pop=as.numeric(raw$estimate))
}

seam_bundle <- "artifacts/2sfca_seam/seam_acs_bundle_2020.rds"
stopifnot(file.exists(seam_bundle))
sb <- readRDS(seam_bundle)
say("reusing seam geometries: geom2020=%d, geom2010=%d tracts", nrow(sb$geom2020), nrow(sb$geom2010))

st <- conus()
pop_by_year <- list()
for (y in ACS_YEARS) {
  say("fetching female pop ACS %d (CONUS, %d states)", y, length(st))
  pv <- fetch_pop(y, st)
  pop_by_year[[as.character(y)]] <- pv
  say("  ACS %d: %d tract rows, total female = %.0f", y, nrow(pv), sum(pv$female_pop, na.rm=TRUE))
}

bundle <- list(
  pop_by_year = pop_by_year,
  geom_by_vintage = list("2010" = sb$geom2010, "2020" = sb$geom2020),
  created = "prefetch_2sfca_acs",
  acs_years = ACS_YEARS)
out <- "artifacts/2sfca_seam/acs_bundle_2013_2022.rds"
saveRDS(bundle, out)
say("wrote %s (%.1f MB)", out, file.info(out)$size/1e6)
say("pop-years: %s", paste(names(pop_by_year), collapse=", "))
