#!/usr/bin/env Rscript
# renv.lock integrity. Fails if the lockfile is unparseable, has duplicate or
# malformed records, or omits a package DESCRIPTION declares as a hard Import.
# Suggests are NOT required to be present: .renvignore deliberately keeps the
# reference-only modules' heavy deps out of the lock.
if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("check_lockfile.R needs jsonlite", call. = FALSE)

fail <- function(...) { message("FAIL: ", ...); quit(status = 1L, save = "no") }

lock <- tryCatch(jsonlite::fromJSON("renv.lock", simplifyVector = FALSE),
                 error = function(e) fail("renv.lock is not valid JSON: ", conditionMessage(e)))
pkgs <- lock$Packages
if (!length(pkgs)) fail("renv.lock records no packages")

dup <- names(pkgs)[duplicated(names(pkgs))]
if (length(dup)) fail("duplicate lockfile records: ", paste(dup, collapse = ", "))

# Every record needs the fields renv::restore() actually consumes.
bad <- Filter(function(p) {
  r <- pkgs[[p]]
  is.null(r$Package) || is.null(r$Version) || is.null(r$Source)
}, names(pkgs))
if (length(bad)) fail("records missing Package/Version/Source: ", paste(bad, collapse = ", "))

mismatch <- Filter(function(p) !identical(pkgs[[p]]$Package, p), names(pkgs))
if (length(mismatch)) fail("record key does not match its Package field: ",
                           paste(mismatch, collapse = ", "))

d <- read.dcf("DESCRIPTION")[1, ]
parse_deps <- function(field) {
  if (is.na(d[[field]] %||% NA)) return(character(0))
  v <- trimws(gsub("\\(.*?\\)", "", strsplit(d[[field]], ",")[[1]]))
  setdiff(v[nzchar(v)], "R")
}
`%||%` <- function(a, b) if (is.null(a)) b else a
imports <- parse_deps("Imports")
missing <- setdiff(imports, names(pkgs))
if (length(missing)) fail("DESCRIPTION Imports absent from renv.lock: ",
                          paste(missing, collapse = ", "))

cat(sprintf("renv.lock OK: %d records, all %d hard Imports pinned\n",
            length(pkgs), length(imports)))
