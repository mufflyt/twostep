# =============================================================================
# End-to-end study fixture: raw pipeline inputs, not pre-digested tables.
# =============================================================================
# Enters twostep at the EARLIEST practical contract -- provider cohort and
# coordinate map for the supply side, isochrone and tract GEOMETRY for the
# demand side -- so the joins, the subspecialty and year filters, the catchment
# construction and the area-overlap arithmetic are all exercised rather than
# bypassed.
#
# Geometry is axis-aligned rectangles in EPSG:5070 with 1000 m sides, so every
# overlap fraction is an exact simple number a reader can check by eye: a tract
# is either fully inside a catchment (1.0), exactly half inside (0.5), or out.
#
# Component A is the study. Component B sits 1000 km away with far larger
# population and supply, and must never perturb A.

.rect <- function(x0, x1, y0, y1) {
  sf::st_polygon(list(cbind(c(x0, x1, x1, x0, x0), c(y0, y0, y1, y1, y0))))
}

# --- tracts -------------------------------------------------------------------
study_tracts_sf <- function() {
  g <- list(
    .rect(0,    1000, 0,    1000),   # A01
    .rect(1000, 2000, 0,    1000),   # A02  reached by TWO providers
    .rect(2000, 3000, 0,    1000),   # A03
    .rect(0,    1000, 1000, 2000),   # A04  zero population
    .rect(3000, 4000, 0,    1000),   # A05  UNREACHABLE by any catchment
    .rect(1e6,       1e6 + 1000, 0, 1000),   # B01 disconnected component
    .rect(1e6 + 1000, 1e6 + 2000, 0, 1000)   # B02 disconnected component
  )
  sf::st_sf(GEOID = c("A01", "A02", "A03", "A04", "A05", "B01", "B02"),
            geometry = sf::st_sfc(g, crs = 5070))
}

study_tract_pop <- function() {
  data.frame(
    GEOID      = c("A01", "A02", "A03", "A04", "A05", "B01", "B02"),
    female_pop = c(1000,  2000,  500,   0,     800,   50000, 30000),
    stringsAsFactors = FALSE)
}

# --- isochrones (CUMULATIVE: the 60 band contains the 30 band) ----------------
study_iso_sf <- function() {
  g <- list(
    .rect(0,    1500, 0, 1000),   # PA1 @30 -> A01 = 1.0, A02 = 0.5
    .rect(0,    2500, 0, 1000),   # PA1 @60 -> A01 = 1.0, A02 = 1.0, A03 = 0.5
    .rect(1000, 2000, 0, 1000),   # PA2 @30 -> A02 = 1.0
    .rect(1000, 2000, 0, 1000),   # PA2 @60 -> A02 = 1.0 (no growth)
    .rect(0,    1000, 1000, 2000),# PA3 @30 -> A04 only, which has ZERO population
    .rect(1e6,  1e6 + 2000, 0, 1000), # PB1 @30 -> B01 = 1.0, B02 = 1.0
    .rect(1e6,  1e6 + 2000, 0, 1000)  # PB1 @60 -> same (cumulative, no growth)
  )
  sf::st_sf(coord_id           = c("PA1", "PA1", "PA2", "PA2", "PA3", "PB1", "PB1"),
            drive_time_minutes = c(30L,   60L,   30L,   60L,   30L,   30L,   60L),
            geometry = sf::st_sfc(g, crs = 5070))
}

# --- supply side: cohort + coordinate map -------------------------------------
# Deliberately carries rows that MUST be excluded, so the filters are tested
# rather than assumed: a physician in another subspecialty, one in another
# analysis year, and one whose location is a placeholder (NA match_source).
study_cohort <- function() {
  data.frame(
    npi                     = c(101, 102, 201, 301, 302, 303, 401, 501, 601),
    subspecialty_normalized = c("GO", "GO", "GO", "GO", "GO", "GO",
                                "MFM",          # wrong subspecialty
                                "GO", "GO"),
    stringsAsFactors = FALSE)
}

study_year_coord_map <- function(year = 2020L) {
  data.frame(
    npi           = c(101, 102, 201, 301, 302, 303, 401, 501, 601, 601),
    analysis_year = c(year, year, year, year, year, year,
                      year,            # wrong subspecialty, filtered by cohort
                      year - 1L,       # WRONG YEAR
                      year, year),     # 601 appears twice at PB1: n_distinct = 1
    coord_id      = c("PA1", "PA1", "PA2", "PA3", "PA3", "PA3",
                      "PA1", "PA1", "PB1", "PB1"),
    match_source  = c("geo", "geo", "geo", "geo", "geo", "geo",
                      "geo", "geo", "geo", NA),   # NA = placeholder, dropped
    stringsAsFactors = FALSE)
}

# Cumulative-band weights for the fixture: two bands only, so the arithmetic
# stays hand-checkable. inc = (1.00 - 0.68, 0.68 - 0) = (0.32, 0.68).
STUDY_W <- c("30" = 1.00, "60" = 0.68)
