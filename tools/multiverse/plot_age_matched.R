#!/usr/bin/env Rscript
# =============================================================================
# SDC figure: age-matched versus all-ages demand denominators
# =============================================================================
# DESIGN CONSTRAINT, and the reason this is not a simple bar chart of access:
# the two regimes have DIFFERENT DENOMINATORS and are therefore different
# estimands. Plotting their national means side by side would invite exactly the
# misreading the appendix forbids -- "access doubled" is arithmetic, not a
# finding. Halving a denominator roughly doubles the value.
#
# Three things ARE comparable across regimes, and each gets a panel:
#
#   A  DENOMINATOR RETAINED -- the mechanism. What share of the all-ages female
#      population each age window keeps. This is why all-ages indexing distorts:
#      a subspecialty measured against four times its candidate population looks
#      four times less accessible than it is.
#
#   B  CONTRAST RATIOS -- the result. Rural:metropolitan and AIAN:White, paired
#      within subspecialty, all-ages to age-matched. A flat line means the
#      disparity does not depend on the denominator. A line crossing 1.0 is a
#      reversal. Ratios are dimensionless, so this comparison is legitimate.
#
#   C  RANK ORDER -- claim C5. Levels are not comparable but RANK is, so the
#      ordering can be compared honestly even when the values cannot.
#
# Usage: Rscript tools/multiverse/plot_age_matched.R
suppressWarnings(suppressMessages({ library(yaml) }))
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")), error = function(e) ".")
setwd(root)

# The panel is the single source. 2020 rows are selected below; there is no
# fallback to the standalone file.
RES <- "artifacts/2sfca/agematched_panel/age_matched_panel.csv"
if (!file.exists(RES))
  stop("the age-matched panel is missing: ", RES,
       "\n  It is the sole source for this figure; there is no fallback.", call. = FALSE)
res <- utils::read.csv(RES, stringsAsFactors = FALSE)
# The panel spans 2013-2023; this figure is the 2020 cross-section, matching the
# manuscript table. Without this filter rownames() below would collide across
# eleven years and silently plot whichever row happened to land last.
if ("year" %in% names(res)) res <- res[res$year == 2020L, , drop = FALSE]
stopifnot(nrow(res) == 14L)
man <- yaml::read_yaml("inst/multiverse/age_matched_denominator.yml")
win <- setNames(vapply(man$subspecialties, function(s) s$age_range, character(1)),
                vapply(man$subspecialties, function(s) s$code, character(1)))

ORD <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")   # manifest order, fixed in advance
aa  <- res[res$regime == "all_ages",    ]; rownames(aa) <- aa$subspec
am  <- res[res$regime == "age_matched", ]; rownames(am) <- am$subspec
ORD <- ORD[ORD %in% aa$subspec & ORD %in% am$subspec]
cols <- grDevices::hcl.colors(length(ORD), "Dark 3")
names(cols) <- ORD

# The figure lives beside the document, not in artifacts/, so a submitted
# supplement carries its own figure and there is no manual copy step to drift.
out <- "manuscript/figures/fig_age_matched_denominators.jpg"
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
grDevices::jpeg(out, width = 2400, height = 900, res = 200, quality = 96)
on.exit(grDevices::dev.off(), add = TRUE)
graphics::layout(matrix(1:3, nrow = 1), widths = c(1, 1.25, 1))
graphics::par(mar = c(7.5, 4.6, 3.4, 1.2))

## ---- Panel A: denominator retained -----------------------------------------
allages <- aa$denominator[1]
share   <- vapply(ORD, function(k) 100 * am[k, "denominator"] / allages, numeric(1))
bp <- graphics::barplot(share, names.arg = rep("", length(ORD)), col = cols[ORD],
                        border = NA, ylim = c(0, 100), ylab = "percent of all-ages female population",
                        main = "A. Denominator retained\nby the age window", cex.main = 0.98)
graphics::text(bp, share + 3, sprintf("%.0f%%", share), cex = 0.72)
graphics::axis(1, at = bp, labels = sprintf("%s\n%s", ORD, win[ORD]),
               las = 2, cex.axis = 0.62, tick = FALSE, line = -0.4)
graphics::mtext("all-ages indexing measures every subspecialty against 100%",
                side = 3, line = 0.1, cex = 0.55, col = "grey35")

