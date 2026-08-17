#!/usr/bin/env Rscript
# =============================================================================
# Compare scientific fingerprints from two or more runs.
# =============================================================================
# Used two ways:
#
#   DETERMINISM       two independent R sessions on the same machine. Any
#                     difference at all is a defect: same inputs, same seeds,
#                     same code must give the same numbers. Tolerance 0.
#
#   CROSS-PLATFORM    Linux vs macOS vs Windows. Here bit-identity is the wrong
#                     demand -- GEOS and the C library legitimately differ in
#                     the last places -- so the question is whether the
#                     platforms agree to a tolerance far tighter than anything
#                     that could change a conclusion. A disagreement in the 8th
#                     digit is noise; one in the 3rd is a different study.
#
# Reports the WORST disagreeing value by name, not just a verdict, so a failure
# points at the quantity rather than the run.
#
# Usage:
#   Rscript tools/ci/compare_fingerprints.R --tolerance 0 a.json b.json
#   Rscript tools/ci/compare_fingerprints.R --tolerance 1e-9 fp-*/*.json

args <- commandArgs(trailingOnly = TRUE)
tol <- 0
i <- match("--tolerance", args)
if (!is.na(i)) { tol <- as.numeric(args[i + 1L]); args <- args[-c(i, i + 1L)] }
files <- args[file.exists(args)]
if (length(files) < 2L) {
  message("FAIL: need at least two fingerprint files; got ", length(files),
          ". A comparison job that silently compares one run to itself would ",
          "always pass.")
  quit(status = 1L, save = "no")
}

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("needs jsonlite", call. = FALSE)
fps <- lapply(files, jsonlite::fromJSON, simplifyVector = FALSE)
labs <- vapply(seq_along(fps), function(k) {
  p <- fps[[k]]$platform
  sprintf("%s (%s, R %s, GEOS %s)", basename(dirname(files[k])),
          p$os %||% "?", p$r_version %||% "?", p$geos %||% "?")
}, character(1))
`%||%` <- function(a, b) if (is.null(a)) b else a

cat("comparing ", length(fps), " fingerprints, tolerance ", format(tol), "\n", sep = "")
for (l in labs) cat("  - ", l, "\n", sep = "")

ref <- fps[[1]]$science
keys <- names(ref)
fails <- character(0)
worst <- list(diff = 0, what = NA_character_, a = NA_character_, b = NA_character_)

for (k in seq_along(fps)[-1]) {
  cur <- fps[[k]]$science
  if (!identical(sort(names(cur)), sort(names(ref)))) {
    fails <- c(fails, sprintf("%s reports a different set of science blocks", labs[k]))
    next
  }
  for (blk in keys) {
    a <- ref[[blk]]; b <- cur[[blk]]
    if (!identical(sort(names(a)), sort(names(b)))) {
      fails <- c(fails, sprintf("%s: block '%s' has different keys (%s vs %s)",
                                labs[k], blk, length(a), length(b)))
      next
    }
    for (nm in names(a)) {
      av <- a[[nm]]; bv <- b[[nm]]
      an <- suppressWarnings(as.numeric(av)); bn <- suppressWarnings(as.numeric(bv))
      if (is.na(an) || is.na(bn)) {          # non-numeric, e.g. reached TRUE/FALSE
        if (!identical(as.character(av), as.character(bv)))
          fails <- c(fails, sprintf("%s: %s$%s differs (%s vs %s)",
                                    labs[k], blk, nm, av, bv))
        next
      }
      d <- abs(an - bn)
      rel <- if (abs(an) > 0) d / abs(an) else d
      if (rel > worst$diff) worst <- list(diff = rel, what = paste0(blk, "$", nm),
                                          a = av, b = bv)
      if (rel > tol)
        fails <- c(fails, sprintf("%s: %s$%s relative diff %.3e (%s vs %s)",
                                  labs[k], blk, nm, rel, av, bv))
    }
  }
}

cat(sprintf("\nlargest relative disagreement: %.3e  at %s\n",
            worst$diff, worst$what %||% "(none)"))
if (!is.na(worst$what)) cat("  ", worst$a, "\n  ", worst$b, "\n", sep = "")

if (length(fails)) {
  message("\nFAIL: ", length(fails), " scientific value(s) disagree beyond tolerance ",
          format(tol), ":")
  for (f in utils::head(fails, 20)) message("  - ", f)
  if (length(fails) > 20) message("  ... and ", length(fails) - 20, " more")
  quit(status = 1L, save = "no")
}
cat("\nall fingerprints agree within tolerance\n")
