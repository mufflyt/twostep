#!/usr/bin/env Rscript
# =============================================================================
# Unquoted heredocs: every $VAR that expands must be one the launcher defines
# =============================================================================
# `bash -n` cannot catch this. It parses syntax; it does not expand heredocs. So
# an R expression like `ref$variant` inside an UNQUOTED heredoc is silently
# treated as a shell variable, and under `set -u` the launcher dies at runtime
# with "variant: unbound variable" -- after provisioning an instance.
#
# That is exactly what happened: a gate rewrite dropped the \$ escaping the rest
# of the file uses, and the run reached "SSH up" and then died without ever
# pushing the remote script, leaving an idle instance billing.
#
# This check extracts each unquoted heredoc and requires every unescaped
# $IDENTIFIER in it to be a variable the enclosing script actually assigns.
# Anything else is either a typo or -- far more likely here -- a foreign
# language's syntax being eaten by the shell.
#
# Usage: Rscript tools/ci/check_launcher_heredoc.R [script ...]
args <- commandArgs(trailingOnly = TRUE)
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status=1L) }
files <- if (length(args)) args else Sys.glob("scripts/ec2_run_*.sh")
files <- files[file.exists(files)]
if (!length(files)) { cat("no launcher scripts found\n"); quit(status=0L) }

fail <- character(0); n_hd <- 0L
for (f in files) {
  x <- readLines(f, warn = FALSE)
  # variables the script assigns, plus shell builtins that are always defined
  # ALL assignments on a line, not just the first: the environment pins are
  # written as `EXP_R="4.5.1"; EXP_SF="1.1.1"; EXP_TERRA=...` on one line, and an
  # anchored regex sees only EXP_R. A checker that reports three false positives
  # is one people learn to ignore.
  assign_hits <- unlist(regmatches(x, gregexpr(
    "(^|[;&|]|\\s)\\s*(export\\s+)?[A-Za-z_][A-Za-z0-9_]*=", x)))
  assigned <- unique(c(
    trimws(gsub("[;&|]|export|=", "", assign_hits)),
    gsub("^\\s*for\\s+([A-Za-z_][A-Za-z0-9_]*)\\s+in.*$", "\\1",
         grep("^\\s*for\\s+[A-Za-z_][A-Za-z0-9_]*\\s+in", x, value = TRUE)),
    "HOME","PATH","USER","PWD","IFS","RANDOM","SECONDS","LINENO","BASH_SOURCE","FUNCNAME","REPLY"))
  starts <- grep("<<[A-Za-z_][A-Za-z0-9_]*\\s*$", x)          # UNQUOTED only
  for (s in starts) {
    delim <- sub(".*<<([A-Za-z_][A-Za-z0-9_]*)\\s*$", "\\1", x[s])
    ends <- which(grepl(paste0("^", delim, "\\s*$"), x))
    e <- ends[ends > s][1]; if (is.na(e)) next
    n_hd <- n_hd + 1L
    body <- x[(s + 1):(e - 1)]
    for (i in seq_along(body)) {
      # unescaped $IDENT  (a preceding backslash means it survives to the heredoc)
      hits <- regmatches(body[i], gregexpr("(^|[^\\\\])\\$\\{?([A-Za-z_][A-Za-z0-9_]*)", body[i]))[[1]]
      for (h in hits) {
        v <- sub("^.*\\$\\{?", "", h)
        if (!v %in% assigned)
          fail <- c(fail, sprintf("%s:%d  $%s expands but is never assigned  |  %s",
                                  basename(f), s + i, v, trimws(substr(body[i], 1, 70))))
      }
    }
  }
}
cat("unquoted-heredoc expansion audit\n")
cat("  scripts: ", length(files), "   unquoted heredocs: ", n_hd, "\n", sep = "")
if (length(fail)) {
  cat("\nFAIL: a $VAR inside an unquoted heredoc is not defined by the script.\n")
  for (v in unique(fail)) cat("  - ", v, "\n", sep = "")
  cat("\n  Escape it as \\$ if it belongs to the REMOTE script or another language\n")
  cat("  (R's list accessors look exactly like shell variables), or define it.\n")
  cat("  bash -n cannot see this: it does not expand heredocs, so the failure\n")
  cat("  only appears at runtime, after an instance has been provisioned.\n")
  quit(status = 1L)
}
cat("  every expanded variable is defined by its script\n")
