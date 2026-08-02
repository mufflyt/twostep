#' @title Canonical Drive-Time Contour Bands (SHIM: live from mufflyaccess)
#'
#' @description
#' The SHARED band SSOTs -- `CANONICAL_BANDS`, `get_canonical_bands()`,
#' `PRIMARY_ACCESS_BAND_MIN`, `PRIMARY_ACCESS_BAND_SEC`, `get_primary_access_band()`
#' -- are sourced live from the shared mufflyaccess package (now public + pinned in
#' renv.lock), the single source of truth across isochrones / twostep / cliff, so
#' cross-repo drift is impossible. Guarded by
#' tests/testthat/test-ssot-access-constants.R. This file also keeps the
#' twostep-specific active-band pieces (`ACTIVE_BANDS_FALLBACK`,
#' `get_active_bands()`) that read `config/isochrone_config.yaml` and are NOT in
#' the package.
#'
#' @family contour-bands
#' @name contour_bands_module
NULL

if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("mufflyaccess (>= 0.10.0) is required (SSOT for the drive-time bands). ",
       "renv::restore() or remotes::install_github('mufflyt/mufflyaccess').",
       call. = FALSE)

# ---- shared band SSOTs, live from mufflyaccess -------------------------------

#' @rdname contour_bands_module
#' @export
CANONICAL_BANDS <- mufflyaccess::CANONICAL_BANDS

#' @rdname contour_bands_module
#' @export
PRIMARY_ACCESS_BAND_MIN <- mufflyaccess::PRIMARY_ACCESS_BAND_MIN

#' @rdname contour_bands_module
#' @export
PRIMARY_ACCESS_BAND_SEC <- mufflyaccess::PRIMARY_ACCESS_BAND_SEC

#' Return the canonical generation bands (minutes).
#' @return [CANONICAL_BANDS].
#' @export
get_canonical_bands <- mufflyaccess::get_canonical_bands

#' Return the primary access band in the requested units.
#' @param units `"min"` (default) or `"sec"`.
#' @return Integer scalar -- [PRIMARY_ACCESS_BAND_MIN] or [PRIMARY_ACCESS_BAND_SEC].
#' @export
get_primary_access_band <- mufflyaccess::get_primary_access_band

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
