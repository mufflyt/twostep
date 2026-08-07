# =============================================================================
# Accessibility under URPS workforce-projection scenarios
#
# NurseCast-style separation of concerns across the three repos:
#
#   mufflyaccess  owns the scenario DICTIONARY + projection CONTRACT (what a
#                 scenario is, what a projection table must look like).
#   cliff         PRODUCES the projection: a long table of national supply per
#                 (scenario_id, year) -- headcount + clinical-FTE, with 95% bounds.
#   twostep       (here) CONSUMES that projection and asks the accessibility
#                 question: given each scenario's national supply in a year, how
#                 accessible are the subspecialists across the CONUS?
#
# This module is the deterministic ORCHESTRATION layer only. It does NOT run the
# E2SFCA model -- that engine (`compute_e2sfca()`, needing the isochrone/tract
# overlap + population) is INJECTED as a function. Keeping the two apart means the
# scenario wiring is pure data manipulation (base R + mufflyaccess), testable
# without the geospatial stack, exactly like cliff's projection producer is
# testable without the road network.
#
# The supply chain for one (scenario, year):
#
#   national supply  --urps_allocate_national()-->  per-CONUS-state count
#                    --within-state scaling-------> per-origin supply(coord_id)
#                    --accessibility_fn()---------> access metrics (E2SFCA/SPAR)
#
# The per-origin `data.frame(coord_id, supply)` is exactly the shape twostep's
# `compute_e2sfca(overlap, tract_pop, supply, ...)` asserts, so a real adapter is
# a one-liner over the engine (see scripts/urps_accessibility/).
# =============================================================================

.uas_basis_col <- function(basis) {
  basis <- match.arg(basis, c("headcount", "clinical_fte"))
  if (basis == "headcount") "supply_headcount" else "supply_clinical_fte"
}

# Resolve a projection argument: a path (read + validate through the SSOT) or an
# already-in-memory projection data.frame (validated in place).
.uas_projection <- function(projection, validate = TRUE) {
  if (is.character(projection) && length(projection) == 1L) {
    return(mufflyaccess::read_urps_projection(projection, validate = validate))
  }
  if (is.data.frame(projection)) {
    if (isTRUE(validate)) mufflyaccess::validate_urps_projection(projection)
    return(projection)
  }
  stop("[urps_accessibility] `projection` must be a file path or a projection data.frame.",
       call. = FALSE)
}

#' National URPS supply for one scenario-year, allocated to CONUS states
#'
#' Takes cliff's projection table and returns the provider supply a given
#' `scenario_id` implies in a given `year`, allocated from the national total to
#' the 49 CONUS states (+ DC) with the shared weights in
#' `mufflyaccess::urps_allocate_national()`.
#'
#' @param projection A projection file path (read + validated via the SSOT) or an
#'   already-validated projection `data.frame` (the cliff artifact / contract).
#' @param scenario_id A single registered scenario id
#'   (`mufflyaccess::urps_scenario_ids()`).
#' @param year A single projection year present in the table.
#' @param basis `"headcount"` (default) or `"clinical_fte"` -- which supply
#'   measure to allocate. Fractional clinical-FTE is rounded before integer
#'   allocation; the pre-rounding value is returned in `national_supply`.
#' @param weights Optional allocation weights forwarded to
#'   `mufflyaccess::urps_allocate_national()`; `NULL` uses the SSOT default.
#' @return A `data.frame`, one row per CONUS state: `scenario_id`, `year`,
#'   `basis`, `state_abbr`, `state_fips`, `supply` (integer, allocated), and
#'   `national_supply` (the unrounded national total). `supply` sums to the
#'   rounded national total -- allocation is mass-conserving.
#' @seealso [urps_allocate_origins()], [urps_project_accessibility()],
#'   `mufflyaccess::urps_allocate_national()`
#' @export
urps_scenario_supply <- function(projection, scenario_id, year,
                                 basis = c("headcount", "clinical_fte"),
                                 weights = NULL) {
  col <- .uas_basis_col(basis)
  basis <- match.arg(basis)
  if (length(scenario_id) != 1L || !is.character(scenario_id))
    stop("[urps_accessibility] `scenario_id` must be a single string.", call. = FALSE)
  if (length(year) != 1L || !is.numeric(year))
    stop("[urps_accessibility] `year` must be a single number.", call. = FALSE)
  mufflyaccess::validate_urps_scenarios(scenario_id)

  p <- .uas_projection(projection)
  row <- p[p$scenario_id == scenario_id & p$year == as.integer(year), , drop = FALSE]
  if (nrow(row) == 0L)
    stop(sprintf("[urps_accessibility] no projection row for scenario '%s' in year %d.",
                 scenario_id, as.integer(year)), call. = FALSE)
  nat <- row[row$geography_type == "national", , drop = FALSE]
  if (nrow(nat) != 1L)
    stop(sprintf("[urps_accessibility] expected exactly one national row for '%s'/%d, got %d.",
                 scenario_id, as.integer(year), nrow(nat)), call. = FALSE)

  national_supply <- nat[[col]]
  if (length(national_supply) != 1L || is.na(national_supply) || national_supply <= 0)
    stop(sprintf("[urps_accessibility] scenario '%s' year %d has no usable %s supply (got %s); the projection does not populate `%s` for this cell.",
                 scenario_id, as.integer(year), basis,
                 format(national_supply), col), call. = FALSE)
  n <- as.integer(round(national_supply))
  alloc <- mufflyaccess::urps_allocate_national(n, weights = weights)

  data.frame(
    scenario_id     = scenario_id,
    year            = as.integer(year),
    basis           = basis,
    state_abbr      = alloc$state_abbr,
    state_fips      = alloc$state_fips,
    supply          = alloc$n_allocated,
    national_supply = national_supply,
    stringsAsFactors = FALSE)
}

