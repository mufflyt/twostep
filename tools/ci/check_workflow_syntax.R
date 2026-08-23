#!/usr/bin/env Rscript
# =============================================================================
# Every bash `run:` block in every workflow must actually parse.
# =============================================================================
# A malformed shell step is not caught by YAML validation -- the YAML is fine,
# the STRING inside it is broken -- so it ships, and the job dies with a bare
# "exit code 2" only once CI runs. That just happened: a stray quote left
#
#     echo "frozen artifacts unmodified
#
# unterminated, which failed the job AFTER the work it was verifying had already
# succeeded. Cheap to check here, expensive to discover on a runner.
#
# Only bash/sh steps are parsed. Steps declaring `shell: Rscript {0}` (or
# python, or anything else) contain code in that language and would produce
# nine false positives if handed to bash -- and a check that cries wolf is one
# people learn to ignore.
#
# Usage: Rscript tools/ci/check_workflow_syntax.R
suppressWarnings(suppressMessages(library(yaml)))
if (!file.exists("DESCRIPTION")) {
  cat("::error::run from the repository root\n"); quit(status = 1L)
}
if (nchar(Sys.which("bash")) == 0L) {
  cat("::error::bash not found; cannot syntax-check workflow steps\n")
  quit(status = 1L)
}

wfs <- list.files(".github/workflows", pattern = "[.]ya?ml$", full.names = TRUE)
if (!length(wfs)) { cat("no workflows found\n"); quit(status = 0L) }

`%||%` <- function(a, b) if (is.null(a)) b else a
shell_of <- function(step, jdef, wdef) step[["shell"]] %||% jdef %||% wdef %||% "bash"

fails <- character(0); n <- 0L
for (wf in wfs) {
  d <- tryCatch(yaml::read_yaml(wf), error = function(e) {
    fails <<- c(fails, sprintf("%s: YAML does not parse: %s", wf, conditionMessage(e)))
    NULL
  })
  if (is.null(d) || is.null(d$jobs)) next
  wdef <- d$defaults$run$shell
  for (jn in names(d$jobs)) {
    job  <- d$jobs[[jn]]
    jdef <- job$defaults$run$shell %||% wdef
    for (st in job$steps %||% list()) {
      r <- st[["run"]]
      if (is.null(r) || !nzchar(r)) next
      sh <- shell_of(st, jdef, wdef)
      if (!sh %in% c("bash", "sh")) next
      n <- n + 1L
      tf <- tempfile(fileext = ".sh")
      writeLines(r, tf)
      out <- suppressWarnings(system2("bash", c("-n", shQuote(tf)),
                                      stdout = TRUE, stderr = TRUE))
      st_code <- attr(out, "status")
      unlink(tf)
      if (!is.null(st_code) && st_code != 0L) {
        msg <- if (length(out)) sub(paste0("^", tf, ": *"), "", out[1]) else "syntax error"
        fails <- c(fails, sprintf("%s :: job '%s' :: step '%s'\n      %s",
                                  basename(wf), jn,
                                  st[["name"]] %||% "(unnamed)", msg))
      }
    }
  }
}

cat("workflow shell syntax\n")
cat("  bash run: blocks parsed: ", n, "\n", sep = "")
if (length(fails)) {
  cat("\nFAIL: a workflow step does not parse as shell:\n")
  for (f in fails) cat("  - ", f, "\n", sep = "")
  cat("\n  YAML validity does not imply the shell inside it is valid. A broken\n")
  cat("  step fails on the runner with a bare exit code and no explanation.\n")
  quit(status = 1L)
}
cat("  every bash step parses\n")
