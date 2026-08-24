#!/usr/bin/env Rscript
# =============================================================================
# Scientific invariants on the age-matched 11-year panel
# =============================================================================
# A separate script from check_scientific_invariants.R on purpose. That one
# guards the frozen study artifacts; this guards the panel, which has a
# different column vocabulary (`subspec`, `regime`) and a different lifecycle.
# The national-summary block there cannot check this file at all -- it shares
# only `year` and its column guard fails immediately.
#
# Structurally this mirrors the sensitivity block, which uses the same
# national/metro/rural/white/aian/*_ratio vocabulary with `variant` where the
# panel has `regime`.
#
# Every check is an identity, an inequality, or a completeness requirement that
# must hold for ANY valid panel. Nothing here encodes what the answer should be.
#
# Usage: Rscript tools/ci/check_panel_invariants.R
if (!file.exists("DESCRIPTION")) {
  cat("::error::run from the repository root\n"); quit(status = 1L)
}
# Overridable so the invariants can be negative-tested against synthetic panels
# BEFORE spending ten hours of compute. CI never sets it, so the default is what
# actually gets gated.
PANEL <- Sys.getenv("E2SFCA_PANEL_CSV",
                    "artifacts/2sfca/agematched_panel/age_matched_panel.csv")
fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))
note <- function(...) cat("  ", ..., "\n", sep = "")
TOL  <- 1e-9

# Fail closed. A missing panel is not a reason to pass quietly: this gate exists
# precisely to say something about that file.
if (!file.exists(PANEL)) {
  cat("::error::panel artifact missing: ", PANEL, "\n", sep = "")
  cat("Build it with tools/multiverse/run_panel.sh then consolidate_panel.R.\n")
  quit(status = 1L)
}

p <- utils::read.csv(PANEL, stringsAsFactors = FALSE)
cat("age-matched panel invariants\n")
NEED <- c("year", "regime", "subspec", "age_range", "denominator", "national",
          "metro", "rural", "white", "aian", "rural_metro_ratio",
          "aian_white_ratio", "n_supply_origins", "n_iso_origins")
miss <- setdiff(NEED, names(p))
if (length(miss)) {
  cat("::error::panel is missing column(s): ", paste(miss, collapse = ", "), "\n", sep = "")
  quit(status = 1L)
}
note("rows ", nrow(p), ", years ", min(p$year), "-", max(p$year),
     ", subspecialties ", length(unique(p$subspec)),
     ", regimes ", paste(sort(unique(p$regime)), collapse = "/"))

# (1) completeness: every (year, regime, subspec) exactly once. A missing cell
# drops silently out of any trend; a duplicate double-counts it.
EXP <- length(unique(p$year)) * length(unique(p$regime)) * length(unique(p$subspec))
if (nrow(p) != EXP)
  bad("panel has ", nrow(p), " rows but ", length(unique(p$year)), " years x ",
      length(unique(p$regime)), " regimes x ", length(unique(p$subspec)),
      " subspecialties = ", EXP)
k <- paste(p$year, p$regime, p$subspec)
if (any(duplicated(k)))
  bad("duplicate (year, regime, subspec): ", paste(unique(k[duplicated(k)]), collapse = "; "))
yrs <- sort(unique(p$year))
if (length(yrs) > 1L && any(diff(yrs) != 1L))
  bad("years are not contiguous: ", paste(yrs, collapse = ", "))

# (2) derived ratios must equal the columns they come from. These hold by
# construction in the runner, so this is a live check on file integrity.
r1 <- abs(p$rural_metro_ratio - p$rural / p$metro)
r2 <- abs(p$aian_white_ratio  - p$aian  / p$white)
if (any(r1 > TOL, na.rm = TRUE))
  bad(sum(r1 > TOL, na.rm = TRUE), " row(s) where rural_metro_ratio != rural/metro",
      " (worst ", signif(max(r1, na.rm = TRUE), 3), ")")
if (any(r2 > TOL, na.rm = TRUE))
  bad(sum(r2 > TOL, na.rm = TRUE), " row(s) where aian_white_ratio != aian/white",
      " (worst ", signif(max(r2, na.rm = TRUE), 3), ")")

# (3) accessibility is supply over demand: non-negative and finite.
for (col in c("national", "metro", "rural", "white", "aian")) {
  v <- p[[col]]
  if (any(!is.finite(v))) bad(sum(!is.finite(v)), " non-finite value(s) in ", col)
  if (any(v < 0, na.rm = TRUE)) bad(sum(v < 0, na.rm = TRUE), " negative value(s) in ", col)
}

# (4) denominators are populations.
if (any(p$denominator <= 0, na.rm = TRUE))
  bad(sum(p$denominator <= 0, na.rm = TRUE), " row(s) with a non-positive denominator")

# (5) within a year, the all-ages denominator is the SAME for every
# subspecialty -- it is one population by construction. A per-subspecialty
# difference means the all-ages arm was not held fixed.
aa <- p[p$regime == "all_ages", ]
for (y in unique(aa$year)) {
  d <- aa$denominator[aa$year == y]
  if (length(d) > 1L && (max(d) - min(d)) > 1e-6)
    bad("year ", y, ": the all-ages denominator differs across subspecialties (",
        format(min(d), big.mark = ","), " to ", format(max(d), big.mark = ","), ")")
}

# (6) an age window is a SUBSET of all ages, so its denominator cannot exceed
# the all-ages denominator for the same year.
am <- p[p$regime == "age_matched", ]
key_aa <- stats::setNames(aa$denominator, paste(aa$year, aa$subspec))
for (i in seq_len(nrow(am))) {
  ref <- key_aa[[paste(am$year[i], am$subspec[i])]]
  if (!is.null(ref) && am$denominator[i] > ref + 1e-6)
    bad(am$year[i], " ", am$subspec[i], ": age-matched denominator exceeds all-ages (",
        format(am$denominator[i], big.mark = ","), " > ", format(ref, big.mark = ","), ")")
}

# (7) origins that reached an isochrone cannot outnumber the origins supplied.
if (any(p$n_iso_origins > p$n_supply_origins, na.rm = TRUE))
  bad(sum(p$n_iso_origins > p$n_supply_origins, na.rm = TRUE),
      " row(s) where n_iso_origins exceeds n_supply_origins")

# (8) the regime label and the age-range label must agree, or the two arms have
# been mixed up somewhere.
if (any(p$regime == "all_ages" & p$age_range != "all ages"))
  bad(sum(p$regime == "all_ages" & p$age_range != "all ages"),
      " all_ages row(s) whose age_range is not 'all ages'")
if (any(p$regime != "all_ages" & p$age_range == "all ages"))
  bad(sum(p$regime != "all_ages" & p$age_range == "all ages"),
      " age-matched row(s) labelled 'all ages'")

note("derived-ratio worst deviation: ",
     signif(max(c(r1, r2), na.rm = TRUE), 3))
note("age-eligible share range: ",
     sprintf("%.1f%%", 100 * min(am$denominator / key_aa[paste(am$year, am$subspec)], na.rm = TRUE)),
     " to ",
     sprintf("%.1f%%", 100 * max(am$denominator / key_aa[paste(am$year, am$subspec)], na.rm = TRUE)))

cat("\n")
if (length(fail)) {
  message("FAIL: the age-matched panel violates scientific invariants:")
  for (f in fail) message("  - ", f)
  message("\n  These are identities, inequalities and completeness requirements",
          "\n  that must hold for ANY valid panel, independently of whether the",
          "\n  method or the data are correct.")
  quit(status = 1L, save = "no")
}
cat("every panel invariant holds\n")
