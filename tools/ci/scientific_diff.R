#!/usr/bin/env Rscript
# =============================================================================
# Scientific diff artifact: the headline numbers, their inputs, and their hashes.
# =============================================================================
# Every scientific test in this repo pins behaviour by ASSERTION. Nothing
# recorded the study's actual headline results in a comparable form, so a change
# that moved a reported estimate was invisible unless some test happened to
# cover it. This emits those numbers as a machine-readable artifact and fails on
# unexplained movement against a committed baseline.
#
# Two sections are compared and one is not:
#
#   inputs     sha256 of every frozen input the numbers derive from. A change
#              here means the evidence moved.
#   headline   the reported estimates themselves. A change here means the
#              ANSWER moved, which must never happen silently.
#   context    git SHA, R version, package versions. RECORDED for provenance but
#              NOT compared: these change legitimately on every commit and every
#              runner image, and comparing them would train people to rerun
#              --update reflexively, which is how a real diff gets waved through.
#
# Usage:
#   Rscript tools/ci/scientific_diff.R            compare against the baseline
#   Rscript tools/ci/scientific_diff.R --update   re-record it (a review event)
#   Rscript tools/ci/scientific_diff.R --print    emit the JSON and stop

args   <- commandArgs(trailingOnly = TRUE)
update <- "--update" %in% args
printo <- "--print"  %in% args

for (p in c("jsonlite", "digest")) if (!requireNamespace(p, quietly = TRUE))
  stop("scientific_diff.R needs the '", p, "' package", call. = FALSE)

# --- which scientific record are we diffing? ---------------------------------
# Default `e2sfca` behaves exactly as before: same baseline, same inputs, same
# headline derivation. The second spec covers the age-matched 11-year panel,
# which is a different artifact with a different column vocabulary.
#
# Parameterised rather than forked into a sibling script: the walk/compare,
# --update and --print logic below is the valuable part, and a copy of it would
# drift from this one silently -- the failure this repository keeps rediscovering.
SPEC <- local({
  i <- grep("^--spec=", args)
  if (length(i)) sub("^--spec=", "", args[i[1]]) else "e2sfca"
})
SPECS <- c("e2sfca", "agematched_panel")
if (!SPEC %in% SPECS)
  stop("unknown --spec: ", SPEC, " (want one of: ", paste(SPECS, collapse = ", "), ")",
       call. = FALSE)

BASELINE <- if (SPEC == "e2sfca") {
  file.path("tests", "fixtures", "scientific_baseline.json")
} else {
  file.path("tests", "fixtures", "agematched_panel_baseline.json")
}
TOL <- 1e-9

sha <- function(path) if (file.exists(path))
  digest::digest(file = path, algo = "sha256") else NA_character_

if (SPEC == "e2sfca") {

# --- inputs -------------------------------------------------------------------
suppressWarnings(suppressMessages(source("scripts/manuscript_e2sfca_values.R")))
run_dir <- e2sfca_run_dir()
ns_csv  <- file.path(run_dir, "e2sfca_national_summary.csv")

inputs <- list(
  engine_R               = sha("R/two_step_floating_catchment.R"),
  manuscript_values_R    = sha("scripts/manuscript_e2sfca_values.R"),
  national_summary_csv   = sha(ns_csv),
  run_manifest_json      = sha(file.path(run_dir, "e2sfca_run_manifest.json")),
  sha256sums_txt         = sha("SHA256SUMS.txt"),
  luo_qi_fixture_json    = sha("tests/fixtures/luo_qi_2009_e2sfca.json"),
  frozen_run_id          = E2SFCA_FROZEN_RUN_ID,
  allocator_method_id    = E2SFCA_ALLOCATOR_METHOD_ID,
  production_resolution_m = E2SFCA_PRODUCTION_RESOLUTION_M
)

# --- headline numbers ---------------------------------------------------------
ns <- as.data.frame(load_e2sfca_national_summary(run_dir))
key <- "mean_pop_weighted_per100k"
stopifnot(all(c("subspecialty", "year", key) %in% names(ns)))
ns <- ns[order(ns$subspecialty, ns$year), ]

per_sub <- lapply(split(ns, ns$subspecialty), function(d) {
  d <- d[order(d$year), ]
  list(first_year = as.integer(min(d$year)),
       last_year  = as.integer(max(d$year)),
       first      = round(d[[key]][1], 10),
       last       = round(d[[key]][nrow(d)], 10),
       absolute_change = round(d[[key]][nrow(d)] - d[[key]][1], 10),
       max        = round(max(d[[key]]), 10))
})

# One hash over the WHOLE reported series. The per-subspecialty values above say
# where a change is; this says whether there is one anywhere at all, including in
# years the summary above does not surface.
series <- paste(ns$subspecialty, ns$year, sprintf("%.10f", ns[[key]]), collapse = "|")

headline <- list(
  n_rows              = nrow(ns),
  n_subspecialties    = length(unique(ns$subspecialty)),
  years               = as.integer(sort(unique(ns$year))),
  female_pop_total    = as.integer(unique(ns$pop_valid_total)[1]),
  series_sha256       = digest::digest(series, algo = "sha256"),
  mean_access_per100k = per_sub
)

} else {

# --- age-matched panel --------------------------------------------------------
# Deliberately does NOT source manuscript_e2sfca_values.R: that pulls
# dplyr/readr/tidyr/here and hard-requires mufflyaccess, and none of it is needed
# to diff a standalone panel CSV.
PANEL <- "artifacts/2sfca/agematched_panel/age_matched_panel.csv"
if (!file.exists(PANEL))
  stop("panel artifact missing: ", PANEL,
       "\n  Build it with tools/multiverse/run_panel.sh then ",
       "tools/multiverse/consolidate_panel.R", call. = FALSE)
pn <- utils::read.csv(PANEL, stringsAsFactors = FALSE)
need <- c("year", "regime", "subspec", "national", "rural_metro_ratio", "aian_white_ratio")
if (!all(need %in% names(pn)))
  stop("panel is missing column(s): ",
       paste(setdiff(need, names(pn)), collapse = ", "), call. = FALSE)
pn <- pn[order(pn$year, pn$regime, pn$subspec), ]

inputs <- list(
  panel_csv         = sha(PANEL),
  manifest_yml      = sha("inst/multiverse/age_matched_denominator.yml"),
  runner_R          = sha("tools/multiverse/run_age_matched.R"),
  denominators_R    = sha("tools/multiverse/age_matched_denominators.R"),
  consolidator_R    = sha("tools/multiverse/consolidate_panel.R"),
  engine_R          = sha("R/two_step_floating_catchment.R")
)

# One hash over the WHOLE ordered panel, so a change anywhere is caught even in
# cells the per-subspecialty summary below does not surface.
series <- paste(pn$year, pn$regime, pn$subspec,
                sprintf("%.10f", pn$national),
                sprintf("%.10f", pn$rural_metro_ratio),
                sprintf("%.10f", pn$aian_white_ratio), collapse = "|")

per_cell <- lapply(split(pn, paste(pn$regime, pn$subspec)), function(d) {
  d <- d[order(d$year), ]
  list(first_year = as.integer(min(d$year)), last_year = as.integer(max(d$year)),
       first = round(d$national[1], 10), last = round(d$national[nrow(d)], 10),
       absolute_change = round(d$national[nrow(d)] - d$national[1], 10),
       max_rural_metro = round(max(d$rural_metro_ratio), 10),
       max_aian_white  = round(max(d$aian_white_ratio), 10))
})

headline <- list(
  n_rows           = nrow(pn),
  n_years          = length(unique(pn$year)),
  n_subspecialties = length(unique(pn$subspec)),
  regimes          = sort(unique(pn$regime)),
  years            = as.integer(sort(unique(pn$year))),
  series_sha256    = digest::digest(series, algo = "sha256"),
  by_regime_subspec = per_cell
)

}