## ---- Panel B: contrast ratios, paired --------------------------------------
graphics::par(mar = c(7.5, 4.6, 3.4, 6.5))
  # xpd stays FALSE: with xpd = NA the parity line below drew across all three
  # panels, putting a horizontal rule through the bar chart that meant nothing.
rng <- range(c(aa$rural_metro_ratio, am$rural_metro_ratio,
               aa$aian_white_ratio,  am$aian_white_ratio), na.rm = TRUE)
graphics::plot(NA, xlim = c(0.75, 4.25), ylim = c(min(rng, 0.9) * 0.92, max(rng, 1.05) * 1.06),
               xaxt = "n", xlab = "", ylab = "ratio (below 1 = disadvantage)",
               # "persist", not "unchanged": the qualitative disparities survive age matching,
# but the ratios themselves move -- up to 1.56% in the correction diff. The old
# title claimed more than the data supports.
                main = "B. Disparity contrasts persist\nunder age matching", cex.main = 0.98)
graphics::abline(h = 1, lty = 2, col = "grey35")
graphics::text(4.25, 1.008, "parity", pos = 4, cex = 0.6, col = "grey35", xpd = NA)
for (k in ORD) {
  graphics::segments(1, aa[k, "rural_metro_ratio"], 2, am[k, "rural_metro_ratio"],
                     col = cols[k], lwd = 2)
  graphics::points(c(1, 2), c(aa[k, "rural_metro_ratio"], am[k, "rural_metro_ratio"]),
                   pch = 19, col = cols[k], cex = 0.9)
  graphics::segments(3, aa[k, "aian_white_ratio"], 4, am[k, "aian_white_ratio"],
                     col = cols[k], lwd = 2)
  graphics::points(c(3, 4), c(aa[k, "aian_white_ratio"], am[k, "aian_white_ratio"]),
                   pch = 19, col = cols[k], cex = 0.9)
}
graphics::axis(1, at = 1:4, labels = c("all ages", "age-matched", "all ages", "age-matched"),
               las = 2, cex.axis = 0.66, tick = FALSE, line = -0.4)
graphics::mtext("rural : metropolitan", side = 1, line = 5.2, at = 1.5, cex = 0.62)
graphics::mtext("AIAN area : White area", side = 1, line = 5.2, at = 3.5, cex = 0.62)
graphics::legend("topright", inset = c(-0.30, 0), xpd = NA, legend = ORD, col = cols[ORD],
                 lwd = 2, bty = "n", cex = 0.66, title = "subspecialty")

## ---- Panel C: rank order ----------------------------------------------------
graphics::par(mar = c(7.5, 4.6, 3.4, 1.2))
# setNames: aa[ORD, "national"] returns an UNNAMED vector -- data-frame column
# extraction drops names -- so rank() gave an unnamed result and r_aa[k] was NA
# for every subspecialty. Panel C rendered as an empty box.
r_aa <- setNames(rank(-aa[ORD, "national"]), ORD)
r_am <- setNames(rank(-am[ORD, "national"]), ORD)
n <- length(ORD)
graphics::plot(NA, xlim = c(0.8, 2.2), ylim = c(n + 0.6, 0.4), xaxt = "n", yaxt = "n",
               xlab = "", ylab = "rank by national mean access",
               main = "C. Ordering: rank is comparable,\nlevels are not", cex.main = 0.98)
graphics::axis(2, at = 1:n, labels = 1:n, las = 1, cex.axis = 0.7)
for (k in ORD) {
  graphics::segments(1, r_aa[k], 2, r_am[k], col = cols[k], lwd = 2.4)
  graphics::points(c(1, 2), c(r_aa[k], r_am[k]), pch = 19, col = cols[k], cex = 1.1)
  graphics::text(0.95, r_aa[k], k, pos = 2, cex = 0.66, col = cols[k])
  graphics::text(2.05, r_am[k], k, pos = 4, cex = 0.66, col = cols[k])
}
graphics::axis(1, at = c(1, 2), labels = c("all ages", "age-matched"),
               las = 2, cex.axis = 0.7, tick = FALSE, line = -0.4)
moved <- sum(r_aa != r_am)
graphics::mtext(sprintf("%d of %d subspecialties change rank", moved, n),
                side = 3, line = 0.1, cex = 0.55, col = "grey35")

cat("wrote", out, "\n")
cat(sprintf("rank changes: %d of %d\n", moved, n))
