#!/usr/bin/env Rscript
# =============================================================================
# Age-matched denominator IDENTITY gate
# =============================================================================
# Independently reconstructs, for every tract x subspecialty x year, the
# denominator that SHOULD enter E2SFCA, and requires EXACT agreement with the
# denominator that actually did.
#
# WHY "eligible share < 1.0" IS NOT ENOUGH. That test only proves the universal
# denominator did not leak wholesale. It passes happily when two subspecialties'
# denominators are swapped, when a band is omitted, when an age boundary is off
# by one, or when a stale ACS vintage is used -- every one of which produces a
# plausible number and a wrong study.
#
# INDEPENDENCE. The check does NOT re-sum the manifest's declared band lists,
# which would only re-run the builder's own logic. It derives the expected bands
# from the DECLARED AGE WINDOW using the ACS table definitions below, then:
#
#   (a) compares the derived band list against the manifest's declared list
#       -- catching a wrong, omitted or off-by-one band in the manifest itself;
#   (b) sums those bands from the RAW cached ACS extract and compares against the
#       denominator actually used -- catching swaps, stale vintages and builder
#       bugs.
#
# Usage: Rscript tools/ci/check_denominator_identity.R
#        E2SFCA_IDENTITY_YEARS=2020 Rscript ...        (subset, for speed)
suppressWarnings(suppressMessages(library(yaml)))
if (!file.exists("DESCRIPTION")) { cat("::error::run from the repository root\n"); quit(status=1L) }
fail <- character(0)
bad  <- function(...) fail <<- c(fail, paste0(...))
note <- function(...) cat("  ", ..., "\n", sep = "")

# ---- ACS table definitions: the independent source of truth -----------------
# B01001 female age bands (variables 027-049) and the race-iteration bands
# (H/C, variables 018-031), as [lo, hi) intervals in years.
TOTAL_BANDS <- list(
  c(0,5), c(5,10), c(10,15), c(15,18), c(18,20), c(20,21), c(21,22), c(22,25),
  c(25,30), c(30,35), c(35,40), c(40,45), c(45,50), c(50,55), c(55,60),
  c(60,62), c(62,65), c(65,67), c(67,70), c(70,75), c(75,80), c(80,85), c(85,Inf))
names(TOTAL_BANDS) <- sprintf("B01001_%03d", 27:49)
RACE_BANDS <- list(
  c(0,5), c(5,10), c(10,15), c(15,18), c(18,20), c(20,25), c(25,30), c(30,35),
  c(35,45), c(45,55), c(55,65), c(65,75), c(75,85), c(85,Inf))

parse_window <- function(w) {
  w <- trimws(tolower(w))
  if (grepl("^under ", w))        return(c(0, as.numeric(sub("^under ", "", w))))
  if (grepl("and over$", w))      return(c(as.numeric(sub(" and over$", "", w)), Inf))
  if (grepl("^[0-9]+ to [0-9]+$", w)) {
    p <- as.numeric(strsplit(w, " to ")[[1]]); return(c(p[1], p[2] + 1))  # inclusive upper
  }
  stop("cannot parse age window: ", w)
}
bands_in <- function(win, bands, prefix, offset) {
  keep <- vapply(bands, function(b) b[1] >= win[1] - 1e-9 && b[2] <= win[2] + 1e-9, logical(1))
  # every band must be wholly inside or wholly outside: a straddling band means
  # the window is not exactly representable and the denominator would be an
  # interpolation, which the manifest forbids.
  strad <- vapply(bands, function(b) (b[1] < win[2] && b[2] > win[1]) &&
                                     !(b[1] >= win[1] - 1e-9 && b[2] <= win[2] + 1e-9), logical(1))
  list(vars = sprintf("%s_%03d", prefix, offset + which(keep) - 1L), straddles = sum(strad))
}

