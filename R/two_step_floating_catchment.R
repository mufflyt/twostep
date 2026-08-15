# ==============================================================================
# Enhanced Two-Step Floating Catchment Area (E2SFCA) accessibility
# ------------------------------------------------------------------------------
# Standalone module. Computes an Enhanced 2SFCA spatial accessibility index for
# OB/GYN subspecialists using the project's existing travel-time isochrones as
# provider catchments and ACS tract population as demand.
#
# ------------------------------------------------------------------------------
# PRIMARY SOURCES  (read these before editing the math; each is mapped to the
# function it grounds, and every one is in manuscript/e2sfca_extra_refs.bib)
# ------------------------------------------------------------------------------
#  METHOD LINEAGE
#   [1] Luo W, Wang F (2003). Measures of spatial accessibility to health care
#       in a GIS environment. Environ Plann B 30(6):865-884.
#       doi:10.1068/b29120        --> the ORIGINAL 2SFCA (two-step supply/demand
#       ratio). Grounds compute_provider_supply() (step 1 supply) and the
#       two-step structure of compute_e2sfca().
#   [2] Luo W, Qi Y (2009). An enhanced two-step floating catchment area
#       (E2SFCA) method... Health Place 15(4):1100-1107.
#       doi:10.1016/j.healthplace.2009.06.002  --> the "E" in E2SFCA: a
#       distance-decay WEIGHT across nested travel-time zones. Grounds
#       E2SFCA_DEFAULT_WEIGHTS, e2sfca_band_weights(), and the zonal weighting in
#       both steps. This is the authoritative method for the paper (step2_power=1).
#   [3] Delamater PL (2013). Spatial accessibility in suboptimally configured
#       health care systems: a Modified 2SFCA (M2SFCA) metric.
#       Health Place 24:30-43. doi:10.1016/j.healthplace.2013.07.012  --> the
#       M2SFCA penalty. Grounds e2sfca_incremental_weights(step2_power=2). The
#       penalty squares the CUMULATIVE weight in STEP 2 ONLY: diff(W^2), NOT
#       diff(W)^2. Sensitivity variant only, never the headline.
#   [4] Wan N, Zhan FB, Zou B, Chow E (2012). A relative spatial access
#       assessment approach... Appl Geogr 32(2):291-299.
#       doi:10.1016/j.apgeog.2011.05.001  --> SPAR (Spatial Access Ratio):
#       access / national population-weighted mean, so the national mean is 1.00
#       by construction. Grounds the `relative_access` field and
#       e2sfca_cell_summaries()' normalization.
#  REFINEMENTS / JUSTIFICATIONS
#   [5] McGrail MR, Humphreys JS (2009). Applied Geogr 29(4):533-541.
#       doi:10.1016/j.apgeog.2008.12.003 ; McGrail MR (2012). Int J Health Geogr
#       11:50. doi:10.1186/1476-072X-11-50  --> catchment-size and decay-function
#       choices; justify the Gaussian decay option (gaussian_band_weights()).
#   [6] Wang F, Luo W (2005). Health Place 11(2):131-146.
#       doi:10.1016/j.healthplace.2004.02.003  --> integrated spatial/nonspatial
#       HPSA framing; why the national mean is a supply-per-population index.
#   [7] Apparicio P, et al. (2017). Int J Health Geogr 16:32.
#       doi:10.1186/s12942-017-0105-9  --> distance-type and AGGREGATION-ERROR
#       issues in potential-access measures. Grounds allocate_pop_areaweighted()
#       (mass-conserving allocation avoids the centroid population-aggregation
#       error; ~1.06% of population would otherwise be dropped).
#   [8] Langford M, Higgs G, Fry R (2016). Health Place 38:70-81.
#       doi:10.1016/j.healthplace.2015.11.007  --> multi-modal 2SFCA (context for
#       the single-mode, drive-time-only limitation).
#   [9] Paul J, Edwards E (2019). Int J Health Plann Manage 34(1):e536-e547.
#       doi:10.1002/hpm.2667  --> temporal 2SFCA (context for the year-specific
#       cohort design; see compute_provider_supply()'s per-year panel).
#  ACCESS CONCEPT
#  [10] Penchansky R, Thomas JW (1981). Med Care 19(2):127-140.
#       doi:10.1097/00005650-198102000-00001  --> the five dimensions of access;
#       this module measures only two (availability + geographic accessibility).
#
# ------------------------------------------------------------------------------
# REBUILD MAP  (if you are rebuilding this in six months, start here)
# ------------------------------------------------------------------------------
#   Manuscript (equations in prose + Methods/eMethods S4): the E2SFCA algorithm,
#     weights table, SPAR, and sensitivity design are written out in
#     manuscript/e2sfca_accessibility_manuscript.Rmd (eMethods S4).
#   Runbook (how to RUN it, gates, gotchas, frozen facts):
#     docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md  (allocator sha256, EPSG:5070, bands,
#     conservation tolerance, the seven sensitivity variants).
#   Non-negotiable contracts this module obeys (CLAUDE.md):
#     #17 isochrone coverage = 5 km haversine (upstream matcher, not this file);
#     #18 cache provenance (the artifacts this module consumes carry sidecars);
#     #19 Trust-a-Number: compute_provider_supply() drops match_source=NA
#         placeholder rows so a non-real location never inflates supply.
#   PROVENANCE GATE (important for a rebuild): scripts/run_2sfca.R hashes this
#     ENTIRE file (digest::digest, sha256) and stops the production run if it does
#     not equal the seam-validated allocator hash (2b78718bf65c..., recorded in
#     each run manifest as allocator.seam_validated_sha256). ANY edit here,
#     including these comments and the M2SFCA/Gaussian/SPAR additions, changes that
#     hash. The allocate_pop_areaweighted() BODY is what the seam test actually
#     certifies; if only comments or sibling functions changed, the allocation is
#     still valid and you re-pin the hash (E2SFCA_SEAM_ALLOCATOR_SHA256), but if
#     the allocator body changed you MUST re-run the seam test to re-validate.
#     The frozen manuscript numbers came from run e2sfca_20260712_190734, whose
#     allocator was 2b78718b; that artifact is immutable regardless of edits here.
#   Sensitivity driver: scripts/sensitivity_e2sfca_2020.R  (base/sharper/slower/
#     drop180/res500/gaussian/m2sfca; numerical gates; frozen-input manifest).
#   Tests: tests/testthat/test-e2sfca-m2sfca-gaussian.R (exact analytic fixtures
#     for E2SFCA vs M2SFCA vs Gaussian, zero-demand audit, SPAR) and
#     test-two-step-floating-catchment.R.
#
# ------------------------------------------------------------------------------
# WHY CUMULATIVE BANDS + INCREMENTAL WEIGHTS (and no ring-cutting)
# ------------------------------------------------------------------------------
# Classic E2SFCA divides each catchment into travel-time RINGS (0-30, 30-60,
# 60-120, 120-180 min) and applies a decreasing weight W_z to each ring. That
# requires cutting rings out of the nested isochrone polygons with
# st_difference(), which is slow and geometry-fragile.
#
# Our isochrone artifacts are CUMULATIVE (the 60-min polygon already contains the
# 30-min polygon, etc.). By Abel (summation-by-parts), a weighted sum over rings
# equals a weighted sum over cumulative bands with INCREMENTAL weights:
#
#     Sum_z  W_z * (quantity in ring z)
#   = Sum_b  w'_b * (quantity within cumulative band b),      w'_b = W_b - W_{b+1}
#
# with the convention W_{beyond the last band} = 0. This holds identically for
# BOTH steps (the ring fraction of a tract is the difference of two cumulative
# fractions), so the E2SFCA result is exactly the ring-based result — but every
# geometry operation is a plain tract-vs-cumulative-band overlap, which is the
# same primitive Step 4 already computes. See `e2sfca_incremental_weights()`.
#
# ------------------------------------------------------------------------------
# CRS: all area math is done in EPSG:5070 (NAD83 / Conus Albers, equal-area).
#   The codebase uses both 5070 and 9311 for equal-area work; this module fixes
#   on 5070 (the CRS the union-cache / geometry validators assert) and states it
#   explicitly. NEVER compute area in EPSG:4326.
# ==============================================================================

