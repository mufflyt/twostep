#!/usr/bin/env Rscript
# =============================================================================
# Scientific-core coverage: which exported objects are never exercised?
# =============================================================================
# Line coverage is a poor proxy for scientific confidence -- code can be fully
# covered by tests that assert nothing meaningful. But its converse is decisive:
# an exported function that NO test ever calls is untested, whatever the
# headline percentage says.
#
# That is not hypothetical here. dj7_tract_access() and dj7_no_access_share()
# were exported, documented, and had ZERO test coverage; the gap surfaced by
# accident while chasing something else. This looks for the rest on purpose.
#
# Three tiers are reported, and only the first is fatal:
#
#   CORE      the scientific calculation itself -- weights, overlap, demand,
#             ratios, accessibility, allocation, aggregation. An untested export
#             here is a release blocker.
#   SUPPORT   constants, guards and vocabulary. Untested is a warning.
#   OTHER     plotting, IO, convenience.
#
# "Exercised" means a test file CALLS it, not merely mentions it in a comment or
# a string. "Asserted" additionally means the call appears inside an expect_*(),
# which is a stronger claim and reported separately.
#
# Usage: Rscript tools/ci/scientific_coverage.R [--strict]

args   <- commandArgs(trailingOnly = TRUE)
strict <- "--strict" %in% args

root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
setwd(root)

exports <- sub("^export\\((.*)\\)$", "\\1",
               grep("^export\\(", readLines("NAMESPACE", warn = FALSE), value = TRUE))
exports <- gsub("^\"|\"$", "", exports)

# --- the scientific core, named explicitly ------------------------------------
# Listed by hand rather than pattern-matched: what counts as the scientific core
# is a judgement about the study, not a naming convention, and it should change
# only deliberately.
CORE <- c(
  "e2sfca_band_weights", "e2sfca_incremental_weights", "gaussian_band_weights",
  "gaussian_decay_weights", "compute_band_tract_overlap", "compute_provider_supply",
  "compute_e2sfca", "compute_e2sfca_raster", "allocate_pop_areaweighted",
  "attach_e2sfca_population", "build_e2sfca_grid_geometry", "build_e2sfca_raster_grid",
  "prepare_e2sfca_iso", "e2sfca_cell_summaries",
  "dj7_incr_weights", "dj7_tract_access", "dj7_no_access_share", "dj7_wmean",
  "dj7_assign_quintile", "dj7_in_surface", "dj7_conus_ok", "dj7_parse_coord_id",
  "dj7_career_stage",
  "urps_scenario_supply", "urps_allocate_origins", "urps_project_accessibility",
  "urps_e2sfca_spar_summary",
  "weighted_mean_all", "zero_access_share", "mc_weighted_ci", "annual_trend",
  "zero_access_audit", "zshare_rast",
  "rurality_from_ruca", "classify_bivariate"
)
SUPPORT <- c(
  "CANONICAL_BANDS", "get_canonical_bands", "get_primary_access_band",
  "PRIMARY_ACCESS_BAND_MIN", "PRIMARY_ACCESS_BAND_SEC", "E2SFCA_DEFAULT_THRESHOLDS",
  "DJ7_SUBS", "DJ7_BANDS", "DJ7_WC_BASE", "DJ7_NAME2CODE",
  "TOTAL_FEMALE_VAR", "RACE_FEMALE_VARS", "RUCA_NONMETRO_MIN",
  "DENOMINATOR_CATEGORY", "TRACT_REACHED_COVERAGE_PCT",
  "ACCESS_SAFE_LABELS", "ACCESS_FORBIDDEN_TERMS", "assert_access_language",
  "assert_matching_geography", "acs_year_of", "tract_vintage_of"
)
tier <- ifelse(exports %in% CORE, "CORE",
        ifelse(exports %in% SUPPORT, "SUPPORT", "OTHER"))

# --- scan the test suite ------------------------------------------------------
test_files <- list.files("tests/testthat", pattern = "^(test|helper)-.*[.]R$",
                         full.names = TRUE)
