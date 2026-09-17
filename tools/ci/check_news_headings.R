#!/usr/bin/env Rscript
# =============================================================================
# NEWS.md headings must not accidentally look like version numbers
# =============================================================================
# R CMD check --as-cran parses NEWS.md, and the way it decides which heading
# level marks a RELEASE is easy to break by accident:
#
#   re_v <- "(^|.*[[:space:]]+)[vV]?(([[:digit:]]+[.-]){1,}[[:digit:]]+).*$"
#   while (length(pos) && !grepl(re_v, text(nodes[[pos[1]]]))) pos <- pos[-1]
#   lev <- level(nodes[pos]); ind[pos] <- (lev == lev[1])
#                                      -- tools:::.build_news_db_from_package_NEWS_md
#
# It walks headings until it finds the FIRST one containing something that looks
# like a version, and adopts THAT heading's level as the release level. Every
# other heading at that level is then expected to name a version too.
#
# `2013-2023` satisfies `([[:digit:]]+[.-]){1,}[[:digit:]]+`. So the heading
#
#     ## Age-matched denominators: the full 2013-2023 panel
#
# was read as a release, level 2 became the release level, and all twenty `##`
# topic headings became malformed release titles at once:
#
#     Problems with news in 'NEWS.md':
#       Cannot extract version info from the following section titles: ...
#
# That is a NOTE, the nightly runs check with error_on = "note", and it failed
# all five R CMD check platforms simultaneously -- roughly seven minutes of CI to
# learn something this file establishes in milliseconds. A study year range in a
# heading is an entirely natural thing to write, so it will be written again.
#
# Rule: the first heading in NEWS.md that matches R's version pattern must be a
# level-1 heading.
#
# Usage: Rscript tools/ci/check_news_headings.R
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status = 1L) }
if (!file.exists("NEWS.md"))     { cat("no NEWS.md; skipped\n"); quit(status = 0L) }

md <- readLines("NEWS.md", warn = FALSE)

# ATX headings only, and not inside fenced code -- a "## " in a shell block is
# not a heading, and flagging it would train people to ignore this check.
fence <- cumsum(grepl("^\\s*```", md)) %% 2L
is_h  <- grepl("^#{1,6}[[:space:]]", md) & fence == 0L
idx   <- which(is_h)
if (!length(idx)) { cat("NEWS.md has no headings\n"); quit(status = 0L) }

lev  <- nchar(sub("^(#+).*$", "\\1", md[idx]))
text <- sub("^#+[[:space:]]*", "", md[idx])

re_v <- sprintf("(^|.*[[:space:]]+)[vV]?(%s).*$", .standard_regexps()$valid_package_version)
hit  <- grepl(re_v, text)

cat("NEWS.md heading audit\n")
cat("  headings: ", length(idx), "   version-shaped: ", sum(hit), "\n", sep = "")

if (!any(hit)) {
  cat("  no heading names a version; R CMD check will not build a news db\n")
  quit(status = 0L)
}

first <- which(hit)[1L]
cat("  first version-shaped heading: line ", idx[first], ", level ", lev[first],
    "\n    ", text[first], "\n", sep = "")

if (lev[first] != 1L) {
  message("FAIL: NEWS.md line ", idx[first], " is a level-", lev[first],
          " heading that R reads as a release:")
  message("  ", text[first])
  message("\n  R adopts this heading's level as the release level, so every other",
          "\n  level-", lev[first], " heading becomes a malformed release title and R CMD check",
          "\n  --as-cran emits a NOTE. The nightly treats NOTEs as failures.",
          "\n\n  It matched: ", .standard_regexps()$valid_package_version,
          "\n  A year range like 2013-2023 is the usual culprit -- write it as",
          "\n  \"2013 to 2023\", or reword (\"the full eleven-year panel\").")
  quit(status = 1L, save = "no")
}
cat("  ok: releases are level-1 headings\n")
