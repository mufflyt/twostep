#!/usr/bin/env Rscript
# =============================================================================
# Old-versus-corrected diff for every manuscript-facing age-matched quantity
# =============================================================================
# Permanent provenance, not a one-off debugging aid. When the corrected panel
# replaces the artifact that silently dropped supply in 12 of 14 cells, this
# records -- for every quantity that reaches the manuscript, appendix or figure --
# the old value, the corrected value, the absolute and relative change, and
# whether the INTERPRETATION changed.
#
# The last column is the one that matters. A ratio can move in the fourth decimal
# and be irrelevant, or cross 1.0 and invert a claim. Recording only the numbers
# would leave a reader to infer which happened.
#
# Usage: Rscript tools/multiverse/diff_age_matched.R \
#          --old artifacts/multiverse/age_matched_results.csv \
#          --new artifacts/2sfca/agematched_panel/age_matched_panel.csv
suppressWarnings(suppressMessages(library(jsonlite)))
args <- commandArgs(trailingOnly = TRUE)
getarg <- function(f, d = NULL) { i <- which(args == f)
  if (length(i) && i[1] < length(args)) args[[i[1] + 1L]] else d }
OLD <- getarg("--old", "artifacts/multiverse/age_matched_results.csv")
NEW <- getarg("--new", "artifacts/2sfca/agematched_panel/age_matched_panel.csv")
OUT <- getarg("--out", "artifacts/multiverse/age_matched_correction_diff.csv")
for (f in c(OLD, NEW)) if (!file.exists(f)) {
  cat("::error::missing ", f, "\n", sep = ""); quit(status = 1L) }

o <- utils::read.csv(OLD, stringsAsFactors = FALSE)
n <- utils::read.csv(NEW, stringsAsFactors = FALSE)
if (!"year" %in% names(o)) o$year <- 2020L
n <- n[n$year %in% unique(o$year), , drop = FALSE]   # compare like with like

rows <- list()
add <- function(quantity, subspec, regime, old, new, interp_old = NA, interp_new = NA) {
  abs_d <- new - old
  rel_d <- if (isTRUE(abs(old) > 0)) abs_d / abs(old) else NA_real_
  changed <- if (!is.na(interp_old) && !is.na(interp_new)) !identical(interp_old, interp_new) else NA
  rows[[length(rows) + 1L]] <<- data.frame(
    quantity = quantity, subspec = subspec, regime = regime,
    old = old, corrected = new, abs_change = abs_d, rel_change = rel_d,
    interpretation_old = interp_old, interpretation_new = interp_new,
    interpretation_changed = changed, stringsAsFactors = FALSE)
}

key <- function(d, r, s) d[d$regime == r & d$subspec == s, , drop = FALSE]
for (s in sort(unique(o$subspec))) for (r in c("all_ages", "age_matched")) {
  a <- key(o, r, s); b <- key(n, r, s)
  if (!nrow(a) || !nrow(b)) next
  for (v in c("denominator", "national", "metro", "rural", "white", "aian"))
    if (v %in% names(a) && v %in% names(b)) add(v, s, r, a[[v]][1], b[[v]][1])
  # ratios carry an interpretation: below 1 means the group is worse served
  for (v in c("rural_metro_ratio", "aian_white_ratio"))
    if (v %in% names(a) && v %in% names(b))
      add(v, s, r, a[[v]][1], b[[v]][1],
          ifelse(a[[v]][1] < 1, "disadvantaged", "not disadvantaged"),
          ifelse(b[[v]][1] < 1, "disadvantaged", "not disadvantaged"))
  # supply coverage: the defect itself
  if (all(c("n_supply_origins","n_iso_origins") %in% names(a)))
    add("origins_dropped", s, r,
        a$n_supply_origins[1] - a$n_iso_origins[1],
        b$n_supply_origins[1] - b$n_iso_origins[1],
        ifelse(a$n_supply_origins[1] > a$n_iso_origins[1], "supply lost", "complete"),
        ifelse(b$n_supply_origins[1] > b$n_iso_origins[1], "supply lost", "complete"))
}

# derived, manuscript-facing quantities
share <- function(d) {
  aa <- d[d$regime == "all_ages", ]; am <- d[d$regime == "age_matched", ]
  k <- paste(am$year, am$subspec)
  stats::setNames(am$denominator / stats::setNames(aa$denominator, paste(aa$year, aa$subspec))[k],
                  am$subspec)
}
so <- share(o); sn <- share(n)
for (s in intersect(names(so), names(sn))) add("age_eligible_share", s, "derived", so[[s]], sn[[s]])

claim <- function(d, col) {
  am <- d[d$regime == "age_matched", ]
  max(am[[col]], na.rm = TRUE)
}
add("C2_max_rural_metro", "ALL", "age_matched",
    claim(o, "rural_metro_ratio"), claim(n, "rural_metro_ratio"),
    ifelse(claim(o, "rural_metro_ratio") < 1, "C2 holds", "C2 fails"),
    ifelse(claim(n, "rural_metro_ratio") < 1, "C2 holds", "C2 fails"))
add("C3_max_aian_white", "ALL", "age_matched",
    claim(o, "aian_white_ratio"), claim(n, "aian_white_ratio"),
    ifelse(claim(o, "aian_white_ratio") < 1, "C3 holds", "C3 fails"),
    ifelse(claim(n, "aian_white_ratio") < 1, "C3 holds", "C3 fails"))

ord <- function(d) paste(d$subspec[d$regime == "age_matched"][
  order(-d$national[d$regime == "age_matched"])], collapse = ">")
add("C5_ordering", "ALL", "age_matched", NA_real_, NA_real_, ord(o), ord(n))

res <- do.call(rbind, rows)
dir.create(dirname(OUT), showWarnings = FALSE, recursive = TRUE)
utils::write.csv(res, OUT, row.names = FALSE)

nch <- sum(res$interpretation_changed %in% TRUE)
cat("old-vs-corrected diff\n")
cat("  quantities compared: ", nrow(res), "\n", sep = "")
cat("  worst relative change: ",
    signif(max(abs(res$rel_change), na.rm = TRUE), 4), "\n", sep = "")
cat("  INTERPRETATION CHANGED in ", nch, " quantit", if (nch == 1) "y" else "ies", "\n", sep = "")
if (nch) {
  ch <- res[res$interpretation_changed %in% TRUE, ]
  for (i in seq_len(nrow(ch)))
    cat(sprintf("    %-22s %-6s  %s -> %s\n", ch$quantity[i], ch$subspec[i],
                ch$interpretation_old[i], ch$interpretation_new[i]))
}
cat("  wrote ", OUT, "\n", sep = "")
