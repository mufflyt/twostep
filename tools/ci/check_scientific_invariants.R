#!/usr/bin/env Rscript
# =============================================================================
# Scientific invariants on the FROZEN artifacts
# =============================================================================
# The test suite proves the engine satisfies its invariants on synthetic
# fixtures. That is necessary and not sufficient: it says nothing about whether
# the numbers actually published hold together. These checks run on the frozen
# artifacts the manuscript reads.
#
# The distinction matters. A unit test can pass on a four-tract fixture while
# the national artifact carries a value that is arithmetically impossible --
# a percentage above 100, a ratio that disagrees with the two columns it is
# derived from, or a nested-catchment monotonicity violation. Nothing checked
# for that until now.
#
# Every check here is an identity or an inequality that must hold for ANY valid
# run, not a threshold tuned to these particular numbers. Nothing here encodes
# what the answer should be -- only what could not possibly be right.
#
# Usage: Rscript tools/ci/check_scientific_invariants.R

root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                 error = function(e) ".")
setwd(root)
fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))
note <- function(...) cat("  ", ..., "\n", sep = "")
TOL  <- 1e-9

SENS <- "artifacts/2sfca/sensitivity/sensitivity_2020.csv"
SPAT <- "artifacts/2sfca/spatial_outcomes/spatial_outcomes_2020.csv"

cat("scientific invariants on the frozen artifacts\n\n")

# ---- sensitivity artifact ----------------------------------------------------
if (!file.exists(SENS)) {
  bad("frozen sensitivity artifact missing: ", SENS)
} else {
  s <- utils::read.csv(SENS, stringsAsFactors = FALSE)
  cat("sensitivity_2020.csv (", nrow(s), " rows)\n", sep = "")

  # (1) national vs national_check: the generator computes the national
  # population-weighted mean TWICE by different routes -- once from the engine's
  # own national summary, once by re-weighting the surface. They must agree.
  # This cross-check is built into the script and nothing verified it.
  d <- abs(s$national - s$national_check)
  rel <- d / pmax(abs(s$national), .Machine$double.eps)
  worst <- which.max(rel)
  note("national vs national_check: worst relative disagreement ",
       signif(rel[worst], 3), " (", s$variant[worst], "/", s$subspec[worst], ")")
  viol <- which(rel > 1e-6)
  for (i in viol)
    bad("national != national_check for ", s$variant[i], "/", s$subspec[i], ": ",
        s$national[i], " vs ", s$national_check[i],
        " -- two independent computations of the same quantity disagree")

  # (2) derived ratios must equal the columns they are derived from
  rm_ok <- abs(s$rural_metro_ratio - s$rural / s$metro)
  aw_ok <- abs(s$aian_white_ratio - s$aian / s$white)
  note("derived ratios: max |rural_metro_ratio - rural/metro| = ", signif(max(rm_ok), 3))
  note("derived ratios: max |aian_white_ratio - aian/white|   = ", signif(max(aw_ok), 3))
  for (i in which(rm_ok > 1e-9))
    bad("rural_metro_ratio disagrees with rural/metro for ", s$variant[i], "/", s$subspec[i])
  for (i in which(aw_ok > 1e-9))
    bad("aian_white_ratio disagrees with aian/white for ", s$variant[i], "/", s$subspec[i])

  # (3) accessibility is a non-negative rate; a negative one is not a small
  # error, it is a sign the arithmetic inverted somewhere
  for (col in c("national", "metro", "rural", "white", "aian")) {
    negi <- which(s[[col]] < 0)
    for (i in negi) bad("negative accessibility in ", col, " for ",
                        s$variant[i], "/", s$subspec[i], ": ", s[[col]][i])
    nai <- which(!is.finite(s[[col]]))
    for (i in nai) bad("non-finite accessibility in ", col, " for ",
                       s$variant[i], "/", s$subspec[i])
  }
  note("all accessibility values finite and non-negative")

  # (4) every specification must cover every subspecialty -- a ragged table
  # means a cell silently failed to compute
  tab <- table(s$variant)
  n_sub <- length(unique(s$subspec))
  for (v in names(tab)) if (tab[[v]] != n_sub)
    bad("variant '", v, "' has ", tab[[v]], " subspecialty rows, expected ", n_sub)
  note(length(tab), " specifications x ", n_sub, " subspecialties, complete")
}

