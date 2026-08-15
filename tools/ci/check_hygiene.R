#!/usr/bin/env Rscript
# Source-code hygiene for PACKAGE code (R/ only).
#
# These are the patterns that actually broke this repository. A top-level
# source() of a non-vendored helper made R CMD INSTALL fail at lazy-load, which
# made the ENTIRE package uninstallable and hid every other check behind it. The
# rest are the same class: package code reaching out to the filesystem, the
# search path or the user's library at load time.
#
# Scoped to R/. scripts/ and inst/scripts/ are executable analysis scripts where
# library() and setwd() are legitimate.
fails <- character(0)
files <- list.files("R", pattern = "[.][Rr]$", full.names = TRUE, recursive = TRUE)

# Patterns are checked against TOP-LEVEL lines (column 1), because that is what
# executes at package load. The same call inside a function body is fine.
rules <- list(
  list(re = "^source\\s*\\(",
       why = "top-level source() runs at package load and reads off disk relative to a working directory that will not exist for an installed package"),
  list(re = "^(library|require)\\s*\\(",
       why = "library() at load time attaches globally instead of importing; use Imports + pkg::fn or @importFrom"),
  list(re = "^setwd\\s*\\(",
       why = "setwd() at load time mutates the user's session"),
  list(re = "^install\\.packages\\s*\\(",
       why = "package code must never install into the user's library"),
  list(re = "^(q|quit)\\s*\\(",
       why = "quit() in package code kills the caller's R session"),
  list(re = "^\\.libPaths\\s*\\(",
       why = "package code must not rewrite the library search path")
)

for (f in files) {
  lines <- readLines(f, warn = FALSE)
  for (r in rules) {
    hit <- grep(r$re, lines)
    for (h in hit)
      fails <- c(fails, sprintf("%s:%d  %s\n      %s", f, h, trimws(lines[h]), r$why))
  }
}

# Absolute developer paths, anywhere in the line -- these are pure
# works-on-my-machine leaks.
for (f in files) {
  lines <- readLines(f, warn = FALSE)
  hit <- grep("[\"'](/Users/|/home/[a-z]|C:[\\\\/])", lines)
  hit <- hit[!grepl("^\\s*#", lines[hit])]
  for (h in hit)
    fails <- c(fails, sprintf("%s:%d  %s\n      absolute local path in package code",
                              f, h, trimws(lines[h])))
}

cat("scanned ", length(files), " package files for ", length(rules) + 1L,
    " hygiene rules\n", sep = "")
if (length(fails)) {
  message("FAIL: ", length(fails), " hygiene violation(s):")
  for (x in fails) message("  - ", x)
  quit(status = 1L, save = "no")
}
cat("no hygiene violations\n")
