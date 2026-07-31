#!/usr/bin/env Rscript
# ==============================================================================
# generate_provenance.R -- regenerate verifiable provenance for the twostep
# Access Explorer inputs. Writes, next to this script:
#   PROVENANCE.md     (human-readable, with sha256 / bytes / rows / cols)
#   provenance.json   (machine-readable)
#
# Run:  Rscript inst/shiny/access_explorer/generate_provenance.R
#
# Provenance is COMPUTED from the live artifacts (never hand-authored) so it
# cannot drift. Absent artifacts (the staged tract layer) are recorded as such.
# ==============================================================================
suppressWarnings(suppressMessages({ library(jsonlite) }))

root    <- rprojroot::find_root(rprojroot::has_file("DESCRIPTION"))
app_dir <- file.path(root, "inst", "shiny", "access_explorer")

sha256 <- function(f) {
  if (requireNamespace("digest", quietly = TRUE))
    return(digest::digest(file = f, algo = "sha256"))
  out <- tryCatch(system2("shasum", c("-a", "256", shQuote(f)), stdout = TRUE),
                  error = function(e) character(0))
  if (length(out)) sub("\\s.*$", "", out[1]) else NA_character_
}
csv_dims <- function(f) {
  con <- file(f, "r"); on.exit(close(con))
  hdr <- readLines(con, n = 1)
  n <- 0L; while (length(readLines(con, n = 1))) n <- n + 1L
  list(rows = n, cols = length(strsplit(hdr, ",")[[1]]),
       fields = trimws(strsplit(hdr, ",")[[1]]))
}
newest <- function(dir, pat) {
  d <- file.path(root, dir)
  if (!dir.exists(d)) return(NA_character_)
  fs <- list.files(d, pat, full.names = TRUE)
  if (!length(fs)) return(NA_character_)
  fs[order(file.info(fs)$mtime, decreasing = TRUE)][1]
}

# ---- the inputs each tab reads ----------------------------------------------
spec <- list(
  list(tab = "Disparities + Sensitivity", source = "data/step_4_access_by_group.csv",
       path = file.path(root, "data/step_4_access_by_group.csv"),
       grain = "2023 cross-section; subspecialty x band x race-category",
       producer = "vendored Step-4 access extract (data/PROVENANCE_vendored_inputs.md)"),
  list(tab = "Temporal (2013-2023)",
       source = "artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv",
       path = file.path(root, "artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv"),
       grain = "subspecialty x year (2013-2023) x stratum (race/rurality)",
       producer = "scripts/stratify_allyears_access.R over the frozen E2SFCA run"),
  list(tab = "Access map (tract geometry)", source = "data/cache/tract_boundaries/*.rds",
       path = newest("data/cache/tract_boundaries", "\\.rds$"),
       grain = "census tract polygons (CONUS)",
       producer = "isochrones tract-boundary cache (staged)"),
  list(tab = "Access map (access-by-tract)", source = "scratchpad/seam_tracts/*.parquet",
       path = newest("scratchpad/seam_tracts", "\\.parquet$"),
       grain = "tract x subspecialty x band access + race totals",
       producer = "staged comparator parquet (_staging_guard.R)")
)

records <- lapply(spec, function(s) {
  path <- s$path
  present <- !is.null(path) && !is.na(path) && file.exists(path)
  rec <- list(tab = s$tab, source = s$source, grain = s$grain, producer = s$producer,
              present = present)
  if (present) {
    rec$bytes  <- as.numeric(file.info(path)$size)
    rec$sha256 <- sha256(path)
    if (grepl("\\.csv$", path)) {
      d <- csv_dims(path); rec$rows <- d$rows; rec$cols <- d$cols; rec$fields <- d$fields
    }
  }
  rec
})

# ---- environment / lineage ---------------------------------------------------
lock <- tryCatch(jsonlite::read_json(file.path(root, "renv.lock")), error = function(e) NULL)
pkgver <- function(p) { v <- lock$Packages[[p]]$Version; if (is.null(v)) "(not in renv.lock -- install manually)" else v }
run_line <- grep("E2SFCA_FROZEN_RUN_ID", readLines(file.path(root, "scripts/manuscript_e2sfca_values.R")),
                 value = TRUE)[1]
run_id <- sub('.*"(e2sfca_[0-9a-z_]+)".*', "\\1", run_line)

