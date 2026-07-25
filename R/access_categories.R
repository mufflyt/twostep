# ==============================================================================
# access_categories.R -- SSOT SHIM. Value now lives ONCE in the shared mufflyaccess package
# (single source of truth across isochrones / twostep / cliff). This file loads
# the package so consumers that source() it keep working; no local definition
# remains, so cross-repo drift is impossible.
#   install: renv::install("mufflyt/mufflyaccess@v0.1.2")
# ==============================================================================
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("Package 'mufflyaccess' is required. Install: renv::install(\"mufflyt/mufflyaccess@v0.1.2\").",
       call. = FALSE)
suppressPackageStartupMessages(library(mufflyaccess))
