#!/usr/bin/env Rscript
# Specification-curve figures for the frozen multiverse.
#
# Ordering is FIXED IN ADVANCE by the manifest's specification order (S01..S07),
# never by which specification gives the most favourable answer. Two figures,
# not one: E2 and E3 are both ratios about 1, but the disparity they describe
# is different, and forcing them onto a shared axis would invite reading one as
# the other.
suppressWarnings(suppressMessages({ library(yaml) }))
root <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")), error = function(e) ".")
setwd(root)
OUT <- "artifacts/multiverse"
res <- utils::read.csv(file.path(OUT, "multiverse_results.csv"), stringsAsFactors = FALSE)
man <- yaml::read_yaml("inst/multiverse/specification_manifest.yml")

spec_order <- vapply(man$specifications, `[[`, character(1), "id")
exec <- res[res$status == "frozen" & !is.na(res$spec_value), ]
n_pipe <- length(unique(res$spec_id[res$status == "pipeline"]))

panel <- function(eid, ylab, title, refline, file) {
  d <- exec[exec$estimand == eid & exec$comparable == TRUE, ]
  if (!nrow(d)) return(invisible(NULL))
  d$spec_id <- factor(d$spec_id, levels = intersect(spec_order, unique(d$spec_id)))
  subs <- sort(unique(d$subspecialty))
  cols <- grDevices::hcl.colors(length(subs), "Dark 3")
  grDevices::jpeg(file, width = 1800, height = 1150, res = 190, quality = 95)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(7.5, 5.2, 4, 9.5), xpd = NA)
  xs <- as.integer(d$spec_id)
  graphics::plot(xs, d$spec_value, type = "n",
                 xlim = c(0.6, nlevels(d$spec_id) + 0.4),
                 ylim = range(c(d$spec_value, refline), na.rm = TRUE) * c(0.94, 1.06),
                 xaxt = "n", xlab = "", ylab = ylab, main = title, cex.main = 1.0)
  graphics::abline(h = refline, lty = 2, col = "grey35")
  graphics::text(nlevels(d$spec_id) + 0.45, refline,
                 if (refline == 1) "parity" else "manuscript threshold",
                 pos = 4, cex = 0.62, col = "grey35")
  prim <- which(levels(d$spec_id) == "S01")
  graphics::rect(prim - 0.42, graphics::par("usr")[3], prim + 0.42, graphics::par("usr")[4],
                 col = grDevices::adjustcolor("grey70", 0.22), border = NA)
  for (i in seq_along(subs)) {
    dd <- d[d$subspecialty == subs[i], ]
    graphics::points(as.integer(dd$spec_id), dd$spec_value, pch = 19, cex = 1.05, col = cols[i])
    graphics::lines(as.integer(dd$spec_id), dd$spec_value, col = grDevices::adjustcolor(cols[i], .45))
  }
  labs <- vapply(levels(d$spec_id), function(id) {
    s <- Filter(function(z) z$id == id, man$specifications)[[1]]
    paste0(id, "\n", s$variant, "\n(", s$axis, ")")
  }, character(1))
  graphics::axis(1, at = seq_along(labs), labels = labs, las = 2, cex.axis = 0.56, tick = FALSE, line = -0.4)
  graphics::legend("topright", inset = c(-0.19, 0), legend = subs, col = cols,
                   pch = 19, bty = "n", cex = 0.68, title = "subspecialty")
  graphics::mtext(sprintf("Primary analysis (S01) shaded. %d prespecified specifications not executable here; see manifest.", n_pipe),
                  side = 1, line = 6.1, cex = 0.6, adj = 0)
  invisible(file)
}

panel("E2", "rural : metropolitan access ratio",
      "Specification curve: rural-metropolitan disparity across prespecified specifications",
      0.5, file.path(OUT, "fig_speccurve_rural_metro.jpg"))
panel("E3", "AIAN-area : White-area access ratio",
      "Specification curve: AIAN-White area disparity across prespecified specifications",
      1.0, file.path(OUT, "fig_speccurve_aian_white.jpg"))
cat("figures written\n")
