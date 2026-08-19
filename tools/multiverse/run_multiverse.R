#!/usr/bin/env Rscript
# =============================================================================
# Specification-curve (multiverse) runner -- phase 2
# =============================================================================
# Executes the FROZEN grid in inst/multiverse/specification_manifest.yml.
#
# The freeze is enforced before anything else happens: the manifest's SHA-256
# is checked against the recorded hash BEFORE a single outcome is read. If they
# disagree the run aborts and demands a new manifest version. That ordering is
# the point -- it is what stops a specification being added, dropped or
# re-tuned once its answer is known.
#
# Fragility is a RESULT. This runner fails only for the reasons the manifest's
# failure_policy lists: an unreproducible or missing specification, a
# manifest/execution disagreement, or a manuscript claim of robustness the
# specifications do not support. A finding merely being fragile never fails.
#
# Usage: Rscript tools/multiverse/run_multiverse.R [--allow-claim-failure]

suppressWarnings(suppressMessages({
  library(yaml); library(jsonlite)
}))

args <- commandArgs(trailingOnly = TRUE)
allow_claim_failure <- "--allow-claim-failure" %in% args

root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
setwd(root)

MAN  <- "inst/multiverse/specification_manifest.yml"
HASH <- "inst/multiverse/specification_manifest.sha256"
SENS <- "artifacts/2sfca/sensitivity/sensitivity_2020.csv"
OUT  <- "artifacts/multiverse"
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

sha256 <- function(path) {
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(file = path, algo = "sha256"))
  trimws(strsplit(system2("shasum", c("-a", "256", path), stdout = TRUE), "\\s+")[[1]][1])
}
fail <- function(...) { message("MULTIVERSE FAIL: ", ...); quit(status = 1L, save = "no") }

# ---- 0. ENFORCE THE FREEZE, before reading any outcome ----------------------
if (!file.exists(MAN))  fail("manifest missing: ", MAN)
if (!file.exists(HASH)) fail("frozen hash missing: ", HASH)
recorded <- trimws(strsplit(readLines(HASH, warn = FALSE)[1], "\\s+")[[1]][1])
actual   <- sha256(MAN)
if (!identical(recorded, actual)) {
  fail("the specification manifest has changed since it was frozen.\n",
       "  recorded: ", recorded, "\n  actual:   ", actual, "\n",
       "  A frozen grid may not be edited. Create a NEW manifest version with a new\n",
       "  hash and say why, so the change is visible rather than silent.")
}
cat("freeze verified: manifest sha256 ", substr(actual, 1, 16), "...\n", sep = "")

man <- yaml::read_yaml(MAN)
specs <- man$specifications
estimands <- man$estimands
claims <- man$claims
THRESH <- man$classification$relative_magnitude_threshold
PRIMARY <- man$primary_specification

# ---- 1. load the executed outcomes ------------------------------------------
if (!file.exists(SENS)) fail("frozen sensitivity artifact missing: ", SENS)
sens <- utils::read.csv(SENS, stringsAsFactors = FALSE)
sens_sha <- sha256(SENS)

frozen_specs <- Filter(function(s) identical(s$status, "frozen"), specs)
pipe_specs   <- Filter(function(s) identical(s$status, "pipeline"), specs)

# ---- 2. completeness + agreement checks (these MAY fail) --------------------
ids <- vapply(specs, `[[`, character(1), "id")
if (anyDuplicated(ids)) fail("duplicate spec_id in the manifest: ",
                             paste(unique(ids[duplicated(ids)]), collapse = ", "))
want <- vapply(frozen_specs, `[[`, character(1), "variant")
have <- unique(sens$variant)
missing_v <- setdiff(want, have)
if (length(missing_v))
  fail("prespecified specification(s) absent from the executed artifact: ",
       paste(missing_v, collapse = ", "),
       "\n  A frozen specification that did not run is an unreproduced specification.")
extra_v <- setdiff(have, want)
if (length(extra_v))
  fail("the executed artifact contains specification(s) not in the manifest: ",
       paste(extra_v, collapse = ", "),
       "\n  Manifest and executed analysis disagree.")