# ---- spatial outcomes --------------------------------------------------------
if (!file.exists(SPAT)) {
  note("spatial outcomes artifact absent -- skipped: ", SPAT)
} else {
  p <- utils::read.csv(SPAT, stringsAsFactors = FALSE)
  cat("\nspatial_outcomes_2020.csv (", nrow(p), " rows)\n", sep = "")

  # (5) NESTED CATCHMENT MONOTONICITY. The 180-minute polygon contains the
  # 120-minute polygon, which contains the 60-minute one. So the population
  # OUTSIDE a catchment can only shrink as the catchment grows. A violation is
  # geometrically impossible and would indicate the bands were mixed up.
  m1 <- which(p$pct_outside_120 > p$pct_outside_60 + TOL)
  m2 <- which(p$pct_outside_180 > p$pct_outside_120 + TOL)
  for (i in m1) bad("monotonicity violated for ", p$subspec[i],
                    ": pct_outside_120 (", p$pct_outside_120[i],
                    ") > pct_outside_60 (", p$pct_outside_60[i],
                    ") -- nested catchments cannot exclude MORE people as they grow")
  for (i in m2) bad("monotonicity violated for ", p$subspec[i],
                    ": pct_outside_180 (", p$pct_outside_180[i],
                    ") > pct_outside_120 (", p$pct_outside_120[i], ")")
  note("nested-catchment monotonicity holds for all ", nrow(p), " subspecialties")

  # (6) shares are percentages; Gini is a proportion
  for (col in c("pct_outside_60", "pct_outside_120", "pct_outside_180")) {
    oob <- which(p[[col]] < 0 | p[[col]] > 100)
    for (i in oob) bad(col, " out of [0,100] for ", p$subspec[i], ": ", p[[col]][i])
  }
  oob <- which(p$gini < 0 | p$gini > 1)
  for (i in oob) bad("gini out of [0,1] for ", p$subspec[i], ": ", p$gini[i])
  note("all shares within [0,100] and Gini within [0,1]")

  # (7) an order statistic cannot exceed the median it sits below
  q <- which(p$p10_access > p$median_access + TOL)
  for (i in q) bad("p10_access exceeds median_access for ", p$subspec[i],
                   " -- an order statistic is inverted")
  note("p10 <= median for all subspecialties")
}

# ---- cross-artifact agreement ------------------------------------------------
# The same scientific quantity appearing in two independently produced artifacts
# must agree. If it does not, at least one is stale, and the manuscript reads
# both.
if (file.exists(SENS) && file.exists(SPAT)) {
  s <- utils::read.csv(SENS, stringsAsFactors = FALSE)
  p <- utils::read.csv(SPAT, stringsAsFactors = FALSE)
  base <- s[s$variant == "base", ]
  common <- intersect(base$subspec, p$subspec)
  cat("\ncross-artifact agreement (", length(common), " subspecialties)\n", sep = "")
  worst <- 0; worst_s <- NA_character_
  for (sub in common) {
    a <- base$national[base$subspec == sub]
    b <- p$national_mean[p$subspec == sub]
    ra <- base$res[base$subspec == sub]; rb <- p$res[p$subspec == sub]
    if (length(a) != 1 || length(b) != 1) next
    rel <- abs(a - b) / max(abs(a), .Machine$double.eps)
    if (rel > worst) { worst <- rel; worst_s <- sub }
    # Different grid resolutions are a legitimate reason to differ, so only
    # compare like with like; otherwise report rather than fail.
    if (isTRUE(ra == rb) && rel > 1e-6)
      bad("national mean access for ", sub, " disagrees between artifacts at the same ",
          "resolution (", ra, "m): sensitivity ", signif(a, 8), " vs spatial_outcomes ",
          signif(b, 8))
  }
  note("worst relative difference: ", signif(worst, 3), " (", worst_s, ")")
  if (!identical(sort(unique(base$res)), sort(unique(p$res))))
    note("NOTE: artifacts were produced at different grid resolutions (",
         paste(unique(base$res), collapse = "/"), " vs ",
         paste(unique(p$res), collapse = "/"),
         ") -- level comparison across them is not expected to be exact")
}

