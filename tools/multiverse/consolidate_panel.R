#!/usr/bin/env Rscript
# =============================================================================
# Consolidate the per-year age-matched runs into ONE panel artifact + provenance
# =============================================================================
# run_age_matched.R writes one CSV per vintage. This joins them into a single
# keyed table and records what produced it.
#
# The provenance follows the MULTIVERSE idiom (artifacts/multiverse/provenance.json)
# rather than the EC2 _SUCCESS.json one. That is deliberate: _SUCCESS.json is
# welded into a bash heredoc in scripts/ec2_run_2sfca.sh for EC2 E2SFCA runs, and
# E2SFCA_FROZEN_RUN_ID structurally names a directory under artifacts/2sfca/ec2/
# validated against that run's own manifest. This panel is a multiverse artifact
# and belongs to that family.
#
# Usage: Rscript tools/multiverse/consolidate_panel.R
suppressWarnings(suppressMessages({library(digest); library(jsonlite)}))
say <- function(...) cat(sprintf("[panel] %s\n", sprintf(...)))
fail <- function(...) { cat(sprintf("::error::%s\n", sprintf(...))); quit(status = 1L) }
if (!file.exists("DESCRIPTION")) fail("run from the repository root")

YEARS <- 2013:2023
OUTDIR <- "artifacts/2sfca/agematched_panel"
OUT    <- file.path(OUTDIR, "age_matched_panel.csv")
PROV   <- file.path(OUTDIR, "provenance.json")

path_for <- function(y) {
  if (y == 2020L) {
    "artifacts/multiverse/age_matched_results.csv"
  } else {
    sprintf("artifacts/multiverse/age_matched_results_%d.csv", y)
  }
}

parts <- list(); inputs <- list()
missing <- integer(0)
for (y in YEARS) {
  p <- path_for(y)
  if (!file.exists(p)) { missing <- c(missing, y); next }
  d <- utils::read.csv(p, stringsAsFactors = FALSE)
  # 2020 predates the year column; stamp it rather than re-running that year and
  # rewriting the file the manuscript and appendix read.
  if (!"year" %in% names(d)) d <- cbind(year = y, d)
  # Compare by value, not identical(): the stamped column is integer and the
  # loop variable a double, so identical() reports a mismatch whose message
  # reads "contains 2020, expected 2020".
  if (!isTRUE(all(d$year == y)))
    fail("%s contains year(s) %s, expected %d", p,
         paste(unique(d$year), collapse = ","), y)
  parts[[as.character(y)]] <- d
  inputs[[basename(p)]] <- digest::digest(file = p, algo = "sha256")
}
if (length(missing))
  fail("panel incomplete -- no results for: %s. Run tools/multiverse/run_panel.sh first.",
       paste(missing, collapse = ", "))

# Bind on the union of columns, failing if the schemas actually disagree rather
# than silently filling NA.
cols <- unique(unlist(lapply(parts, names)))
for (y in names(parts)) {
  d <- setdiff(cols, names(parts[[y]]))
  if (length(d)) fail("year %s is missing column(s): %s", y, paste(d, collapse = ", "))
}
panel <- do.call(rbind, lapply(parts, function(d) d[, cols, drop = FALSE]))
panel <- panel[order(panel$year, panel$regime, panel$subspec), ]
rownames(panel) <- NULL

# ---- completeness: this is the whole point of the panel ----------------------
EXPECT <- length(YEARS) * 2L * 7L
if (nrow(panel) != EXPECT)
  fail("panel has %d rows, expected %d (%d years x 2 regimes x 7 subspecialties)",
       nrow(panel), EXPECT, length(YEARS))
key <- paste(panel$year, panel$regime, panel$subspec)
if (any(duplicated(key)))
  fail("duplicate (year, regime, subspec): %s",
       paste(unique(key[duplicated(key)]), collapse = "; "))
if (!setequal(unique(panel$year), YEARS))
  fail("panel years are %s, expected %s", paste(sort(unique(panel$year)), collapse = ","),
       paste(YEARS, collapse = ","))

dir.create(OUTDIR, showWarnings = FALSE, recursive = TRUE)
utils::write.csv(panel, OUT, row.names = FALSE)
say("wrote %s (%d rows, %d years, %d subspecialties, 2 regimes)",
    OUT, nrow(panel), length(unique(panel$year)), length(unique(panel$subspec)))

prov <- list(
  artifact          = OUT,
  results_sha256    = digest::digest(file = OUT, algo = "sha256"),
  manifest          = "inst/multiverse/age_matched_denominator.yml",
  manifest_sha256   = digest::digest(file = "inst/multiverse/age_matched_denominator.yml",
                                     algo = "sha256"),
  runner_sha256     = digest::digest(file = "tools/multiverse/run_age_matched.R",
                                     algo = "sha256"),
  denominators_sha256 = digest::digest(file = "tools/multiverse/age_matched_denominators.R",
                                       algo = "sha256"),
  consolidator_sha256 = digest::digest(file = "tools/multiverse/consolidate_panel.R",
                                       algo = "sha256"),
  engine_sha256     = digest::digest(file = "R/two_step_floating_catchment.R",
                                     algo = "sha256"),
  per_year_inputs   = inputs,
  years             = YEARS,
  n_cells           = nrow(panel),
  n_subspecialties  = length(unique(panel$subspec)),
  regimes           = sort(unique(panel$regime)),
  executed_at       = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  r_version         = paste(R.version$major, R.version$minor, sep = "."),
  platform          = R.version$platform
)
jsonlite::write_json(prov, PROV, auto_unbox = TRUE, pretty = TRUE)
say("wrote %s", PROV)
say("results sha256: %s", prov$results_sha256)