MAN <- "inst/multiverse/age_matched_denominator.yml"
man <- yaml::read_yaml(MAN)
# RELEASE-AUDIT ONLY, DELIBERATELY NOT IN nightly.yml OR pr-scientific-gate.yml.
# This gate needs the 227.7 MB pinned ACS cache, which lives in S3, and no
# workflow in this repository has AWS credentials. Wiring it in would produce a
# job that fails on every run for a reason unrelated to the science -- the exact
# thing that teaches people to ignore a red gate. It runs in
# tools/ci/release_audit.sh, which is executed on a machine that can fetch the
# payload, and a release is not declared without it.
#
# ---- the cache is a PINNED external input, verified before it is read --------
# These 24 files (227.7 MB) are the exact ACS band extracts, tract geometry and
# derived denominators that produced the accepted v0.2.0 analysis. They are too
# large for git, so only the manifest ships and the payload lives in S3.
#
# This gate previously read whatever happened to be at the cache path. A clean
# checkout of v0.2.0 could not run it at all -- every year reported "inputs
# missing" -- and it passed on the author's machine only because the files were
# lying there from the panel build. That is precisely the condition that let the
# WRONG isochrone set be used for four days: a load-bearing input identified by
# local path rather than by hash.
#
# So: resolve the directory, verify every file against the manifest by SHA-256,
# and fail closed. No fallback, no "use what is there", no size-only check --
# this environment silently truncates large S3 transfers, so a file of the right
# length proves nothing.
CACHE <- Sys.getenv("E2SFCA_DENOM_CACHE", "artifacts/2sfca/sensitivity/cache")
MANIFEST <- "inst/multiverse/acs_denominator_cache.json"

.sha256 <- function(path) {
  # digest is pinned in renv.lock (0.6.39). No shelling out to shasum/sha256sum,
  # which differ across the three CI platforms.
  as.character(digest::digest(file = path, algo = "sha256"))
}

.verify_cache <- function(cache, manifest) {
  if (!file.exists(manifest))
    stop("the denominator-cache manifest is missing: ", manifest, call. = FALSE)
  for (pkg in c("jsonlite", "digest"))
    if (!requireNamespace(pkg, quietly = TRUE))
      stop(pkg, " is required to verify the denominator cache", call. = FALSE)

  m <- jsonlite::fromJSON(manifest, simplifyDataFrame = FALSE)
  absent <- character(0); wrong <- character(0)
  for (f in m$files) {
    p <- file.path(cache, f$name)
    if (!file.exists(p)) { absent <- c(absent, f$name); next }
    got <- .sha256(p)
    if (!identical(got, f$sha256))
      wrong <- c(wrong, sprintf("%s\n      want %s\n      got  %s", f$name, f$sha256, got))
  }

  if (length(absent) || length(wrong)) {
    msg <- c("the pinned ACS denominator cache is not present and correct at: ", cache)
    if (length(absent))
      msg <- c(msg, sprintf("\n\n  MISSING (%d of %d):\n    - %s", length(absent),
                            length(m$files), paste(absent, collapse = "\n    - ")))
    if (length(wrong))
      msg <- c(msg, sprintf("\n\n  WRONG CONTENT (%d):\n    - %s", length(wrong),
                            paste(wrong, collapse = "\n    - ")))
    msg <- c(msg, "\n\n  Fetch the pinned set:\n    ", m$fetch,
             "\n\n  These are HISTORICAL FROZEN INPUTS supporting ", m$supports_release,
             ". Do not regenerate them\n  to make this pass -- a later ACS vintage extends observation time rather\n",
             "  than correcting these study-era estimates, so regenerating would change\n",
             "  the analysis rather than verify it.")
    stop(paste0(msg, collapse = ""), call. = FALSE)
  }
  cat("  pinned cache verified: ", length(m$files), " files, sha256 exact\n", sep = "")
  invisible(m)
}

