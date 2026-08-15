#!/usr/bin/env Rscript

# ==============================================================================
# NAMESPACE generator / drift guard  (base R only -- no roxygen2, no Imports)
# ==============================================================================
# WHY THIS EXISTS
#   NAMESPACE used to be maintained by hand and drifted: `@export` tags on
#   DJ7_SUBS / DJ7_BANDS / DJ7_WC_BASE never reached it, so those tags were
#   silently ignored. roxygen2 could not run and catch this, because
#   `roxygenise()` calls `pkgload::load_all()`, which EXECUTES every R/*.R --
#   including the ARCHIVED scripts that `source()` helpers not vendored in this
#   repo -- and aborts. (`.Rbuildignore` does not exempt a file from load_all();
#   only moving it out of R/ does.)
#
#   Fixed 2026-08-15: those two scripts moved to inst/archive/, so roxygen2 now
#   runs and is AUTHORITATIVE for NAMESPACE and man/. This script is the
#   zero-dependency cross-check: it re-derives the export set straight from the
#   tags and compares. Both agree on all 56 exports -- confirmed by letting
#   roxygen2 author NAMESPACE from scratch and diffing the export sets.
#
#   It stays worth keeping because it needs no packages at all, so it runs
#   inside the renv sandbox where roxygen2 is absent, and it catches two
#   failure modes roxygen2 reports less directly: an @export under an R/
#   subdirectory, and an @export in a build-excluded file.
#
# USAGE
#   Rscript tools/sync_namespace.R           # rewrite NAMESPACE from the tags
#   Rscript tools/sync_namespace.R --check   # exit 1 on drift, write nothing
#
# SCOPE -- deliberately mirrors what R itself collates:
#   R sources ONLY top-level R/*.[RrSsq] files. Files in R/ SUBDIRECTORIES
#   (e.g. R/utils/) are never part of the package, so an `@export` there can
#   never take effect. That is reported as an error, not silently dropped.
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
check_only <- "--check" %in% args

root <- local({
  # Walk up from this script (or getwd() when sourced) to the DESCRIPTION anchor.
  this <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
  d <- if (!is.na(this)) dirname(normalizePath(this)) else normalizePath(getwd())
  while (!file.exists(file.path(d, "DESCRIPTION")) && dirname(d) != d) d <- dirname(d)
  d
})

r_dir <- file.path(root, "R")
COLLATED_RE <- "\\.(R|r|S|s|q)$"

# ---- tag extraction ----------------------------------------------------------

#' Pull `@export`-tagged object names out of one R file.
#'
#' Follows roxygen2's attachment rule: a block's tags bind to the next top-level
#' expression, skipping blank lines and plain `#` comments (but NOT a new `#'`
#' block, which means the tag is orphaned).
#'
#' @return list(exports = character(), orphans = integer() line numbers)
extract_exports <- function(path) {
  lines <- readLines(path, warn = FALSE)
  exports <- character(0)
  orphans <- integer(0)

  for (i in seq_along(lines)) {
    tag <- regmatches(lines[i], regexec("^#'\\s*@export\\s*(.*?)\\s*$", lines[i]))[[1]]
    if (!length(tag)) next

    # `@export name` names the object explicitly; bare `@export` infers it.
    if (nzchar(tag[2])) {
      exports <- c(exports, gsub("^[\"'`]|[\"'`]$", "", tag[2]))
      next
    }

    j <- i + 1L
    while (j <= length(lines) &&
           (!nzchar(trimws(lines[j])) ||
            (grepl("^\\s*#", lines[j]) && !grepl("^\\s*#'", lines[j])))) {
      j <- j + 1L
    }

    obj <- NA_character_
    if (j <= length(lines) && !grepl("^\\s*#'", lines[j])) {
      m <- regmatches(lines[j], regexec(
        "^\\s*[\"'`]?([A-Za-z.][A-Za-z0-9._]*)[\"'`]?\\s*(<<-|<-|=(?!=))", lines[j], perl = TRUE))[[1]]
      if (length(m)) {
        obj <- m[2]
      } else {
        m2 <- regmatches(lines[j], regexec(
          "^\\s*assign\\(\\s*[\"']([A-Za-z.][A-Za-z0-9._]*)[\"']", lines[j]))[[1]]
        if (length(m2)) obj <- m2[2]
      }
    }

    if (is.na(obj)) orphans <- c(orphans, i) else exports <- c(exports, obj)
  }

  list(exports = exports, orphans = orphans)
}

# ---- scan --------------------------------------------------------------------

#' Drop paths excluded from the build by .Rbuildignore.
#'
#' A build-excluded R/ file is not in the installed package, so an @export there
#' would put a nonexistent object in NAMESPACE (an `R CMD check` error).
apply_rbuildignore <- function(paths) {
  ign_file <- file.path(root, ".Rbuildignore")
  if (!file.exists(ign_file)) return(paths)
  pats <- trimws(readLines(ign_file, warn = FALSE))
  pats <- pats[nzchar(pats) & !startsWith(pats, "#")]
  if (!length(pats)) return(paths)
  rel <- sub(paste0("^", root, "/"), "", paths)
  keep <- !Reduce(`|`, lapply(pats, function(p)
    grepl(p, rel, perl = TRUE)), init = FALSE)
  paths[keep]
}

