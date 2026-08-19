#!/usr/bin/env Rscript
# =============================================================================
# Frozen scientific artifacts must record the INPUTS that produced them
# =============================================================================
# SHA256SUMS.txt pins what an artifact IS. It says nothing about what produced
# it. Those are different guarantees, and only the second makes an artifact
# reproducible.
#
# THE FAILURE THIS EXISTS FOR, observed rather than imagined:
# artifacts/2sfca/sensitivity/sensitivity_2020.csv is checksummed, is consumed
# by the manuscript AND by the frozen specification-curve analysis, and has no
# record of which inputs produced it. Its own generator is written to emit
# sensitivity_2020_manifest.json with input paths and SHA-256s; that file was
# never committed. Re-running the generator against inputs chosen by search
# reproduced NONE of it -- national mean access for the primary specification
# came out 16.7% different -- and there is no way to tell which input set was
# correct, because nothing recorded it.
#
# An artifact whose inputs are unknown cannot be reproduced, cannot be audited,
# and cannot be defended. This check makes that condition visible instead of
# waiting for someone to attempt a re-run two years later.
#
# Usage: Rscript tools/ci/check_artifact_provenance.R [--strict]

args   <- commandArgs(trailingOnly = TRUE)
strict <- "--strict" %in% args
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")), error = function(e) ".")
setwd(root)

# Artifacts that FEED a scientific conclusion: consumed by the manuscript or by
# a frozen analysis. Listed by hand -- what counts as load-bearing is a
# judgement, and it should change deliberately.
TRACKED <- list(
  list(path = "artifacts/2sfca/sensitivity/sensitivity_2020.csv",
       manifest = "artifacts/2sfca/sensitivity/sensitivity_2020_manifest.json",
       generator = "scripts/sensitivity_e2sfca_2020.R",
       consumed_by = c("manuscript", "inst/multiverse/specification_manifest.yml")),
  list(path = "artifacts/2sfca/figures/GO_2020_inferential_MC_CI.csv",
       manifest = "artifacts/2sfca/figures/GO_2020_inferential_MC_CI_manifest.json",
       generator = "scripts/inferential_stats_access.R",
       consumed_by = "manuscript"),
  list(path = "artifacts/2sfca/figures/allsubspec_2020_inferential_TABLE.csv",
       manifest = "artifacts/2sfca/figures/allsubspec_2020_inferential_TABLE_manifest.json",
       generator = "scripts/compile_inferential_table.R",
       consumed_by = "manuscript")
)

missing_artifact <- character(0)
missing_manifest <- character(0)
present <- 0L

for (t in TRACKED) {
  if (!file.exists(t$path)) { missing_artifact <- c(missing_artifact, t$path); next }
  if (file.exists(t$manifest)) { present <- present + 1L; next }
  missing_manifest <- c(missing_manifest, sprintf(
    "%s\n      generator:   %s\n      consumed by: %s\n      expected:    %s",
    t$path, t$generator, paste(t$consumed_by, collapse = ", "), t$manifest))
}

cat("artifact input-provenance audit\n")
cat("  tracked load-bearing artifacts: ", length(TRACKED), "\n", sep = "")
cat("  with an input manifest:         ", present, "\n", sep = "")
cat("  without one:                    ", length(missing_manifest), "\n", sep = "")

if (length(missing_artifact)) {
  message("\nFAIL: tracked artifact(s) absent from the repository:")
  for (m in missing_artifact) message("  - ", m)
  quit(status = 1L, save = "no")
}

if (length(missing_manifest)) {
  msg <- paste0(
    "\n", length(missing_manifest), " load-bearing artifact(s) have NO record of the ",
    "inputs that produced them:\n",
    paste0("    - ", missing_manifest, collapse = "\n"),
    "\n\n  A checksum pins what the file IS, not what produced it. Without an input\n",
    "  manifest the artifact cannot be reproduced or audited: re-running its\n",
    "  generator against inputs chosen by search gave a 16.7% different primary\n",
    "  estimate, and nothing recorded which input set was correct.\n",
    "  Fix by running the generator with its inputs pinned and committing the\n",
    "  manifest it writes.")
  if (strict) { message("FAIL:", msg); quit(status = 1L, save = "no") }
  message("KNOWN GAP:", msg)
  message("\n  Reported, not failed: these artifacts predate this check and the inputs\n",
          "  are not currently recoverable. Run with --strict to make it blocking\n",
          "  once the manifests exist, so the gap cannot silently reappear.")
  quit(status = 0L, save = "no")
}
cat("every tracked artifact records its inputs\n")