.verify_cache(CACHE, MANIFEST)
yrs <- Sys.getenv("E2SFCA_IDENTITY_YEARS", "")
YEARS <- if (nzchar(yrs)) as.integer(strsplit(yrs, ",")[[1]]) else 2013:2023

cat("age-matched denominator identity gate\n")
note("manifest: ", MAN, " (v", man$manifest_version, ")")
checked <- 0L
for (y in YEARS) {
  raw_p <- file.path(CACHE, sprintf("acs%d_age_bands.rds", y))
  den_p <- if (y == 2020L) file.path(CACHE, "age_matched_denominators.rds") else
           file.path(CACHE, sprintf("age_matched_denominators_%d.rds", y))
  if (!file.exists(raw_p) || !file.exists(den_p)) {
    bad("year ", y, ": inputs missing (", basename(raw_p), " / ", basename(den_p), ")"); next
  }
  raw <- readRDS(raw_p); den <- readRDS(den_p)$denominators
  for (s in man$subspecialties) {
    code <- s$code
    win  <- parse_window(s$age_range)
    exp_t <- bands_in(win, TOTAL_BANDS, "B01001",  27L)
    exp_w <- bands_in(win, RACE_BANDS,  "B01001H", 18L)
    exp_a <- bands_in(win, RACE_BANDS,  "B01001C", 18L)
    if (exp_t$straddles || exp_w$straddles || exp_a$straddles)
      bad(y, " ", code, ": window '", s$age_range, "' straddles an ACS band; ",
          "the denominator would be an interpolation")

    # (a) derived bands must equal the manifest's declared bands
    for (p in list(list("total", exp_t$vars, s$acs_bands_total),
                   list("white", exp_w$vars, s$acs_bands_white),
                   list("aian",  exp_a$vars, s$acs_bands_aian))) {
      if (!setequal(p[[2]], unlist(p[[3]])))
        bad(y, " ", code, " ", p[[1]], ": manifest bands disagree with the bands implied by '",
            s$age_range, "'. derived=", paste(sort(p[[2]]), collapse=","),
            " manifest=", paste(sort(unlist(p[[3]])), collapse=","))
    }

    # (b) independently summed raw ACS must EXACTLY equal the denominator used
    d <- den[[code]]
    if (is.null(d)) { bad(y, " ", code, ": no denominator present"); next }
    rec <- function(vars) {
      v <- intersect(vars, names(raw)); if (!length(v)) return(NULL)
      stats::setNames(rowSums(raw[, v, drop = FALSE], na.rm = TRUE), raw$GEOID)
    }
    for (p in list(list("total_f", exp_t$vars), list("white_f", exp_w$vars),
                   list("aian_f",  exp_a$vars))) {
      r <- rec(p[[2]])
      if (is.null(r)) { bad(y, " ", code, " ", p[[1]], ": bands absent from the ACS extract"); next }
      got <- stats::setNames(d[[p[[1]]]], d$GEOID)
      common <- intersect(names(r), names(got))
      if (!length(common)) { bad(y, " ", code, " ", p[[1]], ": no GEOIDs in common"); next }
      diff <- abs(r[common] - got[common])
      nbad <- sum(diff > 1e-9, na.rm = TRUE)
      if (nbad > 0)
        bad(y, " ", code, " ", p[[1]], ": ", nbad, " tract(s) disagree with the ",
            "independently reconstructed denominator (worst ", signif(max(diff, na.rm=TRUE), 4), ")")
      checked <- checked + 1L
    }
  }
  note("year ", y, " checked")
}
cat("\n")
note(checked, " tract-vector identities verified")
if (length(fail)) {
  message("FAIL: the denominators entering E2SFCA are not what the manifest declares:")
  for (f in unique(fail)) message("  - ", f)
  message("\n  This gate reconstructs the expected denominator from the ACS table",
          "\n  definitions and the declared age window, independently of the builder.")
  quit(status = 1L, save = "no")
}
cat("every denominator matches its independent reconstruction exactly\n")