# ---- national summary: the file the manuscript actually reads ----------------
# Nothing checked this artifact. The two above are sensitivity and spatial
# outputs; the reported headline numbers come from e2sfca_national_summary.csv,
# and its only guard was scientific_diff.R's sha256. A hash catches TAMPERING.
# It cannot catch a wrongly REGENERATED file -- new run, new hash, honest
# intent, impossible numbers -- which is the case that actually threatens the
# paper. Every check below is an identity or inequality that must hold for any
# valid run, and each is exercised by tools/ci/data_adversarial_corpus.R.
NSUM <- "artifacts/2sfca/ec2/e2sfca_20260712_190734/e2sfca_national_summary.csv"
if (!file.exists(NSUM)) {
  bad("frozen national summary missing: ", NSUM)
} else {
  n <- utils::read.csv(NSUM, stringsAsFactors = FALSE)
  cat("\ne2sfca_national_summary.csv (", nrow(n), " rows)\n", sep = "")
  SH <- c("share_ge_0", "share_ge_1", "share_ge_5",
          "share_ge_10", "share_ge_20", "share_ge_50")
  needed <- c("subspecialty", "year", "n_cells_total", "n_cells_valid",
              "pop_raster_total", "acs_pop_source", "pop_valid_total",
              "pop_excluded_missing_access", "pop_excluded_missing_pop",
              "mean_pop_weighted_per100k", SH)
  miss <- setdiff(needed, names(n))
  if (length(miss)) {
    bad("national summary is missing column(s): ", paste(miss, collapse = ", "))
  } else {

    # (a) one row per (subspecialty, year). A duplicate double-counts that cell
    # in every aggregate without changing any individual value.
    key <- paste(n$subspecialty, n$year)
    if (any(duplicated(key)))
      bad("national summary has duplicate (subspecialty, year) rows: ",
          paste(unique(key[duplicated(key)]), collapse = ", "))

    # (b) rectangular. A missing cell drops silently out of every mean and
    # every trend while the remaining years still look self-consistent.
    tb <- table(n$subspecialty)
    if (length(unique(as.integer(tb))) != 1L)
      bad("national summary is ragged -- subspecialties have different year ",
          "counts: ", paste(sprintf("%s=%d", names(tb), as.integer(tb)),
                            collapse = ", "))
    yrs <- sort(unique(n$year))
    if (length(yrs) > 1L && any(diff(yrs) != 1L))
      bad("national summary years are not contiguous: ",
          paste(yrs, collapse = ", "))

    # (c) accessibility is supply over demand; it cannot be negative.
    if (any(n$mean_pop_weighted_per100k < 0, na.rm = TRUE))
      bad("negative mean access in the national summary")
    if (any(is.na(n$mean_pop_weighted_per100k)))
      bad("missing mean access in the national summary")

    # (d) population shares are shares.
    sv <- unlist(n[SH])
    if (any(sv < -TOL | sv > 1 + TOL, na.rm = TRUE))
      bad("population share outside [0, 1] in the national summary")

    # (e) shares must be NON-INCREASING in the threshold: the population at or
    # above a higher access level cannot exceed the population above a lower
    # one. Arithmetically impossible to violate in a valid run.
    dv <- apply(as.matrix(n[SH]), 1, function(r) any(diff(r) > TOL))
    if (any(dv, na.rm = TRUE))
      bad(sum(dv, na.rm = TRUE), " row(s) have non-monotone threshold shares ",
          "(e.g. share_ge_5 > share_ge_1)")

    # (f) valid + excluded == raster total. Breaking it means population
    # vanished silently -- the failure mode that made the reproduction attempt
    # land 0.786% below the published mean.
    accounted <- n$pop_valid_total + n$pop_excluded_missing_access +
                 n$pop_excluded_missing_pop
    rel <- abs(accounted - n$pop_raster_total) / pmax(n$pop_raster_total, 1)
    if (any(rel > 1e-9, na.rm = TRUE))
      bad("population is not conserved in ", sum(rel > 1e-9, na.rm = TRUE),
          " row(s): valid + excluded != raster total (worst rel ",
          signif(max(rel, na.rm = TRUE), 3), ")")

    # (g2) the rasterised population must reconcile with the ACS total it
    # claims to come from. If it does not, the demand denominator is not the
    # population the paper describes, and every accessibility value is
    # rescaled without any access number changing.
    rel_src <- abs(n$pop_raster_total - n$acs_pop_source) /
               pmax(abs(n$acs_pop_source), 1)
    if (any(rel_src > 1e-6, na.rm = TRUE))
      bad("pop_raster_total diverges from acs_pop_source in ",
          sum(rel_src > 1e-6, na.rm = TRUE), " row(s) (worst rel ",
          signif(max(rel_src, na.rm = TRUE), 3), ")")

    # (g) cells cannot be more valid than they are.
    if (any(n$n_cells_valid > n$n_cells_total, na.rm = TRUE))
      bad("n_cells_valid exceeds n_cells_total")

    note("rows ", nrow(n), ", subspecialties ", length(unique(n$subspecialty)),
         ", years ", min(yrs), "-", max(yrs))
    note("population conservation worst relative error: ",
         signif(max(rel, na.rm = TRUE), 3))

    # (h) CROSS-ARTIFACT AGREEMENT. The checks above are all internal, so a
    # corruption that keeps the table structurally valid -- inflating one mean,
    # or swapping two subspecialty labels -- passes every one of them. The
    # sensitivity artifact's `base` variant computes 2020 national means by an
    # independent route, so it can be compared. Natural disagreement is ~5e-4
    # (different grid resolutions); 1% is far above that and far below any
    # corruption worth catching.
    if (file.exists(SENS)) {
      sb <- utils::read.csv(SENS, stringsAsFactors = FALSE)
      sb <- sb[sb$variant == "base", c("subspec", "national")]
      n20 <- n[n$year == 2020, c("subspecialty", "mean_pop_weighted_per100k")]
      mm <- merge(sb, n20, by.x = "subspec", by.y = "subspecialty")
      if (nrow(mm) == 0L) {
        bad("no subspecialty in common between the national summary's 2020 rows ",
            "and the sensitivity base variant -- the labels cannot both be right")
      } else {
        if (nrow(mm) != nrow(sb))
          bad("national summary 2020 covers ", nrow(mm), " of ", nrow(sb),
              " subspecialties present in the sensitivity base variant")
        r2 <- abs(mm$national - mm$mean_pop_weighted_per100k) /
              pmax(abs(mm$mean_pop_weighted_per100k), .Machine$double.eps)
        AGREE_TOL <- 1e-2
        if (any(r2 > AGREE_TOL, na.rm = TRUE)) {
          w <- mm$subspec[which(r2 > AGREE_TOL)]
          bad("national summary disagrees with the independently produced ",
              "sensitivity base variant for ", paste(w, collapse = ", "),
              " (worst rel ", signif(max(r2, na.rm = TRUE), 3),
              ", tolerance ", AGREE_TOL, ")")
        }
        note("agreement with sensitivity base variant, worst relative: ",
             signif(max(r2, na.rm = TRUE), 3))
      }
    }
  }
}

cat("\n")
if (length(fail)) {
  message("FAIL: the frozen artifacts violate scientific invariants:")
  for (f in fail) message("  - ", f)
  message("\n  These are identities and inequalities that must hold for ANY valid run.",
          "\n  A violation means a published number cannot be right, independently of",
          "\n  whether the method or the data are correct.")
  quit(status = 1L, save = "no")
}
cat("every frozen-artifact invariant holds\n")
