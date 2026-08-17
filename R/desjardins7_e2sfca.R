# ==============================================================================
# desjardins7_e2sfca.R
# ------------------------------------------------------------------------------
# Pure, dependency-light core of the tract-centroid E2SFCA re-implementation that
# backs the seven-subspecialty Desjardins recreation (scripts/desjardins7/{06,09,
# 13}). Those scripts inline the same band-weight math, demand/supply/access
# recurrence, coord_id parse, CONUS gate, and quintile assignment; the copies
# drift and cannot be unit-tested. This file is the single source of truth for
# that math, extracted so the semantic + adversarial suite
# (tests/testthat/test-desjardins7-*.R) can guard it.
#
# Design rules:
#   * base R only (no sf/dplyr) so the functions are fast and testable in
#     isolation and can be reasoned about against hand-computed fixtures;
#   * every function is total: pathological input (zero supply, unreachable
#     tract, empty band, NA demand, malformed coord_id) returns a defined value,
#     never an error, matching the production scripts' fail-soft behaviour;
#   * the numeric results reproduce the inline implementations exactly.
#
# References: CLAUDE.md #16 (subspecialty source of truth — GO absorbs CRI +
# Hospice/Palliative), CLAUDE.md #17 (5-km cluster geometry).
# ==============================================================================

# ---- canonical constants -----------------------------------------------------

#' Display order of the seven OB/GYN subspecialties.
#' @export
# SSOT anchor (E2SFCA_SUBSPECIALTIES): identical set + order to the canonical in
# scripts/manuscript_e2sfca_values.R; literal retained so this module stays base-R
# and standalone. Set-membership enforced by tests/testthat/test-ssot-subspecialties.R.
DJ7_SUBS <- c("MFM", "GO", "REI", "FPMRS", "MIGS", "PAG", "CFP")

#' Isochrone travel-time bands (minutes).
#' @export
# SSOT anchor (CANONICAL_BANDS): the drive-time bands below are the canonical set defined in R/contour_bands.R (CANONICAL_BANDS = c(30L, 60L, 120L, 180L)); literal retained for standalone execution.
DJ7_BANDS <- c(30L, 60L, 120L, 180L)

#' Primary cumulative Gaussian band weights (30/60/120/180 min).
#' @export
# SSOT anchor (E2SFCA_DEFAULT_WEIGHTS): identical to the engine's canonical weights
# in R/two_step_floating_catchment.R; the literal is retained so this module stays
# base-R and testable in isolation. Equality is enforced by
# tests/testthat/test-ssot-band-weights.R.
DJ7_WC_BASE <- c(`30` = 1.00, `60` = 0.68, `120` = 0.22, `180` = 0.09)

#' Board-certification subspecialty name -> analysis code.
#'
#' Gynecologic Oncology absorbs the CRI and Hospice/Palliative certifications
#' (CLAUDE.md #16); every physician maps to exactly one code.
#' @export
DJ7_NAME2CODE <- c(
  "Gynecologic Oncology" = "GO", "CRI" = "GO",
  "Hospice and Palliative Medicine" = "GO",
  "Maternal-Fetal Medicine" = "MFM",
  "Reproductive Endocrinology and Infertility" = "REI",
  "Female Pelvic Medicine & Reconstructive Surgery" = "FPMRS",
  "MIG" = "MIGS",
  "Pediatric & Adolescent Gynecology" = "PAG",
  "Complex Family Planning" = "CFP")

# ---- band-weight math --------------------------------------------------------

#' Incremental band weights for the E2SFCA demand step.
#'
#' \eqn{w'_b = W_b - W_{b+1}} for every band except the outermost, where
#' \eqn{w'_{last} = W_{last}}. The demand assigned to an origin is
#' \eqn{D_j = \sum_b w'_b \cdot \mathrm{cumpop}_b(j)} over the NESTED cumulative
#' isochrone populations, which telescopes back to the cumulative weights used
#' for the access step. Guards the historical "mangled name" bug: writing
#' `c(\`30\` = Wc["30"] - Wc["60"])` inherited the name "30" from the RHS and
#' produced the label "30.30", so `Wi[["30"]]` failed. Here the values are
#' stripped of names before relabelling.
#' @param Wc length-4 cumulative band weights (names are the band minutes).
#' @return length-4 numeric, names = `names(Wc)`, values un-mangled.
#' @export
dj7_incr_weights <- function(Wc) {
  stopifnot(length(Wc) == 4L)
  v <- unname(as.numeric(Wc))
  stats::setNames(c(v[1] - v[2], v[2] - v[3], v[3] - v[4], v[4]), names(Wc))
}