context <- list(
  git_sha  = tryCatch(trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE)),
                      error = function(e) NA_character_),
  spec = SPEC,
  r_version = paste0(R.version$major, ".", R.version$minor),
  generated_note = "context is RECORDED for provenance, never compared"
)

current <- list(schema_version = "1.0.0", inputs = inputs,
                headline = headline, context = context)

if (printo) { cat(jsonlite::toJSON(current, auto_unbox = TRUE, pretty = TRUE, digits = 12), "\n"); quit(save = "no") }

if (update || !file.exists(BASELINE)) {
  dir.create(dirname(BASELINE), showWarnings = FALSE, recursive = TRUE)
  writeLines(jsonlite::toJSON(current, auto_unbox = TRUE, pretty = TRUE, digits = 12), BASELINE)
  cat(if (update) "baseline re-recorded: " else "baseline created: ", BASELINE, "\n", sep = "")
  quit(status = 0L, save = "no")
}

# --- compare ------------------------------------------------------------------
base <- jsonlite::fromJSON(BASELINE, simplifyVector = FALSE)
diffs <- character(0)

walk <- function(a, b, path = "") {
  keys <- union(names(a), names(b))
  for (k in keys) {
    p <- if (nzchar(path)) paste0(path, ".", k) else k
    av <- a[[k]]; bv <- b[[k]]
    if (is.null(av)) { diffs <<- c(diffs, sprintf("%s: absent from baseline", p)); next }
    if (is.null(bv)) { diffs <<- c(diffs, sprintf("%s: no longer produced", p)); next }
    if (is.list(av) || is.list(bv)) { walk(av, bv, p); next }
    if (is.numeric(av) && is.numeric(bv)) {
      if (length(av) != length(bv) || any(abs(unlist(av) - unlist(bv)) > TOL))
        diffs <<- c(diffs, sprintf("%s: %s -> %s", p,
                                   paste(bv, collapse = ","), paste(av, collapse = ",")))
    } else if (!identical(as.character(av), as.character(bv))) {
      diffs <<- c(diffs, sprintf("%s:\n      baseline %s\n      current  %s", p,
                                 as.character(bv), as.character(av)))
    }
  }
}
walk(current$inputs,   base$inputs,   "inputs")
walk(current$headline, base$headline, "headline")

cat("scientific diff [", SPEC, "] vs ", BASELINE, "\n", sep = "")
cat("  frozen run:      ", inputs$frozen_run_id, "\n", sep = "")
cat("  subspecialties:  ", headline$n_subspecialties, " over ",
    min(headline$years), "-", max(headline$years), "\n", sep = "")
cat("  series sha256:   ", substr(headline$series_sha256, 1, 16), "...\n", sep = "")

if (length(diffs)) {
  message("\nFAIL: the scientific record moved (", length(diffs), " difference(s)):")
  for (d in diffs) message("  - ", d)
  message("\n  If this change is INTENDED, re-record it deliberately:")
  message("    Rscript tools/ci/scientific_diff.R --update")
  message("  and commit the baseline in the same commit as the change that caused it,")
  message("  so the diff is reviewed as a change to the study's reported results.")
  quit(status = 1L, save = "no")
}
cat("\nno change to inputs or headline results\n")