# executed PARAMETERS must match what the manifest declares
res_of <- function(v) unique(sens$res[sens$variant == v])
for (s in frozen_specs) {
  r <- res_of(s$variant)
  if (length(r) != 1L) fail("variant '", s$variant, "' has non-unique grid resolution: ",
                            paste(r, collapse = ", "))
  expect <- if (identical(s$variant, "res500")) 500 else 1000
  if (!isTRUE(all.equal(as.numeric(r), expect)))
    fail("variant '", s$variant, "' ran at resolution ", r,
         " but the manifest declares ", expect, ". Manifest and execution disagree.")
}
n_sub <- length(unique(sens$subspec))
for (v in want) {
  k <- sum(sens$variant == v)
  if (k != n_sub) fail("variant '", v, "' has ", k, " subspecialty rows, expected ", n_sub)
}
cat("completeness: ", length(want), " executable specs x ", n_sub, " subspecialties\n", sep = "")

# ---- 3. tidy long results ----------------------------------------------------
est_cols <- c(E1 = "national", E2 = "rural_metro_ratio", E3 = "aian_white_ratio")
spec_by_variant <- setNames(specs, vapply(specs, function(s)
  if (!is.null(s$variant)) s$variant else s$id, character(1)))

base_rows <- sens[sens$variant == PRIMARY, ]
rows <- list()
for (s in frozen_specs) {
  v <- s$variant
  sv <- sens[sens$variant == v, ]
  for (sub in sv$subspec) {
    for (eid in names(est_cols)) {
      col <- est_cols[[eid]]
      pv <- base_rows[[col]][base_rows$subspec == sub]
      xv <- sv[[col]][sv$subspec == sub]
      contrast_only <- identical(s$estimand_comparable, "contrast_only")
      comparable <- !(contrast_only && eid == "E1")
      rel <- if (is.finite(pv) && pv != 0) (xv - pv) / abs(pv) else NA_real_
      rows[[length(rows) + 1L]] <- data.frame(
        spec_id = s$id, variant = v, axis = s$axis,
        changed = paste(unlist(s$changed), collapse = "+"),
        status = s$status, subspecialty = sub, estimand = eid,
        estimand_name = col,
        primary_value = pv, spec_value = xv,
        abs_diff = xv - pv, rel_diff = rel,
        direction = if (eid == "E1") NA_character_ else if (xv < 1) "disadvantage" else "no_disadvantage",
        comparable = comparable,
        source_artifact = SENS, source_sha = sens_sha,
        stringsAsFactors = FALSE)
    }
  }
}
# non-executable specs stay in the table, with reason
for (s in pipe_specs) {
  rows[[length(rows) + 1L]] <- data.frame(
    spec_id = s$id, variant = s$variant, axis = s$axis,
    changed = paste(unlist(s$changed), collapse = "+"),
    status = s$status, subspecialty = NA_character_, estimand = NA_character_,
    estimand_name = NA_character_, primary_value = NA_real_, spec_value = NA_real_,
    abs_diff = NA_real_, rel_diff = NA_real_, direction = NA_character_,
    comparable = NA, source_artifact = NA_character_, source_sha = NA_character_,
    stringsAsFactors = FALSE)
}
res <- do.call(rbind, rows)

# ---- 4. classification (thresholds fixed in the manifest, not here) ---------
classify <- function(r) {
  if (identical(r$status, "pipeline")) return("not_executable")
  if (!isTRUE(r$comparable))          return("not_comparable_estimand_changed")
  if (r$spec_id == "S01")             return("primary")
  claim_holds <- if (r$estimand == "E1") TRUE else isTRUE(r$spec_value < 1)
  if (!claim_holds)                   return("materially_conclusion_sensitive")
  if (r$estimand == "E2" && r$subspecialty == "GO") {
    crossed <- isTRUE(r$primary_value < 0.5) != isTRUE(r$spec_value < 0.5)
    if (crossed)                      return("materially_conclusion_sensitive")
  }
  if (isTRUE(abs(r$rel_diff) > THRESH)) return("quantitatively_sensitive")
  "directionally_invariant"
}
res$classification <- vapply(seq_len(nrow(res)), function(i) classify(res[i, ]), character(1))
utils::write.csv(res, file.path(OUT, "multiverse_results.csv"), row.names = FALSE)
cat("wrote multiverse_results.csv (", nrow(res), " rows)\n", sep = "")

# ---- 5. manuscript claims, evaluated by their prespecified rules ------------
eval_claims <- function(v) {
  sv <- sens[sens$variant == v, ]
  go <- sv$rural_metro_ratio[sv$subspec == "GO"]
  ord <- sv$subspec[order(-sv$national)]
  c(C1 = isTRUE(go < 0.5),
    C2 = all(sv$rural_metro_ratio < 1),
    C3 = all(sv$aian_white_ratio < 1),
    C5 = isTRUE(all(c("MFM", "GO") %in% ord[1:2]) && identical(ord[length(ord)], "CFP")))
}
cm <- do.call(rbind, lapply(want, function(v) data.frame(variant = v, t(eval_claims(v)))))
cm$spec_id <- vapply(cm$variant, function(v) spec_by_variant[[v]]$id, character(1))
# C4 is the manuscript's own robustness assertion: C2 AND C3 in EVERY executable spec
C4 <- all(cm$C2) && all(cm$C3)
cm$C4_contribution <- cm$C2 & cm$C3