suppressWarnings({
  requireNamespace("sf", quietly = TRUE)
  requireNamespace("dplyr", quietly = TRUE)
  requireNamespace("checkmate", quietly = TRUE)
})

# Equal-area CRS used for every st_area()/st_intersection() in this module.
E2SFCA_AREA_CRS <- 5070L

#' Default cumulative-band distance-decay weights (Gaussian-shaped, monotone).
#'
#' These are the *cumulative-band* weights W_b for the four canonical travel-time
#' bands. They decay with travel time: a provider reachable within 30 min counts
#' fully; one only reachable within 180 min counts ~9%. Override to run a
#' sensitivity analysis.
#'
#' @format Named numeric vector keyed by band in minutes ("30","60","120","180").
#' @references Luo & Qi (2009) doi:10.1016/j.healthplace.2009.06.002 [source 2]
#'   introduced the zonal distance-decay weight; these specific values are a
#'   Gaussian decay (sigma = 60 min) evaluated at the four band edges and
#'   normalized to the 30-min band (see [gaussian_band_weights], source 5).
E2SFCA_DEFAULT_WEIGHTS <- c("30" = 1.00, "60" = 0.68, "120" = 0.22, "180" = 0.09)

#' Validate and return E2SFCA cumulative-band weights.
#'
#' @param weights Named numeric vector keyed by band-in-minutes. Defaults to
#'   [E2SFCA_DEFAULT_WEIGHTS]. Must be non-negative and (weakly) monotone
#'   decreasing in band, so incremental weights are non-negative.
#' @return The validated named numeric vector, sorted by ascending band.
#' @references Luo & Qi (2009) doi:10.1016/j.healthplace.2009.06.002 [source 2]:
#'   the monotone-decreasing zonal weights are what make E2SFCA "enhanced" over
#'   the flat 2SFCA of Luo & Wang (2003) [source 1].
#' @family E2SFCA distance-decay weights
#' @seealso [gaussian_band_weights], [e2sfca_incremental_weights]
#' @examples
#' # No argument uses [E2SFCA_DEFAULT_WEIGHTS], the production weights. It is the
#' # authoritative SSOT but is not exported, so the example calls the default
#' # rather than naming it -- and rather than restating the literal, which the
#' # SSOT guards in tests/testthat/test-ssot-band-weights.R forbid duplicating.
#' e2sfca_band_weights()
#' e2sfca_band_weights(c("30" = 1, "60" = 0.5, "120" = 0.2, "180" = 0.1))
#' try(e2sfca_band_weights(c("30" = 0.5, "60" = 1)))       # errors: not monotone
#' @export
e2sfca_band_weights <- function(weights = E2SFCA_DEFAULT_WEIGHTS) {
  checkmate::assert_numeric(weights, lower = 0, any.missing = FALSE, min.len = 1L,
                            names = "named")
  bands <- suppressWarnings(as.integer(names(weights)))
  if (anyNA(bands)) {
    stop("e2sfca_band_weights: weight names must be band-in-minutes (e.g. '30','60').",
         call. = FALSE)
  }
  ord <- order(bands)
  weights <- weights[ord]
  bands <- bands[ord]
  if (any(diff(weights) > 1e-9)) {
    stop("e2sfca_band_weights: weights must be monotone non-increasing in band ",
         "(else a farther band would count MORE than a nearer one, and an ",
         "incremental weight would be negative).", call. = FALSE)
  }
  weights
}

#' RAW continuous Gaussian decay kernel G(d) = exp(-d^2 / (2 sigma^2)).
#'
#' The un-normalized kernel: G(0) = 1 and G decreases monotonically. This is the
#' continuous decay function; it is NOT the zonal band weights (which normalize to
#' the inner band, see [gaussian_band_weights]). A genuinely continuous E2SFCA
#' would apply this to a per provider-to-cell travel time. Do NOT normalize this to
#' the 30-min value: distances < 30 min would then exceed 1.
#'
#' @param minutes Numeric travel times in minutes (>= 0).
#' @param sigma Gaussian bandwidth in minutes, strictly positive.
#' @return Named numeric vector G(minutes) in (0, 1], names = the minutes.
#' @references Gaussian decay as a 2SFCA impedance function: McGrail & Humphreys
#'   (2009) doi:10.1016/j.apgeog.2008.12.003 and McGrail (2012)
#'   doi:10.1186/1476-072X-11-50 [source 5]; the Gaussian form also appears in
#'   Luo & Qi (2009) [source 2] as one of the tested decay weights.
#' @family E2SFCA distance-decay weights
#' @seealso [gaussian_band_weights] (the normalized zonal wrapper actually used)
#' @examples
#' gaussian_decay_weights(c(0, 30, 60, 120), sigma = 60)
#' # G(0) = 1, then 0.882, 0.607, 0.135 : the RAW kernel, not normalized to band 1
#' @export
gaussian_decay_weights <- function(minutes, sigma = 60) {
  checkmate::assert_numeric(minutes, lower = 0, any.missing = FALSE, min.len = 1L)
  checkmate::assert_number(sigma, lower = 1e-9)
  g <- exp(-(minutes^2) / (2 * sigma^2))
  stats::setNames(g, as.character(minutes))
}

#' Gaussian-DERIVED zonal band weights (a four-band approximation, NOT continuous).
#'
#' This engine has only four nested travel-time polygons (30/60/120/180 min) and
#' rasterizes one constant contribution per band, so it is a ZONAL method. This
#' helper derives the four zonal band weights from a Gaussian decay evaluated at
#' each band's OUTER edge; it does NOT implement a continuous distance function
#' (that would need a per provider-to-cell travel time or much finer contours).
#'
#' Equation and parameterization (reproducible):
#'   raw_b = exp( - d_b^2 / (2 * sigma^2) )      d_b = band outer edge in minutes
#'   W_b   = raw_b / raw_1                        (normalized so the nearest band = 1)
#' with sigma the Gaussian bandwidth in minutes. Travel times beyond the last band
#' receive weight 0 (the incremental convention; see [e2sfca_incremental_weights]).
#'
#' @param bands Integer band outer edges in minutes (default 30/60/120/180).
#' @param sigma Gaussian bandwidth in minutes, strictly positive (default 60).
#' @return Named cumulative-band weights (monotone non-increasing), W_1 == 1.
#' @references McGrail (2012) doi:10.1186/1476-072X-11-50 [source 5] on decay-
#'   function choice; normalization to the inner band follows the zonal E2SFCA
#'   convention of Luo & Qi (2009) [source 2]. Used only by the `gaussian`
#'   sensitivity variant in scripts/sensitivity_e2sfca_2020.R.
#' @family E2SFCA distance-decay weights
#' @seealso [gaussian_decay_weights] (the raw kernel this normalizes)
#' @examples
#' round(gaussian_band_weights(c(30, 60, 120, 180), sigma = 60), 4)
#' # 30=1.0000 60=0.6873 120=0.1534 180=0.0126 : normalized to the 30-min band
#' attr(gaussian_band_weights(), "decay_meta")$sigma_minutes   # 60
#' @export
gaussian_band_weights <- function(bands = c(30L, 60L, 120L, 180L), sigma = 60) {
  checkmate::assert_numeric(bands, lower = 1, any.missing = FALSE, min.len = 1L)
  checkmate::assert_number(sigma, lower = 1e-9)     # strictly positive
  d <- sort(as.integer(bands))
  raw <- gaussian_decay_weights(d, sigma = sigma)   # raw kernel G(d)
  w <- e2sfca_band_weights(stats::setNames(as.numeric(raw / raw[1]), as.character(d)))
  # explicit contract: this is a NORMALIZED ZONAL vector, not the raw kernel.
  attr(w, "decay_meta") <- list(
    decay_function = "gaussian", decay_type = "zonal",
    normalization = "first_band", normalization_minutes = d[1],
    sigma_minutes = sigma, maximum_minutes = d[length(d)])
  w
}

