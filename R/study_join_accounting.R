# ==============================================================================
# study_join_accounting.R -- fail-closed accounting for study-layer joins.
# ==============================================================================
# PORTED FROM isochrones (scripts/stratify_allyears_access.R @ fe25f0ed3,
# 2026-08-17), and promoted from inline script code to a tested export as part
# of making twostep the canonical owner of the E2SFCA study layer.
#
# WHY A PER-STATE GATE AND NOT A NATIONAL MATCH RATE
#   The Connecticut vocabulary break dropped ~879 tracts -- the entire state --
#   from the ACS denominator join for 2022 and 2023. Every national match-rate
#   gate in the pipeline stayed green, because Connecticut is about 1% of CONUS
#   tracts. A national rate cannot see one small state vanish. Only a per-state
#   rate can, which is what this function checks.
# ==============================================================================

#' Fail closed when any single state loses too much of a join
#'
#' Computes the per-state share of rows that failed to match and `stop()`s,
#' naming the offending states and their loss rates, when any state exceeds
#' `max_frac`. Use after a `left_join()` on tract `GEOID`s so that a vocabulary
#' mismatch fails loudly instead of silently removing a state.
#'
#' @param geoid `character` tract GEOIDs; the first two characters are the state
#'   FIPS code.
#' @param lost `logical` of the same length; `TRUE` marks a row that failed to
#'   match (typically `is.na(joined_column)`).
#' @param context `character(1)` prefix for the error message, e.g. `"GO 2023"`.
#' @param max_frac `numeric(1)` maximum tolerated per-state loss share. Defaults
#'   to 0.05 (5\%), the threshold used by the isochrones production run.
#' @return Invisibly, a named `numeric` of per-state loss fractions for the
#'   states that lost at least one row. Called for its fail-closed side effect.
#' @examples
#' g <- c("09001010101", "09001010102", "25025010100")
#' # Nothing lost -> passes:
#' assert_state_join_loss(g, c(FALSE, FALSE, FALSE), "demo")
#' @export
assert_state_join_loss <- function(geoid, lost, context = "join",
                                   max_frac = 0.05) {
  checkmate::assert_character(geoid, any.missing = FALSE)
  checkmate::assert_logical(lost, any.missing = FALSE, len = length(geoid))
  checkmate::assert_string(context)
  checkmate::assert_number(max_frac, lower = 0, upper = 1)

  if (!any(lost)) return(invisible(stats::setNames(numeric(0), character(0))))

  st       <- substr(as.character(geoid), 1, 2)
  st_all   <- table(st)
  st_lost  <- table(st[lost])
  frac     <- as.numeric(st_lost) / as.numeric(st_all[names(st_lost)])
  names(frac) <- names(st_lost)

  bad <- names(frac)[frac > max_frac]
  if (length(bad)) {
    stop(sprintf(paste0("[strat] %s: state(s) %s lost >%.0f%% of tracts in the ",
                        "join (%s). A national match rate cannot catch this -- ",
                        "one small state can vanish entirely while the national ",
                        "rate stays high."),
                 context, paste(bad, collapse = ", "), 100 * max_frac,
                 paste(sprintf("%s=%.1f%%", bad, 100 * frac[bad]),
                       collapse = " ")),
         call. = FALSE)
  }
  invisible(frac)
}

#' Partition rows whose access is unknown, rather than zeroing them
#'
#' Splits a study frame into rows with a measured access value and rows where
#' access is missing. Missing access is a PROVENANCE GAP, not an observation of
#' no access: coercing it to zero (`d$access[is.na(d$access)] <- 0`, the historic
#' behaviour) biases the population-weighted mean DOWN and the zero-access share
#' UP, because a tract that was never measured is counted as a tract where no
#' provider is reachable.
#'
#' @param d `data.frame` of study rows.
#' @param access_col `character(1)` name of the access column. Default `"access"`.
#' @return `list` with `kept` (rows with measured access), `n_unknown` (count
#'   excluded) and `frac_unknown`.
#' @examples
#' d <- data.frame(GEOID = c("a", "b", "c"), access = c(1, NA, 0))
#' p <- partition_unknown_access(d)
#' p$n_unknown          # 1 excluded, NOT turned into a measured zero
#' nrow(p$kept)         # 2: the measured 1 and the measured 0 both survive
#' @export
partition_unknown_access <- function(d, access_col = "access") {
  checkmate::assert_data_frame(d)
  checkmate::assert_string(access_col)
  if (!access_col %in% names(d)) {
    stop(sprintf("[strat] partition_unknown_access(): column '%s' not present",
                 access_col), call. = FALSE)
  }
  unknown <- is.na(d[[access_col]])
  list(kept         = d[!unknown, , drop = FALSE],
       n_unknown    = sum(unknown),
       frac_unknown = if (length(unknown)) mean(unknown) else 0)
}