#' Distribute per-state scenario supply onto baseline provider origins
#'
#' The E2SFCA engine consumes supply as `data.frame(coord_id, supply)` -- a count
#' per provider ORIGIN, not per state. This turns a scenario's per-state supply
#' ([urps_scenario_supply()]) into that per-origin shape by scaling each baseline
#' origin's supply within its state by `scenario_state_total / baseline_state_total`.
#' A scenario that (say) grows the national workforce 1.5x grows each existing
#' origin proportionally within its state's allocated share; it never invents new
#' provider locations.
#'
#' @param state_supply A [urps_scenario_supply()] frame (needs `state_abbr` /
#'   `state_fips` and `supply`).
#' @param baseline_origins A `data.frame` of the baseline roster's per-origin
#'   supply: `coord_id` (character origin key `"lat_lon"`), `supply` (baseline
#'   count, `> 0`), and a state key -- `state_abbr` or `state_fips` -- matching
#'   `state_supply`.
#' @return A `data.frame(coord_id, supply)` with `supply > 0`, ready to pass to
#'   `compute_e2sfca()`. The per-state sums equal `state_supply$supply` (up to the
#'   states that actually have baseline origins). States with a positive scenario
#'   supply but NO baseline origin cannot be placed and are reported via a warning
#'   and the `"unplaceable"` attribute (a named vector of state -> unplaced count);
#'   creating provider locations that do not exist is out of scope for a
#'   proportional scenario.
#' @seealso [urps_scenario_supply()], [urps_project_accessibility()]
#' @export
urps_allocate_origins <- function(state_supply, baseline_origins) {
  if (!is.data.frame(state_supply) || !all(c("supply") %in% names(state_supply)))
    stop("[urps_accessibility] `state_supply` must be a urps_scenario_supply() frame.", call. = FALSE)
  if (!is.data.frame(baseline_origins) || !all(c("coord_id", "supply") %in% names(baseline_origins)))
    stop("[urps_accessibility] `baseline_origins` needs columns `coord_id` and `supply`.", call. = FALSE)

  key <- if ("state_abbr" %in% names(baseline_origins) && "state_abbr" %in% names(state_supply)) {
    "state_abbr"
  } else if ("state_fips" %in% names(baseline_origins) && "state_fips" %in% names(state_supply)) {
    "state_fips"
  } else {
    stop("[urps_accessibility] `baseline_origins` must carry a state key (`state_abbr` or `state_fips`) matching `state_supply`.",
         call. = FALSE)
  }

  target <- stats::setNames(state_supply$supply, as.character(state_supply[[key]]))
  base_state_total <- tapply(baseline_origins$supply,
                             as.character(baseline_origins[[key]]), sum)

  st <- as.character(baseline_origins[[key]])
  base_tot <- as.numeric(base_state_total[st])
  tgt      <- as.numeric(target[st])
  tgt[is.na(tgt)] <- 0                     # baseline origin in a state the scenario drops
  scale <- ifelse(base_tot > 0, tgt / base_tot, 0)

  out <- data.frame(coord_id = baseline_origins$coord_id,
                    supply   = baseline_origins$supply * scale,
                    stringsAsFactors = FALSE)
  out <- out[out$supply > 0, , drop = FALSE]

  # States the scenario wants to staff but that have no baseline origin to scale.
  placeable_states  <- names(base_state_total[base_state_total > 0])
  unplaceable_states <- setdiff(names(target[target > 0]), placeable_states)
  if (length(unplaceable_states)) {
    unplaced <- target[unplaceable_states]
    warning(sprintf("[urps_accessibility] %d state(s) have scenario supply but no baseline provider origin to scale onto (%s); %d provider(s) left unplaced.",
                    length(unplaceable_states),
                    paste(unplaceable_states, collapse = ", "),
                    as.integer(sum(unplaced))), call. = FALSE)
    attr(out, "unplaceable") <- unplaced
  }
  rownames(out) <- NULL
  out
}