env <- list(
  r_version = as.character(getRversion()),
  packages = list(sf = pkgver("sf"), arrow = pkgver("arrow"), leaflet = pkgver("leaflet"),
                  ggplot2 = pkgver("ggplot2"), dplyr = pkgver("dplyr"), shiny = pkgver("shiny")),
  e2sfca_frozen_run_id = run_id,
  crs = "EPSG:5070", grid_m = 500,
  engine = "R/two_step_floating_catchment.R (SHA-gated); base decay = E2SFCA_DEFAULT_WEIGHTS",
  ssot_constants = c("R/contour_bands.R", "R/access_categories.R"),
  contract = list(
    supply = "mufflyaccess::urps_count() (artifact contract 3.0.0); never re-derived/hardcoded",
    demand = "twostep ACS population denominators",
    reachability = "isochrones release artifacts",
    geography_rule = "assert_matching_geography(numerator, denominator)"),
  note = "Provenance is computed from live artifacts by generate_provenance.R; do not hand-edit."
)

jsonlite::write_json(list(records = records, environment = env),
                     file.path(app_dir, "provenance.json"), auto_unbox = TRUE, pretty = TRUE)

# ---- markdown ----------------------------------------------------------------
md <- c(
  "# Access Explorer -- Verifiable Provenance",
  "",
  "Computed from the live artifacts by `generate_provenance.R` (do not hand-edit;",
  "rerun the script to refresh). Absent artifacts are recorded as not staged.",
  "",
  "## Inputs", "",
  "| Tab | Source | Present | sha256 | bytes | rows x cols | grain / producer |",
  "|---|---|---|---|---|---|---|")
for (r in records) {
  md <- c(md, sprintf("| %s | `%s` | %s | %s | %s | %s | %s |",
    r$tab, r$source,
    if (isTRUE(r$present)) "yes" else "**not staged**",
    if (isTRUE(r$present)) paste0("`", substr(r$sha256, 1, 16), "...`") else "-",
    if (isTRUE(r$present)) format(r$bytes, big.mark = ",") else "-",
    if (!is.null(r$rows)) paste0(r$rows, " x ", r$cols) else "-",
    paste0(r$grain, "; ", r$producer)))
}
md <- c(md, "",
  "## Environment", "",
  sprintf("- R: %s", env$r_version),
  sprintf("- packages: sf %s, arrow %s, leaflet %s, ggplot2 %s, dplyr %s, shiny %s",
          env$packages$sf, env$packages$arrow, env$packages$leaflet,
          env$packages$ggplot2, env$packages$dplyr, env$packages$shiny),
  sprintf("- frozen run id: `%s`", env$e2sfca_frozen_run_id),
  sprintf("- engine: %s", env$engine),
  sprintf("- CRS / grid: %s, %d m", env$crs, env$grid_m),
  sprintf("- SSOT constants: %s", paste(env$ssot_constants, collapse = ", ")),
  "",
  "## One-direction contract", "",
  sprintf("- **Supply** (numerator): %s", env$contract$supply),
  sprintf("- **Demand** (denominators): %s", env$contract$demand),
  sprintf("- **Reachability** (geometry): %s", env$contract$reachability),
  sprintf("- **Geography rule**: %s", env$contract$geography_rule),
  "",
  "Full frozen-run lineage + checksums: `docs/DATA_PROVENANCE.md`, `SHA256SUMS.txt`.",
  "This app measures access only; workforce projection is cliff's",
  "(`cliff/docs/urps-workforce-projection-spec.md`).", "")
writeLines(md, file.path(app_dir, "PROVENANCE.md"))

# ---- checksums (.txt, SHA256SUMS format) -------------------------------------
# Pure "<sha256>  <repo-relative-path>" lines (present inputs only), so pipelines
# can verify inputs from the repo root with:  shasum -a 256 -c provenance.txt
sums <- vapply(records, function(r)
  if (isTRUE(r$present)) sprintf("%s  %s", r$sha256, r$source) else NA_character_,
  character(1))
writeLines(sums[!is.na(sums)], file.path(app_dir, "provenance.txt"))

message("wrote ", file.path(app_dir, "PROVENANCE.md"))
message("wrote ", file.path(app_dir, "provenance.json"))
message("wrote ", file.path(app_dir, "provenance.txt"))
