#' @title Atomic RDS Write Helpers
#'
#' @description
#' Thin wrappers that provide a consistent `write_rds_atomic()` / `read_rds_verified()`
#' API while delegating the actual tmp+rename atomicity to the canonical
#' `safe_saveRDS()` implementation in `R/utils/safe_save.R`.
#'
#' **Why two files?**  `safe_save.R` holds the PID-scoped tmp+rename implementation
#' and is well-tested.  `write_rds_atomic.R` exposes a more explicit name and adds
#' optional SHA-256 sidecar support (`compute_sidecar=TRUE`) so call-sites that want
#' provenance tracking can opt in without modifying the core helper.
#'
#' Sourcing *either* file is sufficient for atomicity.  `01-setup.R` sources
#' `safe_save.R` so pipeline sub-processes already have `safe_saveRDS()`; scripts
#' that want `write_rds_atomic()` by name can source this file instead (or in
#' addition).
#'
#' **Not package exports.**  R collates only top-level `R/*.R`; files under an
#' `R/` subdirectory are never part of the installed package, so these helpers
#' are `@keywords internal` and reachable by `source()` only.  Promoting them to
#' exports means moving the file to `R/` and dropping the load-time `source()`
#' below.  Enforced by `tools/sync_namespace.R`.
#'
#' @family pipeline-infrastructure
#' @name write_rds_atomic_helpers
NULL

# Ensure the canonical implementation is available.  Guard against double-source.
if (!exists("safe_saveRDS", mode = "function")) {
  source(here::here("R", "utils", "safe_save.R"))
}

#' Atomic saveRDS with optional SHA-256 sidecar
#'
#' Writes `obj` to `path` atomically (PID-scoped `.tmp.<pid>` → `file.rename()`
#' → cross-fs `file.copy()` fallback) and optionally records a SHA-256 digest
#' in a `<path>.sha256` sidecar for downstream verification.
#'
#' @param obj     R object to serialize.
#' @param path    Destination file path (character scalar).
#' @param compute_sidecar Logical (default `TRUE`).  When `TRUE`, compute the
#'   SHA-256 of the written file and write it to `<path>.sha256`.  Sidecar
#'   failures are non-fatal (warning only) so the main write is never rolled back.
#' @param ...     Additional arguments forwarded to `saveRDS()`.
#'
#' @return Invisibly `TRUE` on success.
#'
#' @examples
#' \dontrun{
#' write_rds_atomic(my_df, "artifacts/step_1.rds")
#' write_rds_atomic(my_df, "artifacts/step_1.rds", compute_sidecar = FALSE)
#' }
#'
#' @seealso [safe_saveRDS()] (canonical implementation), [read_rds_verified()]
#' @keywords internal
write_rds_atomic <- function(obj, path, compute_sidecar = TRUE, ...) {
  if (!is.character(path) || length(path) != 1L) {
    stop("write_rds_atomic: 'path' must be a single character string", call. = FALSE)
  }
  # Delegate atomicity to the canonical helper
  safe_saveRDS(obj, path, ...)
  # Optional SHA-256 sidecar.
  # NOTE: Uses hash_file() from R/utils/file_hash.R — always SHA-256, never MD5.
  # Sidecars written by the OLD tools::md5sum() fallback (before 2026-06-23)
  # contain MD5 digests and will NOT match; regenerate those artifacts.
  if (isTRUE(compute_sidecar)) {
    tryCatch({
      digest_val <- digest::digest(path, algo = "sha256", file = TRUE)
      writeLines(digest_val, paste0(path, ".sha256"))
    }, error = function(e) {
      warning(sprintf(
        "write_rds_atomic: sidecar write failed (non-fatal) for %s: %s",
        basename(path), e$message
      ), call. = FALSE)
    })
  }
  invisible(TRUE)
}

#' Read RDS and verify against SHA-256 sidecar
#'
#' Reads an RDS file and, when a `<path>.sha256` sidecar is present, recomputes
#' the digest of the file on disk and compares it to the recorded value.  A
#' mismatch triggers a warning (not a stop) so pipelines can choose whether to
#' treat it as fatal.
#'
#' @param path   Path to the RDS file (character scalar).
#' @param warn_on_mismatch Logical (default `TRUE`).  Emit a `warning()` on
#'   digest mismatch.  Set to `FALSE` to silently ignore sidecar differences.
#'
#' @return The deserialized R object.
#'
#' @examples
#' \dontrun{
#' obj <- read_rds_verified("artifacts/step_1.rds")
#' }
#'
#' @seealso [write_rds_atomic()]
#' @keywords internal
read_rds_verified <- function(path, warn_on_mismatch = TRUE) {
  if (!file.exists(path)) {
    stop(sprintf("read_rds_verified: file not found: %s", path), call. = FALSE)
  }
  sidecar <- paste0(path, ".sha256")
  if (file.exists(sidecar)) {
    recorded <- tryCatch(trimws(readLines(sidecar, n = 1L, warn = FALSE)),
                         error = function(e) NA_character_)
    if (!is.na(recorded) && nzchar(recorded)) {
      # Always use SHA-256 (canonical). tools::md5sum() fallback removed 2026-06-23
      # — sidecars written pre-2026-06-23 via the md5 fallback will trigger a
      # mismatch warning here; regenerate the artifact to refresh the sidecar.
      actual <- tryCatch(
        digest::digest(path, algo = "sha256", file = TRUE),
        error = function(e) NA_character_
      )
      if (!is.na(actual) && !identical(recorded, actual) && isTRUE(warn_on_mismatch)) {
        warning(sprintf(
          "read_rds_verified: digest mismatch for %s\n  recorded: %s\n  actual:   %s",
          basename(path), recorded, actual
        ), call. = FALSE)
      }
    }
  }
  readRDS(path)
}
