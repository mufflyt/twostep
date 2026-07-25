#!/usr/bin/env Rscript
# Install missing R packages on EC2 as BINARIES via Posit Public Package Manager
# (no compilation — avoids missing system libs like libuv-devel for fs/testthat).
# Detects the distro from /etc/os-release and sets the PPM binary repo + the
# HTTPUserAgent that triggers binary delivery. Falls back to CRAN source.
# Usage: sudo Rscript scripts/ec2_install_pkgs.R <pkg1> <pkg2> ...
pkgs <- commandArgs(trailingOnly = TRUE)
if (!length(pkgs)) { cat("[install] nothing to install\n"); quit(status = 0) }

# `fs` (a testthat dependency) needs libuv; the AMI lacks libuv-devel. Build fs's
# OWN bundled static libuv instead of requiring the system header — deterministic,
# no dnf/EPEL, works for both binary-miss and source builds.
Sys.setenv(USE_BUNDLED_LIBUV = "1")

osr  <- tryCatch(readLines("/etc/os-release"), error = function(e) character())
getf <- function(k) { m <- grep(paste0("^", k, "="), osr, value = TRUE)
  if (length(m)) gsub('"', '', sub(paste0("^", k, "="), "", m[1])) else "" }
id <- tolower(getf("ID")); vid <- getf("VERSION_ID")
distro <-
  if (grepl("amzn", id) && grepl("^2023", vid)) "amzn2023" else
  if (grepl("amzn", id))                         "centos7"  else
  if (grepl("rhel|rocky|alma|centos", id) && grepl("^9", vid)) "rhel9" else
  if (grepl("rhel|rocky|alma|centos", id) && grepl("^8", vid)) "rhel8" else
  if (grepl("ubuntu", id) && grepl("^22", vid)) "jammy" else
  if (grepl("ubuntu", id) && grepl("^20", vid)) "focal" else ""
repo <- if (nzchar(distro))
  sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", distro) else
  "https://packagemanager.posit.co/cran/latest"
ver  <- as.character(getRversion())
ua   <- sprintf("R/%s R (%s %s %s %s)", ver, ver, R.version[["platform"]],
                R.version[["arch"]], R.version[["os"]])
options(HTTPUserAgent = ua, repos = c(CRAN = repo), Ncpus = max(1L, parallel::detectCores()))
cat(sprintf("[install] distro=%s repo=%s pkgs=%s\n", distro, repo, paste(pkgs, collapse = ",")))
install.packages(pkgs)

still <- Filter(function(p) !requireNamespace(p, quietly = TRUE), pkgs)
if (length(still)) {
  cat(sprintf("[install] PPM left missing: %s — retrying from CRAN source\n",
              paste(still, collapse = ",")))
  install.packages(still, repos = "https://cloud.r-project.org")
  still <- Filter(function(p) !requireNamespace(p, quietly = TRUE), still)
}
if (length(still)) {
  cat(sprintf("[install] STILL MISSING: %s\n", paste(still, collapse = ",")))
  quit(status = 1)
}
cat("[install] all requested packages present\n")