# ---- weighted mean (matches scripts' `wm`) -----------------------------------

#' Population-weighted mean over positive weights.
#'
#' Reproduces the `wm()` helper in scripts 06/09/13: it sums over elements with
#' strictly-positive, non-NA weight. For non-negative finite weights this equals
#' [accessibility_stratification::weighted_mean_all] (zero-weight elements
#' contribute nothing to either numerator or denominator); the suite asserts
#' that equivalence so the two libraries cannot silently diverge.
#' @param x numeric values.
#' @param w numeric weights (same length).
#' @return weighted mean, or NA if no positive weight remains.
#' @export
dj7_wmean <- function(x, w) {
  stopifnot(length(x) == length(w))
  ok <- w > 0 & !is.na(w)
  sw <- sum(w[ok])
  if (!is.finite(sw) || sw <= 0) return(NA_real_)
  sum(x[ok] * w[ok]) / sw
}

# ---- coord_id / geography helpers --------------------------------------------

#' Parse a "lat_lon" coord_id into numeric latitude/longitude.
#'
#' coord_ids are the E2SFCA origin keys, e.g. "39.73921_-104.99025". A malformed
#' key (no underscore, non-numeric) yields NA for the affected field rather than
#' an error.
#' @param coord_id character vector.
#' @return data.frame(coord_id, lat, lon).
#' @export
dj7_parse_coord_id <- function(coord_id) {
  s <- strsplit(as.character(coord_id), "_", fixed = TRUE)
  num <- function(z, i) suppressWarnings(as.numeric(z[i]))
  data.frame(
    coord_id = as.character(coord_id),
    lat = vapply(s, num, numeric(1), 1L),
    lon = vapply(s, num, numeric(1), 2L),
    stringsAsFactors = FALSE)
}

#' CONUS bounding-box gate (48 states + DC; excludes AK/HI/PR/territories).
#'
#' Matches `conus_ok()` in the scripts: lon in (-125, -66), lat in (24, 50).
#' @param lat,lon numeric vectors.
#' @return logical vector; NA coordinates are FALSE.
#' @export
dj7_conus_ok <- function(lat, lon) {
  !is.na(lat) & !is.na(lon) & lon > -125 & lon < -66 & lat > 24 & lat < 50
}

# ---- physician / recovery boundaries -----------------------------------------

#' Career-stage split at years-since-certification (boundary at the cutoff).
#'
#' Reproduces the inline rule in scripts 00/10: a physician is "Early-to-mid" when
#' `years_since_cert <= cutoff` and "Late" otherwise. The boundary is INCLUSIVE of
#' the cutoff (exactly `cutoff` years is Early-to-mid). NA years -> NA stage.
#' @param years_since_cert numeric study-year minus certification year.
#' @param cutoff inclusive upper bound of the early-to-mid class (default 15).
#' @return character "Early-to-mid"/"Late" (NA for NA input).
#' @export
dj7_career_stage <- function(years_since_cert, cutoff = 15) {
  ifelse(is.na(years_since_cert), NA_character_,
         ifelse(years_since_cert <= cutoff, "Early-to-mid", "Late"))
}

#' Whether a recovered physician re-enters the accessibility surface.
#'
#' Reproduces script 08's `in_surface_5km <- nearest_origin_km <= 5`: a recovered
#' location within (inclusive) the 5-km DBSCAN cluster radius of an existing
#' isochrone origin reuses that origin's catchment. The boundary is INCLUSIVE
#' (exactly `radius_km` is in-surface). NA distance -> FALSE.
#' @param nearest_origin_km numeric distance to the nearest origin (km).
#' @param radius_km inclusive cluster radius (default 5, per CLAUDE.md #17).
#' @return logical.
#' @export
dj7_in_surface <- function(nearest_origin_km, radius_km = 5) {
  !is.na(nearest_origin_km) & nearest_origin_km <= radius_km
}

