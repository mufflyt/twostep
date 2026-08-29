#!/usr/bin/env Rscript
# =============================================================================
# The supply-loss numbers quoted in prose must match the correction diff
# =============================================================================
# The dropped-supply defect is described in five places: NEWS.md, README.md, the
# appendix, the pre-correction README, and the engine's own roxygen. Every one of
# them quotes numbers that were typed by hand, and three of them were wrong when
# this gate was written -- not stale, wrong on the day they were written:
#
#   * NEWS claimed PAG's 2-of-95 was "the largest proportional loss". FPMRS lost
#     15 of 580, which is 2.59% against PAG's 2.11%. PAG is largest by EFFECT ON
#     THE MEAN (3.54%), a different quantity that ranks differently. A small
#     provider set converts a small loss into a large shortfall.
#   * NEWS reported the GO cell's "five origins" and "0.786%" as if they were
#     national. Each subspecialty has its own provider set; there is no single
#     number.
#   * The pre-correction README quoted 3.67%, which is the same shortfall divided
#     by the CONTAMINATED value rather than the corrected one. Both conventions
#     appear in this repository's history and they differ by a third of a point.
#
# None of that is catchable by rereading the prose, because each sentence is
# internally plausible. It is catchable by recomputing from the artifact.
#
# Convention, fixed here so the documents cannot disagree about it:
#     shortfall = (corrected - contaminated) / corrected
# This matches the scientific appendix, which reports GO as 0.786%.
#
# Usage: Rscript tools/ci/check_documented_shortfalls.R
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status = 1L) }

DIFF  <- "artifacts/multiverse/age_matched_correction_diff.csv"
PANEL <- "artifacts/2sfca/agematched_panel/age_matched_panel.csv"
for (f in c(DIFF, PANEL))
  if (!file.exists(f)) { cat("::error::missing artifact: ", f, "\n", sep = ""); quit(status = 1L) }

d  <- utils::read.csv(DIFF,  stringsAsFactors = FALSE)
pn <- utils::read.csv(PANEL, stringsAsFactors = FALSE)
pn <- pn[pn$year == 2020L & pn$regime == "all_ages", , drop = FALSE]

nat  <- d[d$quantity == "national"        & d$regime == "all_ages", ]
drop <- d[d$quantity == "origins_dropped" & d$regime == "all_ages", ]
orig <- stats::setNames(pn$n_iso_origins, pn$subspec)

# shortfall, relative to the CORRECTED value
sf <- stats::setNames(100 * (nat$corrected - nat$old) / nat$corrected, nat$subspec)
# proportional loss of ORIGINS -- deliberately a separate vector, because
# conflating the two is the error this gate exists to catch
ol <- stats::setNames(100 * drop$old / orig[drop$subspec], drop$subspec)

fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))
cat("documented supply-loss figures\n\n")
cat(sprintf("  %-6s %6s %8s %14s %14s\n", "spec", "drop", "origins", "origin loss %", "shortfall %"))
for (k in names(sort(sf, decreasing = TRUE)))
  cat(sprintf("  %-6s %6d %8d %14.3f %14.3f\n", k, as.integer(drop$old[drop$subspec == k]),
              as.integer(orig[k]), ol[k], sf[k]))

# ---- 1. the two rankings really are different, and the docs must not swap them
top_sf <- names(which.max(sf)); top_ol <- names(which.max(ol))
cat("\n  largest shortfall: ", top_sf, "   largest origin loss: ", top_ol, "\n", sep = "")
if (identical(top_sf, top_ol))
  cat("  NOTE: they coincide now; the guards below still pin each number.\n")

# ---- 2. every quoted figure must match the artifact ---------------------------
# file, regex capturing one number, the value it must equal, and a tolerance in
# percentage points generous enough for honest rounding at 2 dp.
CLAIMS <- list(
  list("NEWS.md",   "PAG, ([0-9.]+)%, from losing only 2 of 95",                sf["PAG"],   0.01),
  list("NEWS.md",   "FPMRS, 15 of 580 \\(([0-9.]+)%\\)",                        ol["FPMRS"], 0.01),
  list("README.md", "PAG ([0-9.]+)% and FPMRS",                                 sf["PAG"],   0.01),
  list("README.md", "FPMRS\\s*\n?([0-9.]+)% against the corrected value",       sf["FPMRS"], 0.01),
  list("README.md", "against GO's ([0-9.]+)%",                                  sf["GO"],    0.01),
  list("docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md",
       "\\| PAG \\| 95 \\| 2 \\| \\*\\*([0-9.]+)%\\*\\* \\|",                   sf["PAG"],   0.01),
  list("docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md",
       "\\| FPMRS \\| 580 \\| 15 \\| ([0-9.]+)% \\|",                           sf["FPMRS"], 0.01),
  list("artifacts/multiverse/_precorrection/README.md",
       "deflating access by up to ([0-9.]+)% \\(PAG\\)",                        sf["PAG"],   0.01)
)
cat("\n  quoted figures\n")
for (cl in CLAIMS) {
  f <- cl[[1]]; rx <- cl[[2]]; want <- unname(cl[[3]]); tol <- cl[[4]]
  if (!file.exists(f)) { bad("missing file: ", f); next }
  txt <- paste(readLines(f, warn = FALSE), collapse = "\n")
  m <- regmatches(txt, regexec(rx, txt))[[1]]
  if (length(m) < 2L) {
    bad(f, ": the sentence quoting ", sprintf("%.2f", want),
        "% was reworded or removed -- pattern no longer matches: ", rx)
    next
  }
  got <- as.numeric(m[2])
  ok  <- abs(got - want) <= tol
  cat(sprintf("    %-45s %6.2f  artifact %6.3f  %s\n", basename(f), got, want,
              if (ok) "ok" else "MISMATCH"))
  if (!ok) bad(f, ": quotes ", got, "% where the artifact gives ",
               sprintf("%.3f", want), "%")
}

# ---- 3. the alternative convention must never appear unlabelled ---------------
# 3.67% is PAG's shortfall over the CONTAMINATED value. It is not wrong, it
# answers a different question, and it caused a real misstatement when it
# travelled without its denominator.
alt <- 100 * (nat$corrected[nat$subspec == "PAG"] - nat$old[nat$subspec == "PAG"]) /
       nat$old[nat$subspec == "PAG"]
cat(sprintf("\n  alternative convention (over contaminated): PAG %.2f%%\n", alt))
for (f in c("NEWS.md", "README.md", "docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md",
            "artifacts/multiverse/_precorrection/README.md")) {
  if (!file.exists(f)) next
  ln <- readLines(f, warn = FALSE)
  hit <- grep(sprintf("%.2f%%", alt), ln, fixed = TRUE)
  for (i in hit) {
    ctx <- paste(ln[max(1, i - 2):min(length(ln), i + 2)], collapse = " ")
    if (!grepl("contaminated", ctx, ignore.case = TRUE))
      bad(f, ":", i, ": quotes ", sprintf("%.2f", alt),
          "% without naming the denominator it uses. Say 'over the contaminated value', ",
          "or use ", sprintf("%.2f", sf["PAG"]), "%.")
  }
}

cat("\n")
if (length(fail)) {
  message("FAIL: documented supply-loss figures disagree with the artifact:")
  for (f in fail) message("  - ", f)
  message("\n  Recompute from ", DIFF, ".",
          "\n  Shortfall is (corrected - contaminated) / corrected. The proportional",
          "\n  loss of ORIGINS is a different quantity and ranks differently.")
  quit(status = 1L, save = "no")
}
cat("documented supply-loss figures agree with the artifact\n")
