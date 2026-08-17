#!/usr/bin/env Rscript
# =============================================================================
# Scientific fingerprint: the numbers, not the pass/fail.
# =============================================================================
# Every scientific suite runs on ubuntu-latest and nowhere else. The R CMD check
# matrix covers macOS and Windows, but tests/ is excluded from the package
# build, so the E2SFCA science has never executed on another platform at all.
#
# That matters here more than for most packages. Overlap fractions come out of
# GEOS via sf, and the accessibility values are floating-point sums over those
# fractions. A platform that intersects polygons even slightly differently, or
# accumulates in a different order, produces different science while every test
# still passes -- because the tests assert tolerances, not agreement BETWEEN
# platforms.
#
# So each platform emits this fingerprint and a comparison job checks they
# agree. Pass/fail on three machines is weaker than three machines producing
# the same numbers.
#
# Also used for the determinism check: two independent R sessions on the SAME
# machine must produce byte-identical output.
#
# Usage: Rscript tools/ci/scientific_fingerprint.R [out.json]

args <- commandArgs(trailingOnly = TRUE)
out  <- if (length(args)) args[1] else "scientific-fingerprint.json"
for (p in c("jsonlite", "sf")) if (!requireNamespace(p, quietly = TRUE))
  stop("scientific_fingerprint.R needs ", p, call. = FALSE)

suppressWarnings(suppressMessages(library(sf)))
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
source(file.path(root, "R", "two_step_floating_catchment.R"))
source(file.path(root, "tests", "fixtures", "study_oracle.R"))

# Full precision: the point is to detect a difference in the last places, so
# nothing may be rounded away on the way into the file.
fmt <- function(x) vapply(as.numeric(x), function(v)
  if (is.na(v)) "NA" else sprintf("%.17g", v), character(1))

# --- 1. the end-to-end study, straight through the real entry contracts ------
sup <- compute_provider_supply(study_year_coord_map(), study_cohort(), "GO", 2020L)
ov  <- compute_band_tract_overlap(study_iso_sf(), study_tracts_sf(), verbose = FALSE)
res <- compute_e2sfca(ov, study_tract_pop(), sup, weights = STUDY_W)
acc <- as.data.frame(res$access); acc <- acc[order(acc$GEOID), ]
pr  <- as.data.frame(res$provider_ratios); pr <- pr[order(pr$coord_id), ]
ovd <- as.data.frame(ov); ovd <- ovd[order(ovd$coord_id, ovd$band, ovd$GEOID), ]

# --- 2. the geometry step alone, because that is where GEOS enters -----------
geom <- stats::setNames(fmt(ovd$overlap_fraction),
                        paste(ovd$coord_id, ovd$band, ovd$GEOID, sep = "|"))

# --- 3. the published fixtures, as an absolute anchor ------------------------
W_lq <- c("30" = 1.00, "60" = 0.68, "120" = 0.22)
lq <- fmt(as.numeric(e2sfca_incremental_weights(W_lq, step2_power = 1)))
dl <- fmt(as.numeric(e2sfca_incremental_weights(W_lq, step2_power = 2)))

fp <- list(
  schema_version = "1.0.0",
  platform = list(
    os        = unname(Sys.info()[["sysname"]]),
    r_version = paste0(R.version$major, ".", R.version$minor),
    sf        = as.character(utils::packageVersion("sf")),
    geos      = tryCatch(sf::sf_extSoftVersion()[["GEOS"]], error = function(e) NA_character_),
    gdal      = tryCatch(sf::sf_extSoftVersion()[["GDAL"]], error = function(e) NA_character_),
    proj      = tryCatch(sf::sf_extSoftVersion()[["PROJ"]], error = function(e) NA_character_)
  ),
  # Everything below is compared ACROSS platforms; `platform` above is recorded
  # for diagnosis and deliberately not compared.
  science = list(
    overlap_fraction   = as.list(geom),
    weighted_demand    = as.list(stats::setNames(fmt(pr$weighted_demand), pr$coord_id)),
    ratio_for_surface  = as.list(stats::setNames(fmt(pr$ratio_for_surface), pr$coord_id)),
    access_math        = as.list(stats::setNames(fmt(acc$access_math), acc$GEOID)),
    reached            = as.list(stats::setNames(as.character(acc$reached), acc$GEOID)),
    luo_qi_increments  = as.list(stats::setNames(lq, names(W_lq))),
    delamater_increments = as.list(stats::setNames(dl, names(W_lq)))
  )
)

writeLines(jsonlite::toJSON(fp, auto_unbox = TRUE, pretty = TRUE), out)
cat("wrote ", out, "\n", sep = "")
cat("  os=", fp$platform$os, " R=", fp$platform$r_version,
    " GEOS=", fp$platform$geos, "\n", sep = "")
cat("  science values fingerprinted: ",
    sum(lengths(fp$science)), "\n", sep = "")
