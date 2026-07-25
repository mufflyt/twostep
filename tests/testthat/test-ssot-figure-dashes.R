# ==============================================================================
# Style guard: no em-dash / en-dash in figure DISPLAY text.
#
# Project rule (standing, emphatic): user-facing text must never contain an em-dash
# (—) or en-dash (–); use hyphens, commas, or "to". Figure titles, subtitles,
# and captions are rendered into published figures, so they are the highest-value
# surface for this rule. This guard scans the figure/map/stratify scripts and fails if
# any DISPLAY string (a non-comment line invoking a plotting/label function) contains
# either glyph.
#
# SCOPE: display lines only (labs/ggtitle/title/subtitle/caption/annotate/
# plot_annotation/mk_map). Console-log strings (say()/cat()/message()) and code
# comments are a separate, lower-priority cleanup and are intentionally out of scope.
# The engine R/two_step_floating_catchment.R is sha-gated and never scanned/edited.
# ==============================================================================
library(testthat)

root <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))

EN_EM <- "–|—"
DISPLAY_KW <- "labs\\(|ggtitle|plot_annotation|annotate\\(|mk_map|title\\s*=|subtitle\\s*=|caption\\s*="

test_that("no figure display string contains an em-dash or en-dash", {
  files <- list.files(file.path(root, "scripts"), pattern = "[.]R$",
                      full.names = TRUE, recursive = TRUE)
  offenders <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    for (i in seq_along(lines)) {
      ln <- lines[i]
      if (grepl("^\\s*#", ln)) next                 # skip comments
      if (!grepl(DISPLAY_KW, ln)) next              # only display-function lines
      if (grepl(EN_EM, ln))
        offenders <- c(offenders, sprintf("%s:%d", basename(f), i))
    }
  }
  expect_true(length(offenders) == 0,
              info = paste("figure display strings with en/em dash:",
                           paste(offenders, collapse = " | ")))
})
