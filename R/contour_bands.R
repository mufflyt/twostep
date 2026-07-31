#' @title Canonical Drive-Time Contour Bands (twostep-local SSOT, VENDORED)
#'
#' @description
#' The SHARED band SSOTs -- `CANONICAL_BANDS`, `get_canonical_bands()`,
#' `PRIMARY_ACCESS_BAND_MIN`, `PRIMARY_ACCESS_BAND_SEC`, `get_primary_access_band()`
#' -- were promoted to the shared mufflyaccess package, but that package is
#' private, so to keep twostep self-contained and reproducible by outsiders they
#' are VENDORED here (single in-repo source of truth). Upstream origin:
#' mufflyaccess (itself from isochrones/R/contour_bands.R). Behavior-identical;
#' guarded by tests/testthat/test-ssot-access-constants.R. This file also keeps the
#' twostep-specific active-band pieces (`ACTIVE_BANDS_FALLBACK`,
#' `get_active_bands()`) that read `config/isochrone_config.yaml`.
#'
#' @family contour-bands
#' @name contour_bands_module
NULL

# ---- vendored shared band SSOTs (behavior-identical to mufflyaccess) ---------

#' @rdname contour_bands_module
#' @export
CANONICAL_BANDS <- c(30L, 60L, 120L, 180L)

#' @rdname contour_bands_module
#' @export
PRIMARY_ACCESS_BAND_MIN <- 60L

#' @rdname contour_bands_module
#' @export
PRIMARY_ACCESS_BAND_SEC <- PRIMARY_ACCESS_BAND_MIN * 60L

stopifnot(
  "PRIMARY_ACCESS_BAND_MIN must be a single positive integer" =
    is.integer(PRIMARY_ACCESS_BAND_MIN) && length(PRIMARY_ACCESS_BAND_MIN) == 1L &&
    PRIMARY_ACCESS_BAND_MIN > 0L,
  "the headline band must be a member of CANONICAL_BANDS" =
    PRIMARY_ACCESS_BAND_MIN %in% CANONICAL_BANDS,
  "PRIMARY_ACCESS_BAND_SEC must equal MIN * 60" =
    is.integer(PRIMARY_ACCESS_BAND_SEC) && PRIMARY_ACCESS_BAND_SEC == PRIMARY_ACCESS_BAND_MIN * 60L,
  "CANONICAL_BANDS must be ascending, unique integers" =
    is.integer(CANONICAL_BANDS) && !is.unsorted(CANONICAL_BANDS, strictly = TRUE)
)

#' Return the canonical generation bands (minutes).
#' @return [CANONICAL_BANDS].
#' @export
get_canonical_bands <- function() CANONICAL_BANDS

#' Return the primary access band in the requested units.
#' @param units `"min"` (default) or `"sec"`.
#' @return Integer scalar -- [PRIMARY_ACCESS_BAND_MIN] or [PRIMARY_ACCESS_BAND_SEC].
#' @export
get_primary_access_band <- function(units = c("min", "sec")) {
  units <- match.arg(units)
  if (units == "sec") PRIMARY_ACCESS_BAND_SEC else PRIMARY_ACCESS_BAND_MIN
}

# ---- twostep-specific active-band handling (NOT in the package) --------------

#' Active-bands fallback when `isochrone_config.yaml` cannot be read
#'
#' @description Integer vector matching the current 4-band production set
#'   (`[30, 60, 120, 180]`). Used as the final fallback in [get_active_bands()]
#'   when no config directory resolves. Kept SEPARATE from the package's
#'   `CANONICAL_BANDS`: `CANONICAL_BANDS` is the universe of supported bands, while
#'   `ACTIVE_BANDS_FALLBACK` is the active analysis set (the two coincide today but
#'   the active set may shrink again for a band-specific failure mode).
#' @keywords internal
ACTIVE_BANDS_FALLBACK <- c(30L, 60L, 120L, 180L)

#' Return the currently active drive-time bands from config
#'
#' @description Reads `config/isochrone_config.yaml` for the active band set, with a
#'   three-strategy path resolver (here::here / PIPELINE_ROOT / getwd) so it works in
#'   nested callr subprocesses. Falls back to [ACTIVE_BANDS_FALLBACK] (NOT the
#'   package's `CANONICAL_BANDS`) to avoid fingerprint mismatches.
#' @return Integer vector of active drive-time thresholds in minutes.
#' @seealso [ACTIVE_BANDS_FALLBACK]
#' @family contour-bands
#' @keywords internal
get_active_bands <- function() {
  config_path <- tryCatch(here::here("config", "isochrone_config.yaml"), error = function(e) NULL)
  if (is.null(config_path) || !file.exists(config_path)) {
    root <- Sys.getenv("PIPELINE_ROOT", "")
    if (nzchar(root)) config_path <- file.path(root, "config", "isochrone_config.yaml")
  }
  if (is.null(config_path) || !file.exists(config_path)) {
    config_path <- file.path(getwd(), "config", "isochrone_config.yaml")
  }
  cfg <- tryCatch(
    if (!is.null(config_path) && file.exists(config_path)) yaml::read_yaml(config_path) else NULL,
    error = function(e) NULL
  )
  bands <- cfg$manuscript_settings$drive_time_thresholds_minutes
  if (is.null(bands)) bands <- ACTIVE_BANDS_FALLBACK
  sort(as.integer(bands))
}
