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
# GRANDFATHERED BASELINE AT v0.2.0 -- a ratchet, not an amnesty.
# Three artifacts predate this check and their generating inputs are not
# recoverable, so demanding manifests for them would mean a permanently red gate
# that everyone learns to ignore. They are enumerated below and REPORTED.
#
# What is blocking is the direction of travel: any load-bearing artifact that is
# NOT on that list must record its inputs, and the list may shrink but never
# grow. Adding a new artifact without provenance now fails, which is the failure
# that actually matters -- the legacy three are a known, bounded, documented
# debt, while a fourth would be the same mistake made again after learning why
# it was a mistake.
#
# Removing an entry from LEGACY once its manifest exists is required, not
# optional: the check fails if a listed artifact turns out to HAVE provenance,
# so the exception list cannot quietly outlive the exceptions.
#
# Usage: Rscript tools/ci/check_artifact_provenance.R [--strict]
#   --strict additionally fails on the grandfathered three, for the day they are
#   reproduced.

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

# Grandfathered at v0.2.0. Do not add to this list. Remove an entry the moment
# its manifest is committed.
LEGACY <- c(
  "artifacts/2sfca/sensitivity/sensitivity_2020.csv",
  "artifacts/2sfca/figures/GO_2020_inferential_MC_CI.csv",
  "artifacts/2sfca/figures/allsubspec_2020_inferential_TABLE.csv"
)

missing_artifact <- character(0)
missing_manifest <- character(0)
present <- 0L

stale_legacy <- character(0)
new_missing  <- character(0)

for (t in TRACKED) {
  if (!file.exists(t$path)) { missing_artifact <- c(missing_artifact, t$path); next }
  if (file.exists(t$manifest)) {
    present <- present + 1L
    # A grandfathered artifact that now HAS provenance must leave the list, or
    # the exception outlives the exception and quietly re-licenses a slot.
    if (t$path %in% LEGACY) stale_legacy <- c(stale_legacy, t$path)
    next
  }
  entry <- sprintf(
    "%s\n      generator:   %s\n      consumed by: %s\n      expected:    %s",
    t$path, t$generator, paste(t$consumed_by, collapse = ", "), t$manifest)
  missing_manifest <- c(missing_manifest, entry)
  if (!(t$path %in% LEGACY)) new_missing <- c(new_missing, entry)
}

cat("artifact input-provenance audit\n")
cat("  tracked load-bearing artifacts: ", length(TRACKED), "\n", sep = "")
cat("  with an input manifest:         ", present, "\n", sep = "")
cat("  without one:                    ", length(missing_manifest), "\n", sep = "")
cat("  grandfathered at v0.2.0:        ", length(LEGACY), "\n", sep = "")
cat("  NEW without provenance:         ", length(new_missing), "\n", sep = "")

if (length(missing_artifact)) {
  message("\nFAIL: tracked artifact(s) absent from the repository:")
  for (m in missing_artifact) message("  - ", m)
  quit(status = 1L, save = "no")
}

if (length(stale_legacy)) {
  message("\nFAIL: these artifacts are on the grandfathered list but DO have an input")
  message("manifest. Remove them from LEGACY in this file:")
  for (m in stale_legacy) message("  - ", m)
  message("\n  The list is a bounded debt, not a permanent licence. An entry that",
          "\n  outlives its exception leaves a slot open for a future artifact to",
          "\n  inherit without anyone deciding to grant it.")
  quit(status = 1L, save = "no")
}

if (length(new_missing)) {
  message("\nFAIL: ", length(new_missing), " load-bearing artifact(s) NOT covered by the ",
          "v0.2.0 baseline have no record of the inputs that produced them:")
  for (m in new_missing) message("    - ", m)
  message("\n  Three artifacts are grandfathered because their inputs are genuinely",
          "\n  unrecoverable. This is not one of them. Run the generator with its",
          "\n  inputs pinned and commit the manifest it writes.",
          "\n\n  Do not add it to LEGACY. That list may shrink, never grow.")
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
