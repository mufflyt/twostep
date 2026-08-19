# =============================================================================
# Zero-access estimands
# =============================================================================
# Zero access -- the share of population living where NO provider is reachable
# within any modelled catchment -- is a different estimand from mean access, and
# it fails differently. A mean is a magnitude that missing data biases; a
# zero-access share is a COUNT OF ABSENCE, so mistaking missing data for absence
# does not bias the answer, it manufactures it.

#' Population-weighted zero-access coverage audit
#'
#' @description
#' Returns the full population accounting behind a zero-access share, never a
#' bare number, so the denominator can be inspected rather than trusted.
#'
#' @section Why `NA` is not zero access:
#' [compute_e2sfca_raster] builds the surface DENSELY: it initialises every cell
#' to `0` and accumulates rasterized band contributions with `background = 0`.
#' Every cell therefore carries a computed value, and a cell outside every
#' catchment holds an *explicit* zero. Verified on a fixture in which three of
#' four tracts lie outside all catchments: 665 cells, zero `NA` in the surface,
#' zero `NA` in the population raster, 393 populated cells at exactly `0`.
#'
#' The surface is not sparse. An `NA` therefore does **not** mean "no provider
#' reachable" -- it means something upstream is incomplete: a partial surface, a
#' template/population mismatch, a failed routing input. Counting it as zero
#' access would inflate the reported share using missing data, which is the
#' conflation this package refuses everywhere else: an explicit zero is a
#' measurement, a missing value is not.
#'
#' @param surf_scaled `SpatRaster` accessibility surface.
#' @param wrast `SpatRaster` population weights (the eligible denominator).
#' @param tol_unresolved Maximum population permitted to have no evaluable
#'   accessibility before the share is withheld. Default `0`: nothing unresolved.
#'   A non-zero value is an explicit, documented decision to report a share over
#'   an incomplete denominator.
#' @return A list with `eligible_population`, `evaluable_population`,
#'   `zero_access_population`, `excluded_population`, `unresolved_population`,
#'   `pct_evaluable` and `zero_share` (percent, over EVALUABLE population; `NA`
#'   when unresolved population exceeds `tol_unresolved`).
#' @family zero access
#' @seealso [zshare_rast]
#' @export
zero_access_audit <- function(surf_scaled, wrast, tol_unresolved = 0) {
  a <- terra::values(surf_scaled)[, 1]
  w <- terra::values(wrast)[, 1]
  eligible   <- sum(w[!is.na(w)])
  excluded   <- sum(w[is.na(w)], na.rm = TRUE)
  ok         <- !is.na(w) & w > 0
  unresolved <- sum(w[ok & is.na(a)])
  evaluable  <- sum(w[ok & !is.na(a)])
  zero_pop   <- sum(w[ok & !is.na(a) & a <= 0])
  list(
    eligible_population    = eligible,
    evaluable_population   = evaluable,
    zero_access_population = zero_pop,
    excluded_population    = excluded,
    unresolved_population  = unresolved,
    pct_evaluable          = if (eligible > 0) 100 * evaluable / eligible else NA_real_,
    zero_share = if (!is.finite(evaluable) || evaluable <= 0) NA_real_
                 else if (unresolved > tol_unresolved) NA_real_
                 else 100 * zero_pop / evaluable)
}

#' Population-weighted zero-access share, failing closed
#'
#' @description
#' The share of population with no reachable provider, as a percentage of
#' EVALUABLE population. Errors -- naming the population involved -- when any
#' population has no evaluable accessibility, rather than returning a plausible
#' number computed over a silently shrunken denominator.
#'
#' The share is population-weighted, not tract- or cell-counted: two of four
#' cells may be zero-access while holding a tenth of the people.
#'
#' @inheritParams zero_access_audit
#' @return Percent in `[0, 100]`.
#' @family zero access
#' @seealso [zero_access_audit]
#' @export
zshare_rast <- function(surf_scaled, wrast, tol_unresolved = 0) {
  au <- zero_access_audit(surf_scaled, wrast, tol_unresolved)
  if (is.na(au$zero_share) && isTRUE(au$unresolved_population > tol_unresolved)) {
    stop(sprintf(paste0(
      "zero-access: %.0f of %.0f eligible population have NO evaluable accessibility ",
      "(%.4f%%). NA access is an incomplete surface, not zero access; counting it as ",
      "zero would inflate the zero-access share using missing data. Fix the surface, ",
      "or pass tol_unresolved to declare an explicit tolerance."),
      au$unresolved_population, au$eligible_population,
      100 * au$unresolved_population / max(au$eligible_population, 1)), call. = FALSE)
  }
  au$zero_share
}