# CLAIM-CONSISTENCY GUARD. In --verify mode the runner does NOT rewrite the
# claim table; it re-derives every truth value from the frozen inputs and
# compares. An edited claim_matrix.csv -- a truth value flipped by hand between
# runs, deliberately or by a bad merge -- is caught here rather than believed.
CLAIMS_CSV <- file.path(OUT, "claim_matrix.csv")
if ("--verify" %in% args) {
  if (!file.exists(CLAIMS_CSV)) fail("--verify: no claim table to verify at ", CLAIMS_CSV)
  on_disk <- utils::read.csv(CLAIMS_CSV, stringsAsFactors = FALSE)
  key <- c("C1", "C2", "C3", "C5", "C4_contribution")
  on_disk <- on_disk[order(on_disk$variant), c("variant", key)]
  fresh   <- cm[order(cm$variant), c("variant", key)]
  bad <- FALSE
  for (k in key) {
    d <- as.logical(on_disk[[k]]); f <- as.logical(fresh[[k]])
    m <- which(d != f)
    if (length(m)) {
      bad <- TRUE
      for (i in m) message("  claim ", k, " for '", fresh$variant[i],
                           "': table says ", d[i], ", recomputation says ", f[i])
    }
  }
  if (bad) fail("the recorded claim table disagrees with recomputation from the frozen inputs.")
  cat("claim-consistency verified: recorded table matches recomputation\n")
} else {
  utils::write.csv(cm, CLAIMS_CSV, row.names = FALSE)
}

# ---- 6. leave-one-assumption-out -------------------------------------------
# ONLY specifications differing from primary on exactly ONE axis qualify.
loo <- list()
for (s in frozen_specs) {
  if (identical(s$variant, PRIMARY)) next
  n_changed <- length(unlist(s$changed))
  if (n_changed != 1L) next            # not an isolated contrast; excluded by design
  sv <- sens[sens$variant == s$variant, ]
  for (eid in names(est_cols)) {
    col <- est_cols[[eid]]
    if (identical(s$estimand_comparable, "contrast_only") && eid == "E1") next
    for (sub in sv$subspec) {
      pv <- base_rows[[col]][base_rows$subspec == sub]
      xv <- sv[[col]][sv$subspec == sub]
      claim_p <- if (eid == "E1") NA else pv < 1
      claim_x <- if (eid == "E1") NA else xv < 1
      loo[[length(loo) + 1L]] <- data.frame(
        spec_id = s$id, axis = s$axis, assumption = unlist(s$changed)[1],
        subspecialty = sub, estimand = eid, estimand_name = col,
        primary = pv, altered = xv, abs_change = xv - pv,
        pct_change = 100 * (xv - pv) / abs(pv),
        direction_changed = !identical(claim_p, claim_x),
        claim_truth_changed = !identical(claim_p, claim_x),
        stringsAsFactors = FALSE)
    }
  }
}
loo <- do.call(rbind, loo)
utils::write.csv(loo, file.path(OUT, "leave_one_out.csv"), row.names = FALSE)

# ---- 7. robustness summaries (DESCRIPTIVE, not sampling intervals) ---------
summ <- list()
for (eid in names(est_cols)) {
  col <- est_cols[[eid]]
  for (sub in unique(sens$subspec)) {
    ok <- vapply(frozen_specs, function(s)
      !(identical(s$estimand_comparable, "contrast_only") && eid == "E1"), logical(1))
    vs <- vapply(frozen_specs[ok], function(s)
      sens[[col]][sens$variant == s$variant & sens$subspec == sub], numeric(1))
    pv <- base_rows[[col]][base_rows$subspec == sub]
    dirn <- if (eid == "E1") rep(TRUE, length(vs)) else (vs < 1)
    far <- names(vs)[which.max(abs(vs - pv))]
    summ[[length(summ) + 1L]] <- data.frame(
      estimand = eid, estimand_name = col, subspecialty = sub,
      primary = pv, n_executable = length(vs),
      min = min(vs), p25 = unname(stats::quantile(vs, .25)),
      median = stats::median(vs), p75 = unname(stats::quantile(vs, .75)),
      max = max(vs), mean = mean(vs), sd = stats::sd(vs),
      frac_same_direction = mean(dirn),
      frac_claim_holds = mean(dirn),
      spec_largest_deviation = vapply(frozen_specs[ok], `[[`, character(1), "variant")[which.max(abs(vs - pv))],
      spec_min = vapply(frozen_specs[ok], `[[`, character(1), "variant")[which.min(vs)],
      spec_max = vapply(frozen_specs[ok], `[[`, character(1), "variant")[which.max(vs)],
      summary_kind = "descriptive_over_prespecified_specifications_not_sampling_interval",
      stringsAsFactors = FALSE)
  }
}
summ <- do.call(rbind, summ)
utils::write.csv(summ, file.path(OUT, "robustness_summary.csv"), row.names = FALSE)