#' Convert cumulative-band weights W_b into incremental weights for step 1 or 2.
#'
#' See the module header for the Abel-summation identity that makes cumulative
#' bands + incremental weights equivalent to ring-based (E2)SFCA. With
#' `step2_power = 1` (the default, and always the STEP-1 demand denominator) this
#' returns the ordinary E2SFCA increments `w'_b = W_b - W_[b+1]`. With
#' `step2_power = 2` it returns the M2SFCA (Delamater 2013) STEP-2 access
#' increments derived from the SQUARED cumulative weights,
#'   `w''_b = W_b^2 - W_[b+1]^2` (this is `diff(W^2)`, NOT `diff(W)^2`),
#' so the access step applies the distance penalty a second time and a
#' suboptimally configured system shows lower access. The outermost band's
#' increment is its own (possibly powered) weight (W beyond the last band is 0).
#'
#' @param weights Named cumulative-band weights (see [e2sfca_band_weights]).
#' @param step2_power Exponent applied to the CUMULATIVE weights before
#'   differencing: 1 = E2SFCA, 2 = M2SFCA. Must be >= 1. For power > 1 every
#'   cumulative weight must be <= 1 (else squaring would INCREASE access).
#' @return Named numeric vector of incremental weights, same names/order.
#' @references The cumulative-band + incremental-weight identity is the
#'   Abel/summation-by-parts reformulation of the ring-based E2SFCA of Luo & Qi
#'   (2009) [source 2] (see module header). step2_power = 2 implements the M2SFCA
#'   penalty of Delamater (2013) doi:10.1016/j.healthplace.2013.07.012 [source 3]:
#'   the squared-cumulative difference diff(W^2), applied in STEP 2 ONLY. Analytic
#'   fixtures pinning both cases live in tests/testthat/test-e2sfca-m2sfca-gaussian.R.
#' @family E2SFCA distance-decay weights
#' @seealso [e2sfca_band_weights], [compute_e2sfca]
#' @examples
#' # E2SFCA (step2_power = 1): plain incremental weights W_b - W_[b+1]
#' e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 1)  # 0.5 0.5
#' # M2SFCA (step2_power = 2): diff of SQUARED cumulative weights, W^2_b - W^2_[b+1]
#' e2sfca_incremental_weights(c("30" = 1, "60" = 0.5), step2_power = 2)  # 0.75 0.25
#' @export
e2sfca_incremental_weights <- function(weights = E2SFCA_DEFAULT_WEIGHTS,
                                       step2_power = 1) {
  checkmate::assert_number(step2_power, lower = 1)
  w <- e2sfca_band_weights(weights)
  if (step2_power != 1 && any(w > 1 + 1e-12)) {
    stop("e2sfca_incremental_weights: step2_power > 1 (M2SFCA) requires cumulative ",
         "weights <= 1; squaring a weight > 1 would INCREASE access.", call. = FALSE)
  }
  wp <- w^step2_power                          # W_b^power (diff of the POWERED cumulative)
  next_w <- c(wp[-1L], 0)                       # W beyond the last band = 0
  inc <- wp - next_w                            # diff(W^power), NOT diff(W)^power
  inc[inc < 0 & inc > -1e-9] <- 0               # clamp float error
  stats::setNames(inc, names(w))
}

#' Compute tract x cumulative-band overlap fractions (the geometry step).
#'
#' For every (provider origin `coord_id`, band, tract `GEOID`) this returns the
#' fraction of the TRACT's area that falls within the provider's cumulative
#' isochrone for that band. This is the only geometry-heavy operation and it is
#' YEAR-AGNOSTIC (isochrone geometry does not change year to year; only the
#' active-provider set and tract population do). Compute it once per tract
#' vintage and reuse across years.
#'
#' @param iso_sf   `sf` of provider isochrones with columns `coord_id`,
#'   `drive_time_minutes` (band, one of 30/60/120/180) and polygon `geometry`.
#'   Cumulative bands (the project's consolidated artifacts). Any CRS.
#' @param tracts_sf `sf` of census tracts with column `GEOID` and polygon
#'   `geometry`. Any CRS.
#' @param area_crs EPSG code for the equal-area projection used for all area
#'   math. Default [E2SFCA_AREA_CRS] (5070).
#' @param chunk_by_state Logical (default TRUE). Process tracts in per-state
#'   chunks so a national `st_intersection` never materializes all intersecting
#'   pairs at once. Results are identical either way; only peak memory changes.
#'   Set FALSE for small inputs where the overhead isn't worth it.
#' @param verbose  Logical; print progress.
#' @return tibble with columns `coord_id`, `band` (int minutes), `GEOID`,
#'   `overlap_fraction` (area of tract within the cumulative band / tract area,
#'   in `[0, 1]`). Only positive-overlap rows are returned.
#' @family E2SFCA computation
#' @seealso [compute_e2sfca], [compute_e2sfca_raster]
#' @export
compute_band_tract_overlap <- function(iso_sf, tracts_sf,
                                       area_crs = E2SFCA_AREA_CRS,
                                       chunk_by_state = TRUE,
                                       verbose = TRUE) {
  checkmate::assert_class(iso_sf, "sf")
  checkmate::assert_class(tracts_sf, "sf")
  checkmate::assert_subset(c("coord_id", "drive_time_minutes"), names(iso_sf))
  checkmate::assert_subset("GEOID", names(tracts_sf))

  iso <- sf::st_transform(iso_sf, area_crs)
  iso <- sf::st_make_valid(iso)
  iso$coord_id <- as.character(iso$coord_id)
  iso$band <- as.integer(round(iso$drive_time_minutes))

  tracts <- sf::st_transform(tracts_sf, area_crs)
  tracts <- sf::st_make_valid(tracts)
  tracts$GEOID <- as.character(tracts$GEOID)
  tracts$.tract_area <- as.numeric(sf::st_area(tracts))
  # Degenerate/zero-area tracts cannot receive a meaningful fraction.
  tracts <- tracts[tracts$.tract_area > 0, , drop = FALSE]

  # Chunk tracts by state FIPS (first 2 chars of GEOID) so a national
  # st_intersection never materializes all intersecting pairs at once. Each
  # tract lives in exactly one chunk, so results are identical to no chunking;
  # only peak memory changes. An origin whose isochrone spans several states is
  # simply intersected once per chunk (the STRtree prunes non-overlapping pairs).
  if (isTRUE(chunk_by_state)) {
    chunk_key <- substr(tracts$GEOID, 1, 2)
  } else {
    chunk_key <- rep("all", nrow(tracts))
  }
  chunks <- split(seq_len(nrow(tracts)), chunk_key)

  bands <- sort(unique(iso$band))
  out <- list()
  # Bounding boxes let us skip origins that cannot touch a given tract chunk.
  for (i in seq_along(bands)) {
    b <- bands[i]
    iso_b <- iso[iso$band == b, c("coord_id"), drop = FALSE]
    if (nrow(iso_b) == 0L) next
    for (ci in seq_along(chunks)) {
      if (isTRUE(verbose)) {
        message(sprintf("[e2sfca] overlap: band %d min (%d/%d), chunk %s (%d/%d)",
                        b, i, length(bands), names(chunks)[ci], ci, length(chunks)))
      }
      tr <- tracts[chunks[[ci]], c("GEOID", ".tract_area"), drop = FALSE]
      if (nrow(tr) == 0L) next
      # Prune origins whose bbox misses this chunk's bbox before intersecting.
      keep_iso <- suppressMessages(lengths(sf::st_intersects(iso_b, sf::st_as_sfc(sf::st_bbox(tr)))) > 0L)
      iso_bc <- iso_b[keep_iso, , drop = FALSE]
      if (nrow(iso_bc) == 0L) next
      inter <- suppressWarnings(sf::st_intersection(iso_bc, tr))
      if (nrow(inter) == 0L) next
      inter_area <- as.numeric(sf::st_area(inter))
      frac <- inter_area / inter$.tract_area
      frac <- pmin(pmax(frac, 0), 1)  # clamp float overshoot; drop non-positive
      keep <- frac > 0
      if (!any(keep)) next
      out[[length(out) + 1L]] <- dplyr::tibble(
        coord_id = as.character(inter$coord_id[keep]),
        band = b,
        GEOID = as.character(inter$GEOID[keep]),
        overlap_fraction = frac[keep]
      )
    }
  }
  res <- dplyr::bind_rows(out)
  if (nrow(res) == 0L) {
    return(dplyr::tibble(coord_id = character(), band = integer(),
                         GEOID = character(), overlap_fraction = numeric()))
  }
  # A given (coord_id, band, GEOID) can appear as several intersection fragments
  # (multipart geometry) — sum them, cap at 1.
  res <- dplyr::summarise(
    dplyr::group_by(res, coord_id, band, GEOID),
    overlap_fraction = min(sum(overlap_fraction), 1),
    .groups = "drop"
  )
  res
}