# Strip comments and string literals so a name mentioned in prose or in an error
# message is not mistaken for a call.
strip <- function(path) {
  ln <- readLines(path, warn = FALSE)
  ln <- sub("(?<!\\\\)#.*$", "", ln, perl = TRUE)
  ln <- gsub('"[^"]*"', '""', ln)
  ln <- gsub("'[^']*'", "''", ln)
  ln
}
corpus <- unlist(lapply(test_files, strip))
# The mutation corpus and CI tools also exercise the science.
corpus <- c(corpus, unlist(lapply(
  list.files("tools/ci", pattern = "[.]R$", full.names = TRUE), strip)))

called   <- vapply(exports, function(n)
  any(grepl(paste0("(?<![A-Za-z0-9._])", n, "\\s*\\("), corpus, perl = TRUE)), logical(1))
referenced <- vapply(exports, function(n)
  any(grepl(paste0("(?<![A-Za-z0-9._])", n, "(?![A-Za-z0-9._])"), corpus, perl = TRUE)),
  logical(1))
asserted <- vapply(exports, function(n)
  any(grepl("expect_", corpus) &
      grepl(paste0("(?<![A-Za-z0-9._])", n, "(?![A-Za-z0-9._])"), corpus, perl = TRUE)),
  logical(1))

# A FUNCTION must be CALLED. Accepting a bare mention would let a name that
# appears only in a comparison, an argument name, or another function's
# documentation count as tested -- and it did: attach_e2sfca_population passed
# this check on a reference alone while covr measured it at 0% executed lines.
# A CONSTANT has no call syntax, so for those a reference is the real signal.
#
# Read from the sources rather than from the installed namespace. get() on a
# namespace object deparses srcrefs, which emits an encoding warning per UTF-8
# string in a C locale -- 42 of them here, enough to bury a real warning -- and
# it would make this check unrunnable in a job that has not installed twostep.
pkg_src <- unlist(lapply(list.files("R", pattern = "[.]R$", full.names = TRUE),
                         readLines, warn = FALSE))
defs_fun <- sub("^\\s*`?([A-Za-z._][A-Za-z0-9._]*)`?\\s*(<-|=)\\s*function.*$", "\\1",
                grep("^\\s*`?[A-Za-z._][A-Za-z0-9._]*`?\\s*(<-|=)\\s*function", pkg_src,
                     value = TRUE))
is_fun <- exports %in% defs_fun
exercised <- ifelse(is_fun, called, referenced)
res <- data.frame(name = exports, tier = tier, exercised = exercised,
                  asserted = asserted, stringsAsFactors = FALSE)
res <- res[order(factor(res$tier, levels = c("CORE", "SUPPORT", "OTHER")),
                 res$exercised, res$name), ]

cat("scientific-core coverage over ", length(test_files), " test files\n\n", sep = "")
for (tl in c("CORE", "SUPPORT", "OTHER")) {
  sub <- res[res$tier == tl, ]
  if (!nrow(sub)) next
  cat(sprintf("%-8s %d exports | exercised %d | asserted %d\n",
              tl, nrow(sub), sum(sub$exercised), sum(sub$asserted)))
  miss <- sub$name[!sub$exercised]
  if (length(miss)) for (m in miss) cat("    NEVER EXERCISED: ", m, "\n", sep = "")
  weak <- sub$name[sub$exercised & !sub$asserted]
  if (length(weak)) for (w in weak) cat("    called, never asserted: ", w, "\n", sep = "")
}

core_missing <- res$name[res$tier == "CORE" & !res$exercised]
cat("\n")
if (length(core_missing)) {
  message("FAIL: ", length(core_missing),
          " scientific-CORE export(s) are never exercised by any test:")
  for (m in core_missing) message("  - ", m)
  message("  An exported function no test calls is untested, whatever the ",
          "coverage percentage says.")
  quit(status = 1L, save = "no")
}
cat("every scientific-core export is exercised\n")
if (strict) {
  weak_core <- res$name[res$tier == "CORE" & res$exercised & !res$asserted]
  if (length(weak_core)) {
    message("FAIL (--strict): core export(s) called but never asserted on:")
    for (w in weak_core) message("  - ", w)
    quit(status = 1L, save = "no")
  }
}