# ---- 8. provenance ----------------------------------------------------------
prov <- list(
  manifest_sha256 = actual,
  runner_sha256 = sha256("tools/multiverse/run_multiverse.R"),
  input_artifact = SENS, input_sha256 = sens_sha,
  results_sha256 = sha256(file.path(OUT, "multiverse_results.csv")),
  claims_sha256 = sha256(file.path(OUT, "claim_matrix.csv")),
  loo_sha256 = sha256(file.path(OUT, "leave_one_out.csv")),
  summary_sha256 = sha256(file.path(OUT, "robustness_summary.csv")),
  executed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
  r_version = as.character(getRversion()),
  platform = R.version$platform,
  n_specifications = length(specs),
  n_executable = length(frozen_specs),
  n_not_executable = length(pipe_specs))
jsonlite::write_json(prov, file.path(OUT, "provenance.json"), auto_unbox = TRUE, pretty = TRUE)

# ---- 9. report ---------------------------------------------------------------
cat("\n=== CLAIMS BY SPECIFICATION ===\n")
print(cm[, c("spec_id", "variant", "C1", "C2", "C3", "C5")], row.names = FALSE)
cat("\nC4 (manuscript: \"Disparities held across all sensitivity specifications\"): ",
    if (C4) "SUPPORTED" else "NOT SUPPORTED", "\n", sep = "")

cat("\n=== CLASSIFICATION COUNTS (executable rows) ===\n")
print(table(res$classification[res$status == "frozen"]))

cat("\n=== NOT EVALUABLE FROM THE FROZEN ARTIFACT ===\n")
cat("  The abstract's \"about one in five ... outside 60 minutes\" and \"about six\n",
    "  times as likely [zero access]\" have NO counterpart in sensitivity_2020.csv,\n",
    "  which carries mean access and two contrast ratios only. They are reported as\n",
    "  UNEVALUABLE and are NOT inferred from mean accessibility.\n", sep = "")

# ---- 10. failure policy ------------------------------------------------------
# The rule is NOT "fail if fragile". It is "fail if the MANUSCRIPT asserts a
# robustness the specifications do not support". So the guard reads the
# manuscript and fails only on the conjunction. Amend the sentence to describe
# the fragility accurately and this passes with the fragility intact -- which is
# the correct scientific outcome, not a loophole.
RMD <- "manuscript/e2sfca_accessibility_manuscript.Rmd"
asserts_blanket_robustness <- FALSE
if (file.exists(RMD)) {
  txt <- paste(readLines(RMD, warn = FALSE), collapse = " ")
  asserts_blanket_robustness <-
    grepl("Disparities held across all sensitivity specifications", txt, fixed = TRUE)
}
cat("\nmanuscript asserts blanket robustness: ", asserts_blanket_robustness, "\n", sep = "")

if (!C4 && asserts_blanket_robustness && !allow_claim_failure) {
  message("\nMULTIVERSE FAIL: claim C4 is not supported.")
  message("  The manuscript states \"Disparities held across all sensitivity ",
          "specifications\", but the frozen multiverse contradicts it:")
  offend <- cm[!cm$C4_contribution, c("spec_id", "variant")]
  for (i in seq_len(nrow(offend)))
    message("    ", offend$spec_id[i], " (", offend$variant[i], ")")
  message("  This is a MISSTATEMENT, not a fragile finding. Fragility is fine and is")
  message("  reported; asserting robustness that does not hold is not. Amend the")
  message("  sentence to describe which disparity fails under which assumption.")
  quit(status = 1L, save = "no")
}
if (!C4)
  cat("NOTE: C4 unsupported, but the manuscript does not assert blanket robustness.\n",
      "      Fragility is reported as a scientific result; this is not a failure.\n", sep = "")
cat("\nmultiverse run complete\n")
