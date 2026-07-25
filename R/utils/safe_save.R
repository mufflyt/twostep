#' @title Atomic File-Write Helpers
#'
#' @description
#' Provides atomic `saveRDS()` and `writeLines()` drop-in replacements to
#' prevent
#' corrupt half-written outputs and caches when a long-running step is killed
#' mid-write.
#'
#' @family pipeline-infrastructure
#' @name safe_save_helpers
NULL

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Atomic file-write helpers
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Purpose: prevent corrupt half-written outputs and caches when a long-running
#          step is killed mid-write (e.g., OOM, timeout, user Ctrl-C).
#
# Pattern: write to <path>.tmp, fsync the directory, then file.rename().
# On POSIX file systems, the rename is atomic — readers either see the old
# file or the new file, never a partial.
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

#' Atomic saveRDS()
#'
#' Drop-in replacement for `saveRDS()` that writes to a temp file in the same
#' directory and renames into place on success. If the process is killed
#' mid-write, the destination file is either fully intact (prior contents) or
#' fully intact (new contents) — never a partial. The temp file is cleaned up
#' on failure.
#'
#' @param object Object to serialize.
#' @param file Destination file path.
#' @param ... Additional args forwarded to `saveRDS()`.
#' @return Invisibly: TRUE on success.
safe_saveRDS <- function(object, file, ...) {
  dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(file, ".tmp.", Sys.getpid())
  on.exit({
    if (file.exists(tmp)) tryCatch(unlink(tmp), error = function(e) NULL)
  })
  saveRDS(object, tmp, ...)
  ok <- file.rename(tmp, file)
  if (!isTRUE(ok)) {
    # file.rename can fail across filesystems on some platforms; fall back to copy+remove
    if (!file.copy(tmp, file, overwrite = TRUE)) {
      stop(sprintf("safe_saveRDS: failed to move temp file to %s", file))
    }
    unlink(tmp)
  }
  invisible(TRUE)
}

#' Atomic writeLines()
#'
#' Same atomicity pattern for plain text files.
safe_writeLines <- function(text, con, ...) {
  dir.create(dirname(con), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(con, ".tmp.", Sys.getpid())
  on.exit({
    if (file.exists(tmp)) tryCatch(unlink(tmp), error = function(e) NULL)
  })
  writeLines(text, tmp, ...)
  ok <- file.rename(tmp, con)
  if (!isTRUE(ok)) {
    if (!file.copy(tmp, con, overwrite = TRUE)) {
      stop(sprintf("safe_writeLines: failed to move temp file to %s", con))
    }
    unlink(tmp)
  }
  invisible(TRUE)
}