#' Provider supply per origin for one (subspecialty, year) cell.
#'
#' Supply S_j = the count of active subspecialists located at origin `coord_id`
#' in the given year. Reads the per-(npi, year) temporal panel
#' (`step_3_year_coord_map.rds`), which already carries `coord_id`, and joins the
#' cohort to resolve the canonical subspecialty code.
#'
#' Placeholder rows (`match_source` NA) are dropped — they are not real
#' locations (CLAUDE.md #19, Trust-a-Number / provenance).
#'
#' @param year_coord_map tibble with at least `npi`, `analysis_year`, `coord_id`,
#'   `match_source`.
#' @param cohort tibble with `npi` and a subspecialty column
#'   (`subspecialty_normalized`, values like "GO","MFM",...).
#' @param subspecialty_code Canonical short code to select (e.g. "GO").
#' @param year Analysis year (integer).
#' @param subspec_col Name of the subspecialty column in `cohort`
#'   (default "subspecialty_normalized").
#' @return tibble with `coord_id` and `supply` (integer count of distinct NPIs),
#'   only origins with supply > 0.
#' @references Supply S_j is the provider term of step 1 in Luo & Wang (2003)
#'   doi:10.1068/b29120 [source 1]. The per-(npi, year) panel realizes the
#'   temporal-2SFCA design of Paul & Edwards (2019) doi:10.1002/hpm.2667
#'   [source 9]: the cohort inside each year's catchments varies by year. Dropping
#'   match_source = NA placeholder rows enforces CLAUDE.md #19 (Trust-a-Number):
#'   a non-real location must never inflate supply.
#' @family E2SFCA computation
#' @seealso [compute_e2sfca]
#' @export
compute_provider_supply <- function(year_coord_map, cohort, subspecialty_code,
                                    year, subspec_col = "subspecialty_normalized") {
  checkmate::assert_subset(c("npi", "analysis_year", "coord_id", "match_source"),
                           names(year_coord_map))
  checkmate::assert_subset(c("npi", subspec_col), names(cohort))
  checkmate::assert_int(as.integer(year))

  if (!subspec_col %in% names(cohort)) {
    stop(sprintf("compute_provider_supply: cohort lacks column '%s'.", subspec_col),
         call. = FALSE)
  }
  cohort_sel <- dplyr::distinct(
    cohort[!is.na(cohort[[subspec_col]]) &
             cohort[[subspec_col]] == subspecialty_code, , drop = FALSE],
    npi
  )

  panel <- dplyr::filter(
    year_coord_map,
    analysis_year == as.integer(year),
    !is.na(match_source),            # drop placeholder (non-real) locations
    !is.na(coord_id)
  )
  panel <- dplyr::semi_join(panel, cohort_sel, by = "npi")

  supply <- dplyr::summarise(
    dplyr::group_by(panel, coord_id = as.character(coord_id)),
    supply = dplyr::n_distinct(npi),
    .groups = "drop"
  )
  dplyr::filter(supply, supply > 0)
}

#' Core E2SFCA computation for one (subspecialty, year) cell.
#'
#' Given the year-agnostic overlap table, the year's tract population, and the
#' cell's provider supply, compute:
#'   Step 1 — provider-to-population ratio  R_j = S_j / Sum_b w'_b * CumPop_jb
#'   Step 2 — tract accessibility            A_i = Sum_j Sum_b w'_b * R_j * f_jbi
#' where f_jbi = fraction of tract i within provider j's cumulative band b, and
#' w'_b are incremental band weights. (See module header for the ring equivalence.)
#'
#' @param overlap tibble from [compute_band_tract_overlap] (`coord_id`,`band`,
#'   `GEOID`,`overlap_fraction`).
#' @param tract_pop tibble with `GEOID` and a population column for the year.
#' @param supply tibble from [compute_provider_supply] (`coord_id`,`supply`).
#' @param weights Cumulative-band weights (see [e2sfca_band_weights]).
#' @param step2_power Exponent applied to the step-2 demand weights (default 1,
#'   the standard E2SFCA). Values above 1 sharpen distance decay in the
#'   demand-side sum; this is the M2SFCA-style sensitivity lever.
#' @param pop_col Name of the population column in `tract_pop` (default
#'   "female_pop").
#' @param per_capita_scale Multiply the accessibility index by this (default
#'   1e5 → "subspecialists per 100,000 women").
#' @return list with:
#'   * `access` — tibble(`GEOID`, `access`, `access_scaled`,
#'     `n_providers`) accessibility per tract.
#'   * `provider_ratios` — tibble(`coord_id`,`supply`,`weighted_demand`,`ratio`).
#'   * `weights` — the incremental weights used.
#' @references The two-step supply-ratio then demand-accumulation structure is
#'   Luo & Wang (2003) doi:10.1068/b29120 [source 1]; the zonal decay in both
#'   steps is Luo & Qi (2009) doi:10.1016/j.healthplace.2009.06.002 [source 2].
#'   The `step2_power` argument selects E2SFCA (1) vs M2SFCA (2, Delamater 2013
#'   doi:10.1016/j.healthplace.2013.07.012 [source 3]). Zero-weighted-demand
#'   providers yield ratio = NA (undefined), never 0, per the manuscript's
#'   zero-demand convention (see the `$audit` block and eMethods S4).
#' @family E2SFCA computation
#' @seealso [compute_band_tract_overlap], [compute_provider_supply], [compute_e2sfca_raster]
#' @export
compute_e2sfca <- function(overlap, tract_pop, supply,
                           weights = E2SFCA_DEFAULT_WEIGHTS,
                           step2_power = 1,
                           pop_col = "female_pop",
                           per_capita_scale = 1e5) {
  checkmate::assert_subset(c("coord_id", "band", "GEOID", "overlap_fraction"),
                           names(overlap))
  checkmate::assert_subset(c("GEOID", pop_col), names(tract_pop))
  checkmate::assert_subset(c("coord_id", "supply"), names(supply))
  checkmate::assert_number(step2_power, lower = 1)

  # Step-1 (demand denominator) ALWAYS uses ordinary E2SFCA increments (power 1).
  # Step-2 (access surface) uses power `step2_power`: 1 = E2SFCA, 2 = M2SFCA
  # (Delamater 2013), whose access increments are diff(W^2), NOT diff(W)^2.
  inc_d <- e2sfca_incremental_weights(weights, step2_power = 1)
  inc_a <- e2sfca_incremental_weights(weights, step2_power = step2_power)
  wtab <- dplyr::tibble(band = as.integer(names(inc_d)),
                        w_inc = as.numeric(inc_d), w_acc = as.numeric(inc_a))

  pop <- dplyr::transmute(
    tract_pop,
    GEOID = as.character(GEOID),
    pop = as.numeric(.data[[pop_col]])
  )
  pop$pop[is.na(pop$pop)] <- 0

  # Restrict overlap to active providers (supply > 0): providers with no
  # supply contribute R_j = 0 and cannot affect any tract's access.
  base <- dplyr::inner_join(
    dplyr::mutate(overlap, coord_id = as.character(coord_id),
                  GEOID = as.character(GEOID)),
    dplyr::mutate(supply, coord_id = as.character(coord_id)),
    by = "coord_id"
  )
  base <- dplyr::inner_join(base, wtab, by = "band")
  base <- dplyr::left_join(base, pop, by = "GEOID")
  base$pop[is.na(base$pop)] <- 0

  # Per (coord_id, band, GEOID) weighted contribution terms (demand + access).
  base <- dplyr::mutate(base, wf = w_inc * overlap_fraction,
                        wf_a = w_acc * overlap_fraction)

  # ---- Step 1: provider-to-population ratio R_j (demand weights) ------------
  wdem <- dplyr::summarise(
    dplyr::group_by(base, coord_id),
    weighted_demand = sum(wf * pop),
    .groups = "drop"
  )
  # Every POSITIVE-SUPPLY origin appears, even one that reaches no modeled demand
  # (its isochrone covers only zero-population tracts). ratio = supply / demand is
  # UNDEFINED when demand == 0; report ratio = NA (not 0, which would read as
  # "zero capacity"), use ratio_for_surface = 0 so it adds no modeled access, and
  # account its supply as excluded.
  demand <- dplyr::left_join(
    dplyr::mutate(supply, coord_id = as.character(coord_id)), wdem, by = "coord_id")
  demand$weighted_demand[is.na(demand$weighted_demand)] <- 0
  demand <- dplyr::mutate(
    demand,
    zero_demand       = weighted_demand <= 0,
    ratio             = dplyr::if_else(weighted_demand > 0, supply / weighted_demand, NA_real_),
    ratio_for_surface = dplyr::if_else(weighted_demand > 0, supply / weighted_demand, 0),
    excluded_supply   = dplyr::if_else(weighted_demand > 0, 0, supply)
  )

  # ---- Step 2: tract accessibility A_i (access weights; == demand unless M2SFCA)
  step2 <- dplyr::inner_join(
    base[, c("coord_id", "GEOID", "wf_a")],
    demand[, c("coord_id", "ratio_for_surface")],
    by = "coord_id"
  )
  access <- dplyr::summarise(
    dplyr::group_by(step2, GEOID),
    access = sum(wf_a * ratio_for_surface),
    n_providers = dplyr::n_distinct(coord_id[ratio_for_surface > 0]),
    .groups = "drop"
  )

  supply_total <- sum(demand$supply, na.rm = TRUE)
  audit <- list(
    n_zero_demand_origins    = sum(demand$zero_demand),
    supply_zero_demand       = sum(demand$supply[demand$zero_demand]),
    share_supply_zero_demand = if (supply_total > 0)
      sum(demand$supply[demand$zero_demand]) / supply_total else 0,
    zero_demand_coord_ids    = demand$coord_id[demand$zero_demand]
  )

  # Tracts touched by no active provider have access 0 (append them so every
  # tract present in tract_pop gets a row).
  all_tracts <- dplyr::distinct(pop, GEOID)
  access <- dplyr::left_join(all_tracts, access, by = "GEOID")
  access$access[is.na(access$access)] <- 0
  access$n_providers[is.na(access$n_providers)] <- 0L
  access <- dplyr::mutate(access, access_scaled = access * per_capita_scale)

  list(
    access = dplyr::arrange(
      access[, c("GEOID", "access", "access_scaled", "n_providers")], GEOID),
    provider_ratios = dplyr::arrange(
      demand[, c("coord_id", "supply", "weighted_demand", "ratio",
                 "ratio_for_surface", "zero_demand", "excluded_supply")], coord_id),
    audit = audit,
    weights = inc_d,
    method = if (step2_power == 1) "E2SFCA" else "M2SFCA",
    step2_power = step2_power,
    band_weights = e2sfca_band_weights(weights),
    step1_incremental_weights = inc_d,
    step2_incremental_weights = inc_a,
    maximum_travel_time = max(as.integer(names(e2sfca_band_weights(weights))))
  )
}