# ---- accessibility category (Desjardins "quintile") --------------------------

#' Assign a tract to a Desjardins accessibility category.
#'
#' Category 1 = zero-access tracts (`access <= 0`); categories 2-5 = quartiles of
#' the strictly-positive access distribution. Reproduces the `case_when` in
#' script 00. NA access is treated as zero (category 1).
#'
#' @section Which column to pass:
#' Pass `compute_e2sfca()$access$access_math`, not `$access`. Since that
#' function began distinguishing a measured zero from a tract outside every
#' modelled catchment, its public `access` column is `NA` for the latter --
#' 190 of 1,447 Colorado tracts on a rare-subspecialty surface. Feeding those
#' `NA`s here silently files them under category 1, "zero-access", which
#' reintroduces exactly the conflation upstream now avoids.
#'
#' The `NA -> 0` rule below is retained deliberately because this function
#' reproduces the published Desjardins categorisation, in which the input is
#' already a complete zero-filled vector. It is not a judgement that unmeasured
#' and zero are the same thing.
#'
#' @param access numeric per-tract accessibility. Use the algebraic
#'   (zero-filled) form; see the section above.
#' @param brk optional length-3 quartile cut points of the positive distribution;
#'   computed from `access` when NULL.
#' @return integer vector in 1:5.
#' @export
dj7_assign_quintile <- function(access, brk = NULL) {
  access <- as.numeric(access)
  access[is.na(access)] <- 0
  if (is.null(brk)) {
    pos <- access[access > 0]
    brk <- if (length(pos)) stats::quantile(pos, probs = c(.25, .5, .75), na.rm = TRUE)
           else c(NA_real_, NA_real_, NA_real_)
  }
  q <- integer(length(access))
  q[access <= 0] <- 1L
  q[access > 0        & access <= brk[1]] <- 2L
  q[access > brk[1]   & access <= brk[2]] <- 3L
  q[access > brk[2]   & access <= brk[3]] <- 4L
  q[access > brk[3]] <- 5L
  q
}

# ---- the E2SFCA engine -------------------------------------------------------

