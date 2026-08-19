# ==============================================================================
# ct_geoid_relabel.R -- Connecticut planning-region -> legacy county GEOIDs.
# ==============================================================================
# PORTED FROM isochrones (R/census_data_fetcher.R @ origin/main, 2026-08-16..17)
# as part of making twostep the canonical owner of the E2SFCA study layer.
#
# WHY THIS IS A SCIENTIFIC BUG, NOT A FORMATTING ONE
#   From ACS 2022 the Census Bureau returns Connecticut tracts under
#   planning-region ("COG") county FIPS (09110-09190), while the isochrone
#   overlap lineage and the 2020 native tract boundaries use legacy county FIPS
#   (09001-09015). A GEOID join across that vocabulary break matches ZERO
#   Connecticut tracts: the whole state silently leaves the analysis for 2022
#   and 2023. A national match-rate gate does NOT catch it, because CT is ~1% of
#   tracts -- the national rate stays comfortably high while one state vanishes.
#
#   Measured on the isochrones rebuild: 879 CT tracts were being dropped from
#   the ACS denominator join. Restoring them moved published numbers -- the
#   metropolitan-rural gap was OVERSTATED by 2.1-2.5% in every subspecialty and
#   both years, and the Asian-vs-White gap narrowed 4.6% (GO 2023). No
#   conclusion reversed. See inst/doc-provenance/CT_E2SFCA_GEOID_BREAK.md.
#
# WHY THIS HELPER AND NOT merge()/rbind()
#   Unlike an equivalency merge, this relabels the `$GEOID` column IN PLACE via
#   match(), preserving sf geometry and row identity. It is idempotent (a second
#   pass sees only legacy GEOIDs) and fail-closed (it stops when 2022+ CT
#   planning-region GEOIDs are present but the equivalency table is missing, or
#   when any planning-region GEOID has no table entry).
# ==============================================================================

#' Locate the Connecticut tract GEOID equivalency table
#'
#' Resolves the PI-approved ACS-2022 Connecticut equivalency table in a way that
#' works both when \pkg{twostep} is installed and when `R/` is `source()`d
#' directly from a checkout (which is how `scripts/` consume it).
#'
#' Resolution order: the `TWOSTEP_CT_EQUIVALENCY_CSV` environment variable, then
#' the installed `inst/extdata` copy, then the in-checkout `inst/extdata` copy.
#'
#' @return `character(1)` path. Returns `""` when no copy can be found, so that
#'   callers can produce a domain-specific fail-closed error.
#' @export
ct_equivalency_table_path <- function() {
  env <- Sys.getenv("TWOSTEP_CT_EQUIVALENCY_CSV", "")
  if (nzchar(env) && file.exists(env)) return(env)

  installed <- system.file("extdata", "ct_tract_geoid_equivalency_acs2022.csv",
                           package = "twostep")
  if (nzchar(installed) && file.exists(installed)) return(installed)

  # Sourced-from-checkout fallback. rprojroot anchors on DESCRIPTION, which this
  # package's own DESCRIPTION documents as the project-root anchor.
  in_checkout <- tryCatch(
    here::here("inst", "extdata", "ct_tract_geoid_equivalency_acs2022.csv"),
    error = function(e) "")
  if (nzchar(in_checkout) && file.exists(in_checkout)) return(in_checkout)

  ""
}

#' Geometry-safe Connecticut planning-region to legacy county GEOID relabel
#'
#' Relabels 2022+ ACS Connecticut planning-region tract GEOIDs (09110-09190)
#' to the legacy county GEOIDs (09001-09015) used by the isochrone overlap
#' lineage and the 2020 native tract boundaries, so that GEOID joins across the
#' 2022 vocabulary break do not silently drop the entire state.
#'
#' No-op for `census_year < 2022`, and idempotent: a second pass sees only
#' legacy GEOIDs and changes nothing. Fail-closed on a missing equivalency
#' table or an unmapped planning-region GEOID.
#'
#' @param x `sf` or `data.frame` carrying a character `GEOID` column (ACS data).
#'   Returned unchanged when it is `NULL` or has no `GEOID`.
#' @param census_year `integer` ACS end-year. No-op below 2022.
#' @param path Equivalency table path. Defaults to [ct_equivalency_table_path()].
#' @return `x` with Connecticut planning-region GEOIDs relabeled to legacy
#'   county GEOIDs. Geometry and row order are preserved.
#' @examples
#' df <- data.frame(GEOID = c("09190010101", "25025010100"))
#' # 2021 is before the break, so this is a no-op:
#' relabel_ct_geoids_safe(df, 2021)$GEOID
#' @export
relabel_ct_geoids_safe <- function(x, census_year,
                                   path = ct_equivalency_table_path()) {
  census_year <- suppressWarnings(as.integer(census_year))
  if (is.na(census_year) || census_year < 2022L) return(x)
  if (is.null(x) || is.null(x$GEOID)) return(x)

  g <- as.character(x$GEOID)
  # Documented no-legacy-counterpart water tracts: never relabeled. This is also
  # what makes the helper idempotent.
  kept_water <- c("09180990100", "09190990000")
  is_new_ct <- grepl("^091[1-9]0", g) & !(g %in% kept_water)
  if (!any(is_new_ct)) return(x)

  if (!nzchar(path) || !file.exists(path)) {
    stop(sprintf(paste0("[ct-geoid-relabel] ACS %d carries %d Connecticut ",
                        "planning-region GEOID(s) but the equivalency table is ",
                        "missing: %s"),
                 census_year, sum(is_new_ct),
                 if (nzchar(path)) path else "<not found>"), call. = FALSE)
  }

  map <- utils::read.csv(path, colClasses = "character")
  if (!all(c("legacy_geoid", "new_geoid") %in% names(map)) ||
      anyNA(map$legacy_geoid)) {
    stop("[ct-geoid-relabel] equivalency table malformed (need legacy_geoid + ",
         "new_geoid, no NA) -- refusing to relabel", call. = FALSE)
  }

  # First-match: the 2:1 water new_geoid resolves to its first legacy entry
  # (documented all-zero omit).
  idx <- match(g, map$new_geoid)
  hit <- !is.na(idx)
  x$GEOID[hit] <- map$legacy_geoid[idx[hit]]

  # Fail-closed: no CT planning-region GEOID may survive the relabel.
  still <- grepl("^091[1-9]0", as.character(x$GEOID)) &
    !(as.character(x$GEOID) %in% kept_water)
  if (any(still)) {
    stop(sprintf(paste0("[ct-geoid-relabel] %d CT planning-region GEOID(s) had ",
                        "no equivalency entry (ACS CT universe drifted): %s"),
                 sum(still),
                 paste(utils::head(unique(x$GEOID[still]), 10L),
                       collapse = ", ")), call. = FALSE)
  }

  message(sprintf(paste0("[ct-geoid-relabel] ACS %d: relabeled %d Connecticut ",
                         "planning-region -> legacy county GEOID(s)"),
                  census_year, sum(hit)))
  x
}