# ==============================================================================
# RASTER ENGINE (exactextractr / terra) — production-scale equivalent of the
# vector path above. Same estimand (area-weighted E2SFCA), ~10-30x faster at
# national scale because every geometry op is C++ raster work, not
# st_intersection over millions of polygon pairs. Discretization at `resolution`
# metres is the only difference from the exact vector result.
#
# Estimand equivalence (why raster "mean" reproduces the vector formula):
#   Step 1 : CumPop_jb = sum over cells of pop(cell) * coverage(cell, iso_jb)
#            = sum_i pop_i * f_jbi         (pop spread uniformly within a tract)
#   Step 2 : build access surface S(cell) = sum_{j,b} w'_b * R_j * [cell in iso_jb]
#            A_i = mean of S over tract i's cells
#                = sum_{j,b} w'_b * R_j * (cells of i in iso_jb / cells of i)
#                = sum_{j,b} w'_b * R_j * f_jbi     — the vector accessibility.
# ==============================================================================

#' Build the per-year raster grid context reused across all subspecialties.
#'
#' Rasterizes tract population once so the 7 subspecialty cells of a given year
#' share it. Returns a terra SpatRaster of per-cell population plus the tract sf
#' (for the Step-2 zonal mean) and metadata.
#'
#' @param tracts_pop_sf `sf` with `GEOID`, a population column, and polygon
#'   geometry (one year's tracts).
#' @param pop_col Population column name (default "female_pop").
#' @param area_crs Equal-area EPSG (default [E2SFCA_AREA_CRS], 5070).
#' @param resolution Cell size in metres (default 250, matching Step 4).
#' @return list(pop_rast, tracts, template, pop_col, resolution).
#' @family E2SFCA raster grid
#' @export
build_e2sfca_raster_grid <- function(tracts_pop_sf, pop_col = "female_pop",
                                     area_crs = E2SFCA_AREA_CRS, resolution = 250) {
  checkmate::assert_class(tracts_pop_sf, "sf")
  checkmate::assert_subset(c("GEOID", pop_col), names(tracts_pop_sf))
  geom <- build_e2sfca_grid_geometry(tracts_pop_sf, area_crs = area_crs,
                                     resolution = resolution)
  pop_vals <- dplyr::tibble(GEOID = as.character(tracts_pop_sf$GEOID),
                            .pop = as.numeric(tracts_pop_sf[[pop_col]]))
  attach_e2sfca_population(geom, pop_vals, pop_col = pop_col, pop_val_col = ".pop")
}

#' Year-agnostic half of the raster grid: rasterize tract geometry once.
#'
#' Tract boundaries change only at the 2010->2020 vintage break, so this
#' (expensive) rasterization is computed once per vintage and reused across all
#' its years via [attach_e2sfca_population].
#'
#' @param tracts_geom_sf `sf` with `GEOID` + polygon geometry.
#' @param area_crs Equal-area EPSG (default [E2SFCA_AREA_CRS]).
#' @param resolution Cell size in metres.
#' @param template Optional existing `SpatRaster` to rasterize onto. `NULL`
#'   (default) builds a fresh template from `tracts_geom_sf` at `resolution`;
#'   pass one to force an identical grid across vintages.
#' @return list(template, tracts (with `.tid`,`.ncell`), area_crs, resolution).
#' @family E2SFCA raster grid
#' @seealso [allocate_pop_areaweighted]
#' @export
build_e2sfca_grid_geometry <- function(tracts_geom_sf,
                                       area_crs = E2SFCA_AREA_CRS, resolution = 250,
                                       template = NULL) {
  checkmate::assert_class(tracts_geom_sf, "sf")
  checkmate::assert_subset("GEOID", names(tracts_geom_sf))
  tr <- sf::st_transform(tracts_geom_sf, area_crs)
  tr <- sf::st_make_valid(tr)
  if (any(sf::st_geometry_type(tr) == "GEOMETRYCOLLECTION")) {
    tr <- suppressWarnings(sf::st_collection_extract(tr, "POLYGON"))
  }
  n_empty <- sum(sf::st_is_empty(tr))
  if (n_empty > 0L) {
    warning(sprintf("build_e2sfca_grid_geometry: dropping %d empty tract geometr%s.",
                    n_empty, ifelse(n_empty == 1L, "y", "ies")), call. = FALSE)
    tr <- tr[!sf::st_is_empty(tr), , drop = FALSE]
  }
  tr$GEOID <- as.character(tr$GEOID)
  # A caller-supplied `template` forces a COMMON cell-aligned grid across several
  # tract sets (e.g. seam test: 2010 vs 2020 on identical cells). Otherwise the
  # template is the tracts' own extent.
  if (is.null(template)) {
    template <- terra::rast(terra::ext(terra::vect(tr)), resolution = resolution,
                            crs = sprintf("EPSG:%d", area_crs))
  } else {
    template <- terra::rast(template); terra::values(template) <- NA_real_
  }
  tr$.tid <- seq_len(nrow(tr))
  tid_rast <- terra::rasterize(terra::vect(tr), template, field = ".tid")
  cell_counts <- as.data.frame(terra::freq(tid_rast))          # value=tid, count
  cc <- stats::setNames(cell_counts$count, as.character(cell_counts$value))
  tr$.ncell <- as.numeric(cc[as.character(tr$.tid)])
  tr$.ncell[is.na(tr$.ncell) | tr$.ncell == 0] <- NA_real_     # too small to hit a cell centre
  list(template = template, tracts = tr, area_crs = area_crs, resolution = resolution)
}