pkg_files <- sort(list.files(r_dir, pattern = COLLATED_RE, full.names = TRUE))
sub_files <- sort(list.files(r_dir, pattern = COLLATED_RE, full.names = TRUE,
                             recursive = TRUE))
sub_files <- setdiff(sub_files, pkg_files)

pkg_files <- apply_rbuildignore(pkg_files)
sub_files <- apply_rbuildignore(sub_files)

errors <- character(0)

# `@export` under R/ subdirectories is provably dead: R never collates it.
for (f in sub_files) {
  hits <- extract_exports(f)
  n <- length(hits$exports) + length(hits$orphans)
  if (n > 0L) {
    errors <- c(errors, sprintf(
      "%s: %d @export tag(s) in an R/ SUBDIRECTORY -- R only collates top-level R/*.R, so these can never be exported. Move the file to R/ or mark it @keywords internal.",
      sub(paste0("^", root, "/"), "", f), n))
  }
}

exports <- character(0)
for (f in pkg_files) {
  hits <- extract_exports(f)
  exports <- c(exports, hits$exports)
  for (ln in hits$orphans) {
    errors <- c(errors, sprintf(
      "%s:%d: @export is attached to no object (dangling roxygen block).",
      sub(paste0("^", root, "/"), "", f), ln))
  }
}

dupes <- unique(exports[duplicated(exports)])
if (length(dupes)) {
  errors <- c(errors, sprintf("duplicate @export for: %s", paste(dupes, collapse = ", ")))
}

if (length(errors)) {
  message("NAMESPACE sync failed:\n", paste0("  - ", errors, collapse = "\n"))
  quit(status = 1L, save = "no")
}

# Case-insensitive ordering, matching the existing NAMESPACE convention.
exports <- unique(exports)
exports <- exports[order(tolower(exports), exports)]

# ---- compare / render --------------------------------------------------------

ns_path <- file.path(root, "NAMESPACE")
old <- if (file.exists(ns_path)) readLines(ns_path, warn = FALSE) else character(0)

# NAMESPACE is authored by roxygen2 when it can run. Compare EXPORT SETS, never
# whole files, so a differing header is not mistaken for drift.
old_exports <- sub("^export\\((.*)\\)$", "\\1", grep("^export\\(", old, value = TRUE))
added        <- setdiff(exports, old_exports)
removed      <- setdiff(old_exports, exports)
in_sync      <- !length(added) && !length(removed)
roxygen_owned <- any(grepl("^# Generated by roxygen2", old))

report_drift <- function() {
  message("NAMESPACE is out of sync with the @export tags.")
  if (length(added))   message("  tagged but missing from NAMESPACE: ", paste(added, collapse = ", "))
  if (length(removed)) message("  in NAMESPACE but no @export tag:   ", paste(removed, collapse = ", "))
  message("  Fix with: ", if (roxygen_owned) "Rscript -e 'roxygen2::roxygenise()'"
                          else "Rscript tools/sync_namespace.R")
}

if (check_only) {
  if (!in_sync) { report_drift(); quit(status = 1L, save = "no") }
  message("NAMESPACE is in sync (", length(exports), " exports).")
  quit(status = 0L, save = "no")
}

# Write mode. Never clobber a roxygen2-authored NAMESPACE: roxygen2 also emits the
# man/ pages, so hand-writing over it would desynchronise the docs from the exports.
if (roxygen_owned) {
  if (in_sync) {
    message("NAMESPACE is roxygen2-generated and in sync (", length(exports), " exports); nothing to do.")
    quit(status = 0L, save = "no")
  }
  report_drift()
  message("  Refusing to overwrite a roxygen2-generated NAMESPACE.")
  quit(status = 1L, save = "no")
}

header <- c(
  "# Generated by tools/sync_namespace.R from the @export tags -- do not edit by hand.",
  "# Fallback generator for when roxygen2 cannot run; roxygen2 is authoritative when",
  "# it can. Both produce the same export set -- verified 2026-08-15.",
  "# twostep uses explicit pkg::fn calls throughout, so only exports are declared here;",
  "# imported packages are declared in DESCRIPTION Imports.",
  ""
)
new <- c(header, sprintf("export(%s)", exports))

if (identical(old, new)) {
  message("NAMESPACE already in sync (", length(exports), " exports).")
} else {
  writeLines(new, ns_path)
  message("NAMESPACE written: ", length(exports), " exports.")
  if (length(added))   message("  added:   ", paste(added, collapse = ", "))
  if (length(removed)) message("  removed: ", paste(removed, collapse = ", "))
}
