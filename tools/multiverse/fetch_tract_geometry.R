#!/usr/bin/env Rscript
# Cache one ACS tract extract (geometry + all-ages female denominators) for a
# given vintage year, matching the structure of acs2020_tracts.rds exactly:
#   list(geom = sf(GEOID, geometry, EPSG:4269), den = tibble(GEOID, total_f, aian_f, white_f))
#
# Tract geometry has exactly TWO vintages across 2013-2023 -- verified by
# querying GEOIDs year by year, not assumed -- so only 2013 (2010 tracts) is
# needed here; 2020 (2020 tracts) is already cached.
#
# Usage: E2SFCA_GEOM_YEAR=2013 Rscript tools/multiverse/fetch_tract_geometry.R
suppressWarnings(suppressMessages({library(tidycensus); library(dplyr); library(sf)}))
say <- function(...) cat(sprintf("[geom] %s\n", sprintf(...)))
Y <- as.integer(Sys.getenv("E2SFCA_GEOM_YEAR", "2013"))
if (is.na(Y)) stop("E2SFCA_GEOM_YEAR must be an integer year")
OUT <- sprintf("artifacts/2sfca/sensitivity/cache/acs%d_tracts.rds", Y)
if (file.exists(OUT)) { say("%s already cached", OUT); quit(status = 0L) }

# CONUS: the study excludes Alaska and Hawaii; 49 units including DC.
st <- setdiff(c(state.abb, "DC"), c("AK", "HI"))
VARS <- c(total_f = "B01001_026", white_f = "B01001H_017", aian_f = "B01001C_017")
say("fetching %d states with geometry for ACS %d (this is the slow part)", length(st), Y)

parts <- lapply(st, function(s) {
  d <- suppressWarnings(suppressMessages(
    get_acs(geography = "tract", variables = VARS, state = s,
            year = Y, survey = "acs5", geometry = TRUE, output = "wide")))
  d
})
all <- do.call(rbind, parts)
say("fetched %d tracts", nrow(all))

est <- function(v) { k <- paste0(v, "E"); if (k %in% names(all)) all[[k]] else all[[v]] }
den <- tibble(GEOID = all$GEOID,
              total_f = as.numeric(est("total_f")),
              aian_f  = as.numeric(est("aian_f")),
              white_f = as.numeric(est("white_f")))
geom <- all[, "GEOID"] |> st_transform(4269)

# Fail closed rather than cache a partial extract: a geometry file short by a
# state would silently zero that state's women, which is exactly the
# Connecticut failure one level up.
if (nrow(den) != nrow(geom)) stop("den/geom row mismatch")
if (nrow(den) < 60000L) stop("implausibly few tracts (", nrow(den), "); refusing to cache")
if (any(is.na(den$total_f))) stop(sum(is.na(den$total_f)), " tracts have NA female population")
n_states <- length(unique(substr(den$GEOID, 1, 2)))
if (n_states != length(st)) stop("expected ", length(st), " states, got ", n_states)
say("validated: %d tracts across %d states, %.0f women", nrow(den), n_states, sum(den$total_f))

dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
saveRDS(list(geom = geom, den = den), OUT)
say("wrote %s", OUT)
