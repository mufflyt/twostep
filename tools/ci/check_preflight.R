#!/usr/bin/env Rscript
# Repository preflight. Cheap structural checks that must hold before it is worth
# spending 20 minutes installing a geospatial stack. Base R only.
fails <- character(0)
note  <- function(...) cat(...,"\n", sep = "")
bad   <- function(...) fails <<- c(fails, paste0(...))

git <- function(...) system2("git", c(...), stdout = TRUE, stderr = FALSE)
tracked <- git("ls-files")

# --- DESCRIPTION is parseable and complete --------------------------------------
d <- tryCatch(read.dcf("DESCRIPTION")[1, ], error = function(e) NULL)
if (is.null(d)) {
  bad("DESCRIPTION does not parse")
} else {
  required <- c("Package", "Version", "Title", "Description", "License", "Encoding")
  miss <- required[!required %in% names(d)]
  if (length(miss)) bad("DESCRIPTION missing field(s): ", paste(miss, collapse = ", "))
  if (!is.null(d[["Version"]]) &&
      !grepl("^[0-9]+([.-][0-9]+)*$", d[["Version"]]))
    bad("DESCRIPTION Version is not a valid R version: ", d[["Version"]])
  note("DESCRIPTION: ", d[["Package"]], " ", d[["Version"]], " -- fields OK")
}

# --- expected layout ------------------------------------------------------------
expected <- c("R", "man", "tests/testthat", "tools/ci", ".github/workflows")
for (p in expected) if (!dir.exists(p)) bad("expected directory missing: ", p)
for (f in c("NAMESPACE", "renv.lock", "SHA256SUMS.txt", "tests/testthat.R"))
  if (!file.exists(f)) bad("expected file missing: ", f)
note("layout: ", length(expected), " directories and 4 anchor files present")

# --- unresolved merge conflict markers ------------------------------------------
# A committed "<<<<<<<" is silently valid in many file types and poisons whatever
# reads it. Restricted to text files so binaries are not scanned.
textish <- grep("[.](R|r|Rmd|md|txt|ya?ml|json|csv|cff|sh|Rproj)$", tracked, value = TRUE)
conflicted <- character(0)
for (f in textish) {
  if (!file.exists(f)) next
  ln <- tryCatch(readLines(f, warn = FALSE), error = function(e) character(0))
  if (any(grepl("^(<<<<<<< |>>>>>>> |={7}$)", ln))) conflicted <- c(conflicted, f)
}
# This script and any test that legitimately talks about markers are exempt.
conflicted <- setdiff(conflicted, "tools/ci/check_preflight.R")
if (length(conflicted)) bad("merge-conflict markers in: ", paste(conflicted, collapse = ", "))
note("scanned ", length(textish), " text files for conflict markers")

# --- case-colliding paths --------------------------------------------------------
# macOS and Windows are case-insensitive; two paths differing only in case make the
# repo un-checkoutable there.
lower <- tolower(tracked)
coll <- unique(lower[duplicated(lower)])
if (length(coll)) bad("case-colliding tracked paths: ", paste(coll, collapse = ", "))
note("no case-colliding paths among ", length(tracked), " tracked files")

# --- oversized tracked files -----------------------------------------------------
LIMIT_MB <- 25
sizes <- vapply(tracked, function(f) if (file.exists(f)) file.size(f) else 0, numeric(1))
huge <- tracked[sizes > LIMIT_MB * 1024^2]
if (length(huge))
  bad("tracked file(s) over ", LIMIT_MB, "MB: ",
      paste(sprintf("%s (%.1fMB)", huge, sizes[huge] / 1024^2), collapse = ", "))
note(sprintf("largest tracked file is %.1fMB (limit %dMB)", max(sizes) / 1024^2, LIMIT_MB))

# --- workflows reference only files that exist -----------------------------------
# A nightly that silently stops running because it calls a renamed script is itself
# a failure mode.
wf <- list.files(".github/workflows", pattern = "[.]ya?ml$", full.names = TRUE)
refs <- unique(unlist(lapply(wf, function(w) {
  ln <- readLines(w, warn = FALSE)
  m <- regmatches(ln, gregexpr("(?<=Rscript |bash )[A-Za-z0-9_./-]+[.](R|sh)", ln, perl = TRUE))
  unlist(m)
})))
# Only path-like references are repo paths. A bare filename is a script the
# workflow has already copied next to itself -- e.g. `cd "$RUNNER_TEMP/outside"`
# then `Rscript smoke_installed.R` -- and resolving it against the repo root
# would be a false positive.
refs <- refs[grepl("/", refs, fixed = TRUE)]
missing_refs <- refs[!file.exists(refs)]
if (length(missing_refs))
  bad("workflow references non-existent script(s): ", paste(missing_refs, collapse = ", "))
note("workflows reference ", length(refs), " scripts, all present")

# --- workflow YAML is at least structurally sane ---------------------------------
for (w in wf) {
  ln <- readLines(w, warn = FALSE)
  if (!any(grepl("^jobs:", ln))) bad(w, ": no jobs: block")
  if (any(grepl("\t", ln))) bad(w, ": contains a TAB character, which YAML forbids for indentation")
}
note("checked ", length(wf), " workflow file(s)")

if (length(fails)) {
  message("\nFAIL: preflight found ", length(fails), " problem(s):")
  for (f in fails) message("  - ", f)
  quit(status = 1L, save = "no")
}
cat("\npreflight OK\n")