#' Project accessibility across URPS workforce scenarios
#'
#' The orchestration entry point. For each (`scenario_id`, `year`) in the
#' requested grid, allocate that scenario's national supply to CONUS states
#' ([urps_scenario_supply()]), optionally distribute it onto baseline provider
#' origins ([urps_allocate_origins()]), hand the supply to `accessibility_fn`,
#' and stack the returned per-scenario-year accessibility metrics into one long,
#' contract-keyed table.
#'
#' `accessibility_fn` is the seam between this deterministic wiring and the
#' geospatial engine. Signature: `function(supply, scenario_id, year, ...)` ->
#' `data.frame`. When `baseline_origins` is supplied, `supply` is the per-origin
#' `data.frame(coord_id, supply)` that `compute_e2sfca()` consumes; otherwise it
#' is the per-state [urps_scenario_supply()] frame. Tests inject a lightweight
#' deterministic stub so the orchestration is verifiable without sf/terra.
#'
#' @param projection A projection file path or a validated projection `data.frame`.
#' @param accessibility_fn `function(supply, scenario_id, year, ...)` ->
#'   `data.frame`.
#' @param baseline_origins Optional baseline per-origin supply (see
#'   [urps_allocate_origins()]); when given, `accessibility_fn` receives
#'   engine-ready `data.frame(coord_id, supply)`.
#' @param scenarios Character vector of scenario ids; `NULL` runs every scenario
#'   in the projection.
#' @param years Integer vector of years; `NULL` runs every year in the projection.
#' @param basis `"headcount"` (default) or `"clinical_fte"`.
#' @param weights Optional allocation weights forwarded to the allocator.
#' @param ... Extra arguments forwarded to `accessibility_fn` (e.g. the overlap
#'   table, tract population, band weights).
#' @return A long `data.frame`: `accessibility_fn`'s columns prefixed with
#'   `scenario_id` and `year`, row-bound across the grid. Scenario ids are
#'   validated against the SSOT registry before any compute runs.
#' @seealso [urps_scenario_supply()], [urps_allocate_origins()],
#'   `mufflyaccess::urps_scenarios()`
#' @export
urps_project_accessibility <- function(projection, accessibility_fn,
                                       baseline_origins = NULL,
                                       scenarios = NULL, years = NULL,
                                       basis = c("headcount", "clinical_fte"),
                                       weights = NULL, ...) {
  basis <- match.arg(basis)
  if (!is.function(accessibility_fn))
    stop("[urps_accessibility] `accessibility_fn` must be a function.", call. = FALSE)

  p <- .uas_projection(projection)
  if (is.null(scenarios)) scenarios <- sort(unique(p$scenario_id))
  if (is.null(years))     years     <- sort(unique(p$year))
  mufflyaccess::validate_urps_scenarios(scenarios)   # fail loud before any compute

  out <- list()
  for (s in scenarios) {
    for (y in years) {
      state_supply <- urps_scenario_supply(p, s, y, basis = basis, weights = weights)
      supply <- if (is.null(baseline_origins)) state_supply
                else urps_allocate_origins(state_supply, baseline_origins)
      res <- accessibility_fn(supply, scenario_id = s, year = as.integer(y), ...)
      if (!is.data.frame(res))
        stop(sprintf("[urps_accessibility] accessibility_fn must return a data.frame; got %s for '%s'/%d.",
                     class(res)[1], s, as.integer(y)), call. = FALSE)
      if (nrow(res))
        out[[length(out) + 1L]] <- cbind(scenario_id = s, year = as.integer(y),
                                         res, stringsAsFactors = FALSE)
    }
  }
  if (!length(out))
    return(data.frame(scenario_id = character(0), year = integer(0),
                      stringsAsFactors = FALSE))
  do.call(rbind, c(out, list(make.row.names = FALSE, stringsAsFactors = FALSE)))
}