#' Mass-conserving tract-to-grid population allocation (area-weighted).
#'
#' Center-based rasterization (assign a cell to whichever tract covers its
#' centre) DROPS the population of any tract too small to contain a cell centre,
#' and more generally does not conserve each tract's population locally. At a
#' 500 m CONUS grid this silently lost ~1% of ACS female population and made the
#' represented national total *vintage-dependent* (2010 vs 2020 tract sets lose
#' different amounts), which confounds the seam test: an apparent access shift
#' can be a pure change in total demand rather than spatial redistribution.
#'
#' This allocator instead splits each tract's population across every template
#' cell it intersects, weighted by intersection area:
#' \deqn{w_{ic} = A_{ic} / \sum_h A_{ih}, \quad p_{ic} = P_i w_{ic}, \quad p_c = \sum_i p_{ic}}
#' where \eqn{A_{ic}} is the area of overlap between tract \eqn{i} and cell
#' \eqn{c} (from `exactextractr::exact_extract(coverage_area = TRUE)`, planar in
#' the equal-area CRS). Guarantees, verified numerically here:
#' \itemize{
#'   \item \eqn{\sum_c p_{ic} = P_i} for every tract (per-tract conservation);
#'   \item \eqn{\sum_c p_c = \sum_i P_i} (global conservation);
#'   \item sub-cell tracts and slivers keep ALL their population;
#'   \item a tract with zero valid overlap FAILS LOUDLY rather than dropping pop.
#' }
#'
#' @param template terra SpatRaster defining the target grid (values ignored).
#' @param tracts `sf` polygons in the template CRS (equal-area).
#' @param pop numeric vector, `length == nrow(tracts)`, per-tract population.
#' @param conservation_tol Max allowed relative per-tract allocation error
#'   before this function `stop()`s (default 1e-6).
#' @return terra SpatRaster of per-cell population `p_c` (background 0).
#' @references Apparicio et al. (2017) doi:10.1186/s12942-017-0105-9 [source 7]
#'   documents the population-AGGREGATION error that centroid assignment incurs in
#'   potential-access measures; this area-weighted, mass-conserving allocation is
#'   the remedy the manuscript adopts (recovers the ~1.06% of the female
#'   population that centroid allocation drops). Frozen facts (allocator sha256,
#'   500 m EPSG:5070, conservation tolerance) are in
#'   docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md.
#' @family E2SFCA raster grid
#' @seealso [build_e2sfca_grid_geometry], [attach_e2sfca_population]
#' @export
allocate_pop_areaweighted <- function(template, tracts, pop,
                                       conservation_tol = 1e-6) {
  checkmate::assert_class(tracts, "sf")
  stopifnot(length(pop) == nrow(tracts))
  pop <- as.numeric(pop); pop[is.na(pop)] <- 0
  if (any(pop < 0)) {
    stop("allocate_pop_areaweighted: negative source population is not allowed.",
         call. = FALSE)
  }
  # Per-tract coverage of each intersecting template cell, as PLANAR AREA (m^2 in
  # the equal-area CRS). include_cell -> global (row-major, 1-based) cell index.
  # exact_extract requires an initialized raster; the values themselves are
  # irrelevant here (we only use coverage_area + cell index).
  # CHUNKED: at national 500 m the full per-tract coverage list is many GB; we
  # process tracts in batches and accumulate into the per-cell vector, bounding
  # peak memory to one batch regardless of tract count.
  tmpl <- terra::rast(template)
  if (!terra::hasValues(tmpl)) terra::values(tmpl) <- 0
  n <- nrow(tracts)
  acc <- numeric(terra::ncell(template))     # per-cell population accumulator p_c
  tract_alloc <- numeric(n)                  # per-tract allocated total (audit)
  batch <- getOption("e2sfca_alloc_batch", 4000L)

  for (s in seq.int(1L, n, by = batch)) {
    idx  <- s:min(s + batch - 1L, n)
    popc <- pop[idx]
    ex <- exactextractr::exact_extract(
      tmpl, tracts[idx, ], include_cell = TRUE, coverage_area = TRUE, progress = FALSE)
    lens <- vapply(ex, nrow, integer(1))

    bad_empty <- which(lens == 0L & popc > 0)          # would silently drop pop
    if (length(bad_empty)) {
      stop(sprintf(
        "allocate_pop_areaweighted: tract with population has zero template overlap (GEOID %s, pop %.1f); refusing to drop population. Ensure the template covers every tract.",
        tracts$GEOID[idx][bad_empty[1]], popc[bad_empty[1]]), call. = FALSE)
    }
    cell  <- unlist(lapply(ex, `[[`, "cell"), use.names = FALSE)
    area  <- unlist(lapply(ex, `[[`, "coverage_area"), use.names = FALSE)
    locid <- rep.int(seq_along(ex), lens)              # tract index WITHIN batch
    if (any(!is.finite(area)) || any(area < 0)) {
      stop("allocate_pop_areaweighted: non-finite or negative overlap area from exact_extract; invalid geometry.",
           call. = FALSE)
    }
    tot <- vapply(split(area, locid), sum, numeric(1))
    present <- as.integer(names(tot))
    bad_zero <- present[tot[as.character(present)] <= 0 & popc[present] > 0]
    if (length(bad_zero)) {
      stop(sprintf(
        "allocate_pop_areaweighted: tract with population has zero total overlap area (GEOID %s); zero-area/invalid intersection must fail, not drop population.",
        tracts$GEOID[idx][bad_zero[1]]), call. = FALSE)
    }
    contrib <- popc[locid] * (area / tot[as.character(locid)])
    pbc <- vapply(split(contrib, cell), sum, numeric(1))
    cells <- as.integer(names(pbc))
    acc[cells] <- acc[cells] + as.numeric(pbc)         # accumulate across batches
    abt <- vapply(split(contrib, locid), sum, numeric(1))
    tract_alloc[idx[as.integer(names(abt))]] <- as.numeric(abt)
    rm(ex, cell, area, locid, contrib, pbc);
  }

  # --- conservation audit (per-tract and global) ---
  rel_err <- abs(tract_alloc - pop) / pmax(pop, 1)
  worst <- if (length(rel_err)) max(rel_err) else 0
  if (worst > conservation_tol) {
    j <- which.max(rel_err)
    stop(sprintf(
      "allocate_pop_areaweighted: per-tract conservation error %.3e > tol %.1e (tract %d GEOID %s: allocated %.4f vs pop %.4f).",
      worst, conservation_tol, j, tracts$GEOID[j], tract_alloc[j], pop[j]),
      call. = FALSE)
  }
  global_rel <- abs(sum(acc) - sum(pop)) / max(sum(pop), 1)
  if (global_rel > conservation_tol) {
    stop(sprintf("allocate_pop_areaweighted: global conservation error %.3e > tol %.1e (allocated %.2f vs source %.2f).",
                 global_rel, conservation_tol, sum(acc), sum(pop)), call. = FALSE)
  }

  pr <- terra::rast(template)
  terra::values(pr) <- acc
  pr
}