#' Tract-level E2SFCA accessibility from per-band tract membership.
#'
#' Reproduces the demand/supply/access recurrence of `run_e2sfca()` (script 06)
#' with base R so it is exercisable against hand-computed fixtures:
#' \enumerate{
#'   \item demand \eqn{D_j = \sum_b w'_b \cdot \mathrm{cumpop}_b(j)} where
#'         \eqn{\mathrm{cumpop}_b(j)} is the population of tracts whose centroid
#'         falls in origin j's band-b (nested) isochrone;
#'   \item supply-to-demand ratio \eqn{R_j = S_j / \max(D_j, \epsilon)},
#'         non-finite set to 0 (so a zero-demand origin contributes nothing);
#'   \item access \eqn{A_i = \sum_{j \ni i} W_{b^*(i,j)} R_j} where \eqn{b^*} is
#'         the tightest band reaching tract i from origin j (max cumulative
#'         weight across the bands in which the (i,j) pair appears).
#' }
#' A tract reached by no positive-supply origin gets \eqn{A_i = 0} — the
#' zero-access set, which is purely geometric (independent of the demand
#' denominator and of the particular positive band weights).
#'
#' @param membership named list keyed by band ("30","60","120","180"); each
#'   element a data.frame with columns `coord_id`, `GEOID` (one row per
#'   origin-tract pair whose centroid is inside that band). Bands are nested.
#' @param supply named numeric vector supply[coord_id] = provider supply.
#' @param dvec named numeric vector dvec[GEOID] = demand population.
#' @param Wc length-4 cumulative band weights (default [DJ7_WC_BASE]).
#' @return data.frame(GEOID, A) for every reached tract (A > 0 unless the
#'   reaching origins all have zero supply).
#' @export
dj7_tract_access <- function(membership, supply, dvec, Wc = DJ7_WC_BASE) {
  bands <- names(membership)
  Wi <- dj7_incr_weights(Wc)
  cds <- names(supply)
  Dj  <- stats::setNames(rep(0, length(cds)), cds)

  for (bb in bands) {
    m <- membership[[bb]]
    if (is.null(m) || nrow(m) == 0) next
    # SCIENTIFIC JOIN DOCTRINE. A tract inside a band with no demand entry used
    # to be silently zeroed, removing its residents from the denominator and
    # INFLATING accessibility -- the same failure the main engine now refuses.
    # Missing demand is unknown, not empty.
    miss_g <- setdiff(unique(as.character(m$GEOID)), names(dvec))
    if (length(miss_g)) {
      stop(sprintf("dj7_tract_access: %s",
                   .sci_join_msg(sprintf("membership[[%s]]", bb), "dvec", "GEOID",
                     miss_g, " Missing demand is unknown, not zero: zeroing it would drop those residents from the denominator and inflate accessibility.")),
           call. = FALSE)
    }
    d <- dvec[as.character(m$GEOID)]
    d[is.na(d)] <- 0        # explicit NA in dvec, distinct from an absent key
    cp <- tapply(d, as.character(m$coord_id), sum)
    add <- as.numeric(cp); names(add) <- names(cp)
    hit <- intersect(names(add), names(Dj))
    Dj[hit] <- Dj[hit] + Wi[[bb]] * add[hit]
  }

  Rj <- supply / pmax(Dj[names(supply)], .Machine$double.eps)
  Rj[!is.finite(Rj)] <- 0

  allp <- do.call(rbind, lapply(bands, function(bb) {
    m <- membership[[bb]]
    if (is.null(m) || nrow(m) == 0) return(NULL)
    data.frame(GEOID = as.character(m$GEOID), coord_id = as.character(m$coord_id),
               w = unname(Wc[[bb]]), stringsAsFactors = FALSE)
  }))
  if (is.null(allp) || nrow(allp) == 0)
    return(data.frame(GEOID = character(0), A = numeric(0), stringsAsFactors = FALSE))

  key  <- paste(allp$GEOID, allp$coord_id, sep = "\r")
  wmax <- tapply(allp$w, key, max)                       # tightest band per (i,j)
  parts <- strsplit(names(wmax), "\r", fixed = TRUE)
  gg <- vapply(parts, `[`, character(1), 1L)
  cc <- vapply(parts, `[`, character(1), 2L)
  # An origin present in the membership with no supply-to-demand ratio is an
  # unmatched key, not a zero. Excluding origins without supply is legitimate and
  # happens upstream; reaching here means the two tables disagree.
  miss_c <- setdiff(unique(cc), names(Rj))
  if (length(miss_c)) {
    stop(sprintf("dj7_tract_access: %s",
                 .sci_join_msg("membership", "Rj", "coord_id", miss_c,
                   " An origin with no ratio cannot be treated as contributing zero without hiding a table mismatch.")),
         call. = FALSE)
  }
  rj <- Rj[cc]; rj[is.na(rj)] <- 0
  contrib <- as.numeric(wmax) * rj
  A <- tapply(contrib, gg, sum)
  data.frame(GEOID = names(A), A = as.numeric(A), stringsAsFactors = FALSE)
}

#' Population-weighted no-access share (percent) from a tract access table.
#'
#' Percent of `dvec` population in tracts with `A <= 0` (equivalently `A == 0`,
#' since access is non-negative). The zero-access tract SET is geometric; the
#' reported share is denominator-weighted, so it varies with `dvec` but is
#' invariant to the positive band weights.
#' @param access_df output of [dj7_tract_access] (GEOID, A).
#' @param dvec named numeric demand vector over ALL tracts (unreached tracts
#'   count as zero access).
#' @return percent in [0, 100].
#' @export
dj7_no_access_share <- function(access_df, dvec) {
  A <- stats::setNames(rep(0, length(dvec)), names(dvec))
  hit <- intersect(as.character(access_df$GEOID), names(A))
  A[hit] <- access_df$A[match(hit, as.character(access_df$GEOID))]
  w <- dvec; w[is.na(w)] <- 0
  sw <- sum(w)
  if (!is.finite(sw) || sw <= 0) return(NA_real_)
  100 * sum(w[A <= 0]) / sw
}