#' Per-year half of the raster grid: attach population and rasterize demand.
#'
#' @param grid_geom Output of [build_e2sfca_grid_geometry] (cached per vintage).
#' @param pop_vals data.frame/tibble with `GEOID` and a population column.
#' @param pop_col Name to record as the grid's population column.
#' @param pop_val_col Name of the population column in `pop_vals`
#'   (default = `pop_col`).
#' @param alloc Allocation method: `"area"` (default; mass-conserving
#'   area-weighted via [allocate_pop_areaweighted]) or `"center"` (legacy
#'   center-based rasterization, retained only for the vintage-seam sensitivity
#'   comparison — NOT mass-conserving).
#' @param conservation_tol Passed to [allocate_pop_areaweighted] (area mode).
#' @return list(pop_rast, tracts, template, pop_col, resolution, area_crs, alloc).
#' @family E2SFCA raster grid
#' @seealso [build_e2sfca_grid_geometry], [allocate_pop_areaweighted]
#' @export
attach_e2sfca_population <- function(grid_geom, pop_vals, pop_col = "female_pop",
                                     pop_val_col = pop_col,
                                     alloc = c("area", "center"),
                                     conservation_tol = 1e-6) {
  alloc <- match.arg(alloc)
  checkmate::assert_list(grid_geom)
  checkmate::assert_subset(c("GEOID", pop_val_col), names(pop_vals))
  tr <- grid_geom$tracts
  lu <- stats::setNames(as.numeric(pop_vals[[pop_val_col]]), as.character(pop_vals$GEOID))
  tr$.pop <- as.numeric(lu[tr$GEOID]); tr$.pop[is.na(tr$.pop)] <- 0

  if (alloc == "center") {
    # Legacy: uniform over cells whose CENTRE falls in the tract (drops sub-cell
    # tracts, non-conserving). Kept ONLY for the seam sensitivity artifact.
    tr$.dens <- tr$.pop / tr$.ncell
    tr$.dens[is.na(tr$.dens)] <- 0
    pop_rast <- terra::rasterize(terra::vect(tr), grid_geom$template,
                                 field = ".dens", background = 0)
  } else {
    pop_rast <- allocate_pop_areaweighted(grid_geom$template, tr, tr$.pop,
                                          conservation_tol = conservation_tol)
  }
  list(pop_rast = pop_rast, tracts = tr, template = grid_geom$template,
       pop_col = pop_col, resolution = grid_geom$resolution,
       area_crs = grid_geom$area_crs, alloc = alloc)
}

#' Prepare isochrones for the raster engine ONCE (hoist out of the cell loop).
#'
#' The transform to the equal-area CRS and `st_make_valid` over thousands of
#' large isochrone polygons is the single most expensive per-call step; running
#' it once here instead of inside every [compute_e2sfca_raster] call turns an
#' O(cells x polygons) cost into O(polygons).
#'
#' @param iso_sf `sf` with `coord_id`, `drive_time_minutes`, polygon geometry.
#' @param area_crs Equal-area EPSG (default [E2SFCA_AREA_CRS]).
#' @return list(bands = named list of per-band `sf` (`coord_id`, geometry),
#'   area_crs). Pass this as the `iso` argument to [compute_e2sfca_raster].
#' @family E2SFCA raster grid
#' @seealso [compute_e2sfca_raster]
#' @export
prepare_e2sfca_iso <- function(iso_sf, area_crs = E2SFCA_AREA_CRS) {
  checkmate::assert_class(iso_sf, "sf")
  checkmate::assert_subset(c("coord_id", "drive_time_minutes"), names(iso_sf))
  iso <- sf::st_transform(iso_sf, area_crs)
  iso <- sf::st_make_valid(iso)
  iso <- iso[!sf::st_is_empty(iso), , drop = FALSE]
  if (any(sf::st_geometry_type(iso) == "GEOMETRYCOLLECTION")) {
    iso <- suppressWarnings(sf::st_collection_extract(iso, "POLYGON"))
  }
  iso$coord_id <- as.character(iso$coord_id)
  iso$band <- as.integer(round(iso$drive_time_minutes))
  bands <- sort(unique(iso$band))
  band_list <- lapply(bands, function(b) iso[iso$band == b, "coord_id", drop = FALSE])
  names(band_list) <- as.character(bands)
  list(bands = band_list, area_crs = area_crs)
}

#' Default access thresholds (in per-100k units) for cell-level population shares.
#' @export
E2SFCA_DEFAULT_THRESHOLDS <- c(0, 1, 5, 10, 20, 50)

#' Authoritative cell-level national summaries from the access surface.
#'
#' Computes the national population-weighted mean access and the population
#' share at each access threshold DIRECTLY from the aligned cell grids — never
#' by recombining tract averages (which would not be partition-robust). One
#' explicit valid-cell mask governs every summary so the denominator never
#' silently changes between metrics.
#'
#' Valid cell = finite access AND finite, non-negative population, on matching
#' raster support. Excluded population (missing access, or missing/negative
#' population) is reported, not silently dropped.
#'
#' @param surface terra SpatRaster of access values S_c (raw ratio units).
#' @param pop_rast terra SpatRaster of per-cell population p_c (same support).
#' @param thresholds Numeric thresholds in the SCALED units (per `scale`).
#' @param scale Multiplier applied to S_c before thresholding / reporting
#'   (default 1e5 -> per-100k).
#' @return list with the mask accounting, national pop-weighted mean (raw and
#'   scaled), and a `threshold_shares` tibble.
#' @references The population-weighted national mean is the standardized supply-
#'   per-population index of Wang & Luo (2005) doi:10.1016/j.healthplace.2004.02.003
#'   [source 6]. Dividing each cell's access by this mean yields the Spatial
#'   Access Ratio (SPAR) of Wan, Zhan, Zou & Chow (2012)
#'   doi:10.1016/j.apgeog.2011.05.001 [source 4] (national mean == 1.00 by
#'   construction), attached downstream as `relative_access`.
#' @family E2SFCA computation
#' @seealso [compute_e2sfca_raster]
#' @export
e2sfca_cell_summaries <- function(surface, pop_rast,
                                  thresholds = E2SFCA_DEFAULT_THRESHOLDS,
                                  scale = 1e5) {
  if (!isTRUE(terra::compareGeom(surface, pop_rast, stopOnError = FALSE))) {
    stop("e2sfca_cell_summaries: surface and pop_rast must share CRS/extent/",
         "resolution/dimensions/origin.", call. = FALSE)
  }
  s <- terra::values(surface)[, 1]
  p <- terra::values(pop_rast)[, 1]

  # ---- one valid-cell mask for ALL summaries -------------------------------
  fin_s <- is.finite(s)
  fin_p <- is.finite(p) & p >= 0
  valid <- fin_s & fin_p
  pop_total_raster <- sum(p[is.finite(p) & p >= 0])          # all real population on the grid
  pop_excluded_missing_access <- sum(p[!fin_s & is.finite(p) & p >= 0])
  pop_excluded_missing_pop    <- sum(p[fin_s & !fin_p], na.rm = TRUE)  # ~0 by construction
  p_v <- p[valid]; s_v <- s[valid] * scale
  pop_valid_total <- sum(p_v)

  mean_pw_scaled <- if (pop_valid_total > 0) sum(p_v * s_v) / pop_valid_total else NA_real_
  shares <- vapply(thresholds, function(k) {
    if (pop_valid_total > 0) sum(p_v * (s_v >= k)) / pop_valid_total else NA_real_
  }, numeric(1))

  list(
    scale = scale,
    n_cells_total = length(s),
    n_cells_valid = sum(valid),
    pop_raster_total = pop_total_raster,
    pop_valid_total = pop_valid_total,
    pop_excluded_missing_access = pop_excluded_missing_access,
    pop_excluded_missing_pop = pop_excluded_missing_pop,
    mean_population_weighted = if (is.na(mean_pw_scaled)) NA_real_ else mean_pw_scaled / scale,
    mean_population_weighted_scaled = mean_pw_scaled,
    threshold_shares = dplyr::tibble(
      threshold = thresholds,
      pop_ge = vapply(thresholds, function(k) sum(p_v[s_v >= k]), numeric(1)),
      share_pop = shares)
  )
}

#' Raster E2SFCA for one (subspecialty, year) cell.
#'
#' @param grid Output of [build_e2sfca_raster_grid] (shared across subspecialties
#'   of the same year).
#' @param iso `sf` isochrones (`coord_id`, `drive_time_minutes`, geometry) — any
#'   CRS; re-projected internally — OR a prepared context from
#'   [prepare_e2sfca_iso] (hoist the transform/validate out of the cell loop).
#' @param supply tibble from [compute_provider_supply] (`coord_id`,`supply`).
#' @param weights Cumulative-band weights (see [e2sfca_band_weights]).
#' @param step2_power Exponent applied to the step-2 demand weights (default 1,
#'   the standard E2SFCA). See [compute_e2sfca].
#' @param per_capita_scale Multiplier for the index (default 1e5).
#' @param thresholds Access thresholds (scaled units) for cell-level pop shares.
#' @param return_surface Logical. `FALSE` (default) returns summaries only;
#'   `TRUE` additionally returns the full accessibility `SpatRaster`, which is
#'   large -- request it only when the surface itself is needed.
#' @return list(access, provider_ratios, weights, national). `access` carries
#'   BOTH `access_mean_area` (area-weighted, secondary) and
#'   `access_mean_population` (population-weighted, the authoritative tract
#'   value). `national` holds the cell-level authoritative headline summaries
#'   from [e2sfca_cell_summaries] — the sole source for headline estimates.
#' @references Raster realization of the same Luo & Wang (2003) [source 1] /
#'   Luo & Qi (2009) [source 2] two-step method as [compute_e2sfca], on the
#'   mass-conserving grid of [allocate_pop_areaweighted] (Apparicio 2017 [source
#'   7]); `step2_power` selects M2SFCA (Delamater 2013 [source 3]); the national
#'   block adds SPAR (Wan 2012 [source 4]). This is the PRODUCTION path used for
#'   the manuscript (docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md, engine = raster).
#' @family E2SFCA computation
#' @seealso [build_e2sfca_raster_grid], [prepare_e2sfca_iso], [compute_provider_supply], [e2sfca_cell_summaries]
#' @examples
#' \dontrun{
#' # End-to-end for one (subspecialty, year) cell (production = raster engine):
#' grid   <- build_e2sfca_raster_grid(tracts_pop_sf, pop_col = "female_pop")  # once per year
#' iso_p  <- prepare_e2sfca_iso(isochrones_sf)                                 # hoist transform
#' supply <- compute_provider_supply(year_coord_map, cohort, "GO", year = 2020)
#' res    <- compute_e2sfca_raster(grid, iso_p, supply,
#'                                 weights = E2SFCA_DEFAULT_WEIGHTS, step2_power = 1)
#' res$national$mean_population_weighted   # the authoritative headline number
#' res$access$relative_access              # per-tract SPAR (national mean = 1.00)
#' }
#' @export
compute_e2sfca_raster <- function(grid, iso, supply,
                                  weights = E2SFCA_DEFAULT_WEIGHTS,
                                  step2_power = 1,
                                  per_capita_scale = 1e5,
                                  thresholds = E2SFCA_DEFAULT_THRESHOLDS,
                                  return_surface = FALSE) {
  checkmate::assert_list(grid)
  checkmate::assert_subset(c("coord_id", "supply"), names(supply))
  checkmate::assert_number(step2_power, lower = 1)
  # Step-1 demand ALWAYS power 1; Step-2 access uses `step2_power` (2 = M2SFCA,
  # access increments = diff(W^2)).
  inc   <- e2sfca_incremental_weights(weights, step2_power = 1)
  inc_a <- e2sfca_incremental_weights(weights, step2_power = step2_power)

  # `iso` may be a raw sf (tests / one-off) or a prepared per-band context from
  # prepare_e2sfca_iso() (hoisted out of the loop so the expensive
  # transform + st_make_valid runs ONCE, not once per (subspecialty, year)).
  iso_ctx <- if (inherits(iso, "sf")) prepare_e2sfca_iso(iso, area_crs = grid$area_crs)
             else iso
  bands <- sort(intersect(as.integer(names(iso_ctx$bands)), as.integer(names(inc))))
  active <- as.character(supply$coord_id)

  # ---- Step 1: CumPop per (origin, band) -> R_j ----------------------------
  demand_parts <- list()
  for (b in bands) {
    iso_b <- iso_ctx$bands[[as.character(b)]]
    iso_b <- iso_b[iso_b$coord_id %in% active, , drop = FALSE]
    if (nrow(iso_b) == 0L) next
    cum <- exactextractr::exact_extract(grid$pop_rast, iso_b, "sum", progress = FALSE)
    demand_parts[[as.character(b)]] <- dplyr::tibble(
      coord_id = as.character(iso_b$coord_id), band = b, cum_pop = as.numeric(cum))
  }
  cumpop <- dplyr::bind_rows(demand_parts)
  cumpop <- dplyr::left_join(cumpop,
    dplyr::tibble(band = as.integer(names(inc)), w_inc = as.numeric(inc)), by = "band")
  wdem <- dplyr::summarise(dplyr::group_by(cumpop, coord_id),
                           weighted_demand = sum(w_inc * cum_pop), .groups = "drop")
  # Every positive-supply origin appears; zero reachable demand -> ratio NA,
  # ratio_for_surface 0 (adds no modeled access), supply accounted as excluded.
  demand <- dplyr::left_join(
    dplyr::mutate(supply, coord_id = as.character(coord_id)), wdem, by = "coord_id")
  demand$weighted_demand[is.na(demand$weighted_demand)] <- 0
  demand <- dplyr::mutate(demand,
    zero_demand       = weighted_demand <= 0,
    ratio             = dplyr::if_else(weighted_demand > 0, supply / weighted_demand, NA_real_),
    ratio_for_surface = dplyr::if_else(weighted_demand > 0, supply / weighted_demand, 0),
    excluded_supply   = dplyr::if_else(weighted_demand > 0, 0, supply))
  supply_total <- sum(demand$supply, na.rm = TRUE)
  audit <- list(
    n_zero_demand_origins    = sum(demand$zero_demand),
    supply_zero_demand       = sum(demand$supply[demand$zero_demand]),
    share_supply_zero_demand = if (supply_total > 0)
      sum(demand$supply[demand$zero_demand]) / supply_total else 0,
    zero_demand_coord_ids    = demand$coord_id[demand$zero_demand])

  # ---- Step 2: access surface S -> zonal mean per tract --------------------
  ratio_lu <- stats::setNames(demand$ratio_for_surface, demand$coord_id)
  surface <- grid$template
  terra::values(surface) <- 0
  for (b in bands) {
    iso_b <- iso_ctx$bands[[as.character(b)]]
    iso_b <- iso_b[iso_b$coord_id %in% active, , drop = FALSE]
    if (nrow(iso_b) == 0L) next
    iso_b$fld <- as.numeric(inc_a[as.character(b)]) * as.numeric(ratio_lu[iso_b$coord_id])
    iso_b$fld[is.na(iso_b$fld)] <- 0
    rb <- terra::rasterize(terra::vect(iso_b), grid$template, field = "fld",
                           fun = "sum", background = 0)
    surface <- surface + rb
  }
  # ---- Tract values: BOTH area-weighted (secondary) and population-weighted --
  # (authoritative tract value). Population weights are the SAME pop_rast used
  # for the national headline, so pop-weighted tract means recombine exactly to
  # the cell-level national mean (see e2sfca_cell_summaries + tests).
  acc_area <- exactextractr::exact_extract(surface, grid$tracts, "mean",
                                           progress = FALSE)
  acc_pop  <- exactextractr::exact_extract(surface, grid$tracts, "weighted_mean",
                                           weights = grid$pop_rast, progress = FALSE)
  access <- dplyr::tibble(
    GEOID = grid$tracts$GEOID,
    access_mean_area = as.numeric(acc_area),
    access_mean_population = as.numeric(acc_pop))
  # Keep undefined tract values as NA (never coerce to 0): "no calculable raster
  # coverage" / "undefined zonal mean" is not "zero access", even for the
  # secondary area-weighted map layer or the pop-weighted value of an empty tract.
  access$access_mean_population[is.nan(access$access_mean_population)] <- NA_real_
  access <- dplyr::mutate(access,
    access_mean_area_per100k = access_mean_area * per_capita_scale,
    access_mean_population_per100k = access_mean_population * per_capita_scale,
    n_providers = NA_integer_)

  # ---- Authoritative national cell-level headline summaries ------------------
  national <- e2sfca_cell_summaries(surface, grid$pop_rast,
                                    thresholds = thresholds, scale = per_capita_scale)

  list(
    access = dplyr::arrange(access[, c("GEOID", "access_mean_area",
      "access_mean_population", "access_mean_area_per100k",
      "access_mean_population_per100k", "n_providers")], GEOID),
    provider_ratios = dplyr::arrange(
      demand[, c("coord_id", "supply", "weighted_demand", "ratio",
                 "ratio_for_surface", "zero_demand", "excluded_supply")], coord_id),
    audit = audit,
    weights = inc,
    method = if (step2_power == 1) "E2SFCA" else "M2SFCA",
    step2_power = step2_power,
    band_weights = e2sfca_band_weights(weights),
    step1_incremental_weights = inc,
    step2_incremental_weights = inc_a,
    maximum_travel_time = max(as.integer(names(e2sfca_band_weights(weights)))),
    national = national,
    surface = if (isTRUE(return_surface)) surface else NULL
  )
}
