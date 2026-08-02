#!/usr/bin/env Rscript
# ==============================================================================
# manuscript_e2sfca_values.R
# ------------------------------------------------------------------------------
# Single source of truth for the E2SFCA national-series values used in the
# accessibility manuscript Abstract and Results. Reads ONLY the canonical
# cell-level, population-weighted national summary from the validated production
# run and emits validated, formatted values. No value is copied from prose,
# console output, or figure labels.
#
# Canonical source (headline_source in the run manifest):
#   artifacts/2sfca/ec2/<RUN>/e2sfca_national_summary.csv
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr) }))

# ---- canonical frozen-run pointer (SSOT) -------------------------------------

#' Canonical frozen production run backing the manuscript.
#'
#' Every manuscript Abstract/Results number derives from this run; each artifact
#' path is built from it, and the run manifest's self-declared `run_id` must match
#' (see [e2sfca_run_dir]). This is the single source of truth for "which run" —
#' do not paste the literal id into scripts, docs, or the Rmd; reference this
#' constant (or [e2sfca_run_dir]) instead. Override for a re-run with env
#' `E2SFCA_RUN_ID`.
#'
#' @format Character scalar; the frozen run directory name under
#'   `artifacts/2sfca/ec2/`.
#' @export
E2SFCA_FROZEN_RUN_ID <- Sys.getenv("E2SFCA_RUN_ID", "e2sfca_20260712_190734")

#' Resolve and validate the frozen-run artifact directory.
#'
#' Fails loudly (never silently falls back) if the directory or its manifest is
#' missing, or if the manifest's self-declared `run_id` disagrees with
#' [E2SFCA_FROZEN_RUN_ID] — the stale-pointer guard that keeps a moved/renamed run
#' from silently feeding wrong numbers into the manuscript.
#'
#' @param run_id Frozen run id; defaults to [E2SFCA_FROZEN_RUN_ID].
#' @param root Repository root; defaults to `here::here()` when available.
#' @return Absolute path to the validated run directory.
#' @export
e2sfca_run_dir <- function(run_id = E2SFCA_FROZEN_RUN_ID,
                           root = if (requireNamespace("here", quietly = TRUE))
                             here::here() else ".") {
  dir <- file.path(root, "artifacts", "2sfca", "ec2", run_id)
  manifest <- file.path(dir, "e2sfca_run_manifest.json")
  if (!dir.exists(dir))
    stop("[e2sfca] frozen run directory missing: ", dir, call. = FALSE)
  if (!file.exists(manifest))
    stop("[e2sfca] run manifest missing: ", manifest, call. = FALSE)
  declared <- jsonlite::read_json(manifest)$run_id
  if (!identical(declared, run_id))
    stop(sprintf("[e2sfca] run_id mismatch: constant='%s' manifest='%s'",
                 run_id, declared), call. = FALSE)
  dir
}

# ---- canonical allocator identity (SSOT) -------------------------------------

#' Population allocator the manuscript run was validated against.
#'
#' The production allocator is the mass-conserving area-overlap scheme
#' (`allocate_pop_areaweighted`): it conserves every source tract's population with
#' native annual totals. Authority = the frozen manifest `allocator$method_id`
#' (written by the producer, scripts/run_2sfca.R). The seam test
#' (scripts/seam_test_2sfca.R) reports this method against alternatives
#' (`raw`, `equal_total`, `mass_conserving_eqtot`); those are a deliberate method
#' vocabulary and are NOT collapsed into this constant.
#'
#' @format Character scalar; the manifest allocator `method_id`.
#' @export
E2SFCA_ALLOCATOR_METHOD_ID <- "mass_conserving"

# ---- canonical subspecialty set (SSOT) ---------------------------------------

#' The seven OB/GYN subspecialty analysis codes, in manuscript display order.
#'
#' Study set: MFM (Maternal-Fetal Medicine), GO (Gynecologic Oncology), REI
#' (Reproductive Endocrinology & Infertility), FPMRS (Female Pelvic Medicine &
#' Reconstructive Surgery), MIGS (Minimally Invasive Gynecologic Surgery), PAG
#' (Pediatric & Adolescent Gynecology), CFP (Complex Family Planning). This ORDER is
#' the manuscript Table/figure display order; consumers that use it as factor levels
#' rely on it, while set/iteration consumers may sort it.
#'
#' NOTE (deliberate variants, NOT unified here): the seam test and some scripts hold
#' the same set in ALPHABETICAL order (an order-agnostic membership list); the
#' `scripts/manuscript_catalog/` subsystem labels FPMRS as the synonym "URPS" and
#' uses a different tail order. The repo guard checks set membership (mapping
#' URPS->FPMRS), not order, so those intentional differences survive.
#'
#' @format Character vector, length 7, unique codes.
#' @export
E2SFCA_SUBSPECIALTIES <- c("MFM", "GO", "REI", "FPMRS", "MIGS", "PAG", "CFP")

#' Subspecialty display labels for figures and maps (Title Case, abbreviated).
#'
#' Code -> figure/map label, keyed by [E2SFCA_SUBSPECIALTIES] code. This is the
#' abbreviated Title-Case style used in map/figure titles and legends; three map
#' scripts previously held byte-identical copies of it. FPMRS is labelled
#' "Urogynecology (FPMRS)".
#'
#' Deliberate style variants that are NOT this map (do not unify): the equity
#' heatmap uses a SENTENCE-case rendering of these abbreviated names; the manuscript
#' Rmd uses FULL, lowercase formal names for inline prose. Those are separate,
#' context-specific label styles.
#'
#' @format Named character vector, length 7, keyed by subspecialty code.
#' @export
E2SFCA_SUBSPECIALTY_LABELS <- c(
  MFM   = "Maternal-Fetal Medicine",
  GO    = "Gynecologic Oncology",
  REI   = "Reproductive Endocrinology",
  FPMRS = "Urogynecology (FPMRS)",
  MIGS  = "Minimally Invasive Gyn Surgery",
  PAG   = "Pediatric & Adolescent Gyn",
  CFP   = "Complex Family Planning")

# ---- canonical production raster resolution (SSOT) ---------------------------

#' Production E2SFCA grid resolution, in metres.
#'
#' The frozen run allocated demand onto a 500 m equal-area grid; authority = the run
#' manifest `resolution_m`, pinned to this constant in [load_e2sfca_national_summary].
#'
#' NOTE (deliberate variants, NOT this value): the engine functions default to 250 m
#' (a fallback that production always overrides); the all-subspecialty DISPLAY
#' small-multiples use 1000 m on purpose ("500 m is wasted compute" — the figure is
#' coarsened to ~4 km); the sensitivity sweep labels a `res500`/1000 m pair. Those are
#' separate, labelled resolutions and are not unified here.
#'
#' @format Integer scalar; grid cell size in metres.
#' @export
E2SFCA_PRODUCTION_RESOLUTION_M <- 500L

# ---- canonical geographic scope (LIVE from mufflyaccess SSOT) ----------------
# The geography SSOTs are sourced live from the shared mufflyaccess package (now
# public + pinned in renv.lock), the single source of truth across isochrones /
# twostep / cliff. NON_CONUS_FIPS is re-exported under the local consumer name;
# US_STATE_TERRITORY_FIPS is DERIVED so the CONUS/non-CONUS partition cannot drift.
# Guarded by tests/testthat/test-ssot-{conus,nonconus}-fips.R.
if (!requireNamespace("mufflyaccess", quietly = TRUE))
  stop("mufflyaccess (>= 0.10.0) is required: it is the SSOT for the shared ",
       "constants (ACS denominator, CONUS FIPS, bands, categories). ",
       "renv::restore() or remotes::install_github('mufflyt/mufflyaccess').",
       call. = FALSE)

#' CONUS state/DC FIPS (48 contiguous states + DC = 49 codes). Excludes AK(02),
#' HI(15), and the five territories. Live from `mufflyaccess::CONUS_STATE_FIPS`.
#' @export
CONUS_STATE_FIPS <- mufflyaccess::CONUS_STATE_FIPS

#' Non-contiguous FIPS excluded from the study (AK, HI, + 5 territories), under
#' the local consumer name NON_CONUS_FIPS. Live from
#' `mufflyaccess::NON_CONTIGUOUS_FIPS`.
#' @export
NON_CONUS_FIPS <- mufflyaccess::NON_CONTIGUOUS_FIPS

#' All US state + territory FIPS (56): the CONUS/non-CONUS union. DERIVED from the
#' two sets so the partition is exact and cannot drift.
#' @export
US_STATE_TERRITORY_FIPS <- sort(union(CONUS_STATE_FIPS, NON_CONUS_FIPS))

stopifnot(
  "CONUS_STATE_FIPS must be 49 unique 2-char codes" =
    length(CONUS_STATE_FIPS) == 49L && !anyDuplicated(CONUS_STATE_FIPS) &&
    all(nchar(CONUS_STATE_FIPS) == 2L),
  "NON_CONUS_FIPS must be 7 codes disjoint from CONUS" =
    length(NON_CONUS_FIPS) == 7L && !any(NON_CONUS_FIPS %in% CONUS_STATE_FIPS)
)

# ---- canonical national denominator (SSOT) -----------------------------------

#' National ACS female population, 2020 (the national coverage denominator).
#'
#' Sourced LIVE from the shared package (`mufflyaccess::ACS2020_CONUS_FEMALE_POP`)
#' as the single source of truth; `as.integer()` strips provenance attributes to
#' the plain-integer form figures and the guard expect. Authority is cross-checked
#' against the frozen run's national summary (`acs_pop_source`, year 2020), which
#' [e2sfca_acs_female_pop] re-derives live and the test suite pins to this value.
#'
#' @format Integer scalar; count of women (all ages) in the 2020 ACS, CONUS grid.
#' @export
E2SFCA_ACS_FEMALE_POP_2020 <- as.integer(mufflyaccess::ACS2020_CONUS_FEMALE_POP)

#' Derive the national ACS female-population denominator for a year.
#'
#' Reads the frozen national summary and returns the (subspecialty-invariant)
#' `acs_pop_source` for `year`. Fails loudly if the year is absent or the value is
#' not unique — never silently averages or picks one.
#'
#' @param year Study year (default 2020).
#' @param run_dir Frozen run directory (default [e2sfca_run_dir]).
#' @return Integer national ACS female population for that year.
#' @export
e2sfca_acs_female_pop <- function(year = 2020L, run_dir = e2sfca_run_dir()) {
  summary_path <- file.path(run_dir, "e2sfca_national_summary.csv")
  stopifnot(file.exists(summary_path))
  nat <- readr::read_csv(summary_path, show_col_types = FALSE)
  vals <- unique(nat$acs_pop_source[nat$year == year])
  if (length(vals) != 1L)
    stop(sprintf("[e2sfca] ACS female pop for %d is not a single value: %s",
                 year, paste(vals, collapse = ", ")), call. = FALSE)
  as.integer(vals)
}

#' Load and validate the canonical E2SFCA national summary.
#'
#' @param run_dir Path to the validated production run directory.
#' @return A tibble of the 77 specialty-year national rows.
#' @export
load_e2sfca_national_summary <- function(run_dir) {
  summary_path <- file.path(run_dir, "e2sfca_national_summary.csv")
  manifest_path <- file.path(run_dir, "e2sfca_run_manifest.json")
  stopifnot(file.exists(summary_path), file.exists(manifest_path))
  manifest_json <- jsonlite::read_json(manifest_path)
  national_tbl <- readr::read_csv(summary_path, show_col_types = FALSE)

  base::message("[e2sfca] run_id = ", manifest_json$run_id)
  base::message("[e2sfca] allocator = ", manifest_json$allocator$method_id,
                " / ", manifest_json$allocator$population_allocator)
  base::message("[e2sfca] module_sha256 = ",
                substr(manifest_json$allocator$module_sha256, 1, 16))
  base::message("[e2sfca] headline_source = ", manifest_json$headline_source)

  n_spec <- dplyr::n_distinct(national_tbl$subspecialty)
  n_year <- dplyr::n_distinct(national_tbl$year)
  n_cell <- nrow(dplyr::distinct(national_tbl, subspecialty, year))
  stopifnot(
    identical(manifest_json$run_id, E2SFCA_FROZEN_RUN_ID),
    identical(manifest_json$allocator$method_id, E2SFCA_ALLOCATOR_METHOD_ID),
    as.integer(manifest_json$resolution_m) == E2SFCA_PRODUCTION_RESOLUTION_M,
    nrow(national_tbl) == 77L, n_spec == 7L, n_year == 11L, n_cell == 77L,
    min(national_tbl$year) == 2013L, max(national_tbl$year) == 2023L,
    all(!is.na(national_tbl$mean_pop_weighted_per100k))
  )
  base::message("[e2sfca] validated: 77 rows, 7 specialties, 11 years, ",
                "unique (spec,year), no missing access")
  national_tbl
}

#' Per-specialty first/last-year access, absolute and relative change.
#' @export
e2sfca_specialty_change <- function(national_tbl, first_year = 2013L,
                                    last_year = 2023L) {
  endpoints_tbl <- national_tbl |>
    dplyr::filter(year %in% c(first_year, last_year)) |>
    dplyr::select(subspecialty, year, access = mean_pop_weighted_per100k) |>
    tidyr::pivot_wider(names_from = year, values_from = access,
                       names_prefix = "y")
  change_tbl <- national_tbl |>
    dplyr::group_by(subspecialty) |>
    dplyr::summarise(
      series_min = min(mean_pop_weighted_per100k),
      series_min_year = year[which.min(mean_pop_weighted_per100k)],
      series_max = max(mean_pop_weighted_per100k),
      .groups = "drop")
  endpoints_tbl |>
    dplyr::left_join(change_tbl, by = "subspecialty") |>
    dplyr::mutate(
      abs_change = .data[[paste0("y", last_year)]] -
        .data[[paste0("y", first_year)]],
      rel_change_pct = 100 * (.data[[paste0("y", last_year)]] /
        .data[[paste0("y", first_year)]] - 1),
      direction = dplyr::if_else(abs_change >= 0, "increased", "decreased")) |>
    dplyr::arrange(dplyr::desc(.data[[paste0("y", last_year)]]))
}

#' Derive the 2020 subspecialty workforce sizes from the frozen national summary.
#'
#' By the E2SFCA conservation property the population-weighted national mean equals
#' supply / population, so supply = mean_pop_weighted_per100k * acs_pop_source / 1e5.
#' This re-derives the seven 2020 provider counts from the frozen run itself, giving a
#' second independent method to cross-check the staged workforce CSV (the
#' trust-a-number two-method-agreement rule).
#'
#' @param national_tbl Validated national summary (from [load_e2sfca_national_summary]).
#' @param year Study year (default 2020).
#' @return data.frame of subspecialty + n_providers_derived (integer).
#' @export
e2sfca_workforce_from_run <- function(national_tbl, year = 2020L) {
  yr <- national_tbl[national_tbl$year == year, , drop = FALSE]
  stopifnot(nrow(yr) == 7L,
            all(c("mean_pop_weighted_per100k", "acs_pop_source") %in% names(yr)))
  data.frame(
    subspecialty = yr$subspecialty,
    n_providers_derived = as.integer(round(
      yr$mean_pop_weighted_per100k * yr$acs_pop_source / 1e5)),
    stringsAsFactors = FALSE)
}

#' Canonical 2020 workforce counts (active board-certified provider supply).
#'
#' The seven 2020 provider counts. The staged CSV is the manuscript's consumed
#' artifact; when `national_tbl` is supplied it is CROSS-CHECKED against the counts
#' re-derived from the frozen run ([e2sfca_workforce_from_run]) and fails loudly on any
#' disagreement > 1 (rounding) — so the staged file can never silently drift from the
#' run it claims to summarize.
#'
#' @param path CSV of subspecialty, n_providers.
#' @param national_tbl Optional validated national summary; enables the cross-check.
#' @return A tibble of the seven 2020 workforce rows.
#' @export
e2sfca_workforce_counts <- function(
    path = file.path("manuscript", "data", "workforce_counts_2020.csv"),
    national_tbl = NULL, year = 2020L) {
  stopifnot(file.exists(path))
  workforce_tbl <- readr::read_csv(path, show_col_types = FALSE)
  stopifnot(nrow(workforce_tbl) == 7L, all(workforce_tbl$n_providers > 0))
  if (!is.null(national_tbl)) {
    derived <- e2sfca_workforce_from_run(national_tbl, year = year)
    m <- merge(workforce_tbl, derived, by = "subspecialty")
    stopifnot("staged workforce CSV disagrees with the frozen run" =
                nrow(m) == 7L && all(abs(m$n_providers - m$n_providers_derived) <= 1L))
    base::message("[e2sfca] workforce cross-check vs frozen run: OK (max |diff|=",
                  max(abs(m$n_providers - m$n_providers_derived)), ")")
  }
  base::message("[e2sfca] workforce: ", sum(workforce_tbl$n_providers),
                " providers across ", nrow(workforce_tbl), " specialties (", year, ")")
  workforce_tbl
}

#' Reconcile the disparity/coverage artifacts against the frozen national summary.
#'
#' The paper's central disparity claims (metro:rural ratio, zero-access shares) come
#' from `GO_2020_inferential_MC_CI.csv` and `spatial_outcomes_2020.csv`, which are
#' NOT otherwise pinned to `E2SFCA_FROZEN_RUN_ID`. This fails loud if the GO 2020
#' national mean disagrees across the three sources beyond the disclosed grain
#' tolerance (500 m cell vs 1 km tract), catching a wrong-source substitution that
#' would otherwise render silently. Mirrors the workforce conservation cross-check.
#'
#' @param national_tbl frozen national summary (from [load_e2sfca_national_summary]).
#' @param go_ci_tbl the GO Monte-Carlo CI table (metric/point/lo/hi).
#' @param spatial_tbl the spatial-outcomes table (subspec/national_mean/...).
#' @param tol numeric tolerance (default 0.0015; the disclosed cell-vs-tract grain gap).
#' @return invisibly `TRUE`; `stop()`s on mismatch.
#' @export
e2sfca_reconcile_disparity_artifacts <- function(national_tbl, go_ci_tbl,
                                                 spatial_tbl, tol = 0.0015) {
  frozen <- national_tbl$mean_pop_weighted_per100k[
    national_tbl$subspecialty == "GO" & national_tbl$year == 2020]
  mc <- go_ci_tbl$point[go_ci_tbl$metric == "nat_mean"]
  sp <- spatial_tbl$national_mean[spatial_tbl$subspec == "GO"]
  stopifnot("[reconcile] GO 2020 national mean must resolve to one value per source" =
              length(frozen) == 1L && length(mc) == 1L && length(sp) == 1L &&
              all(is.finite(c(frozen, mc, sp))))
  d <- max(abs(c(mc, sp) - frozen))
  if (d > tol)
    base::stop(sprintf(paste0("[reconcile] GO 2020 national mean disagrees across ",
      "sources by %.5f (> %.4f tol): frozen=%.6f, MC-CI=%.6f, spatial=%.6f. A ",
      "disparity/coverage artifact may be from a different run than ",
      "E2SFCA_FROZEN_RUN_ID."), d, tol, frozen, mc, sp), call. = FALSE)
  base::message(sprintf(paste0("[e2sfca] disparity/coverage artifacts reconcile ",
    "with the frozen run (GO 2020 national mean agrees within %.5f)"), d))
  invisible(TRUE)
}

#' Canonical cross-subspecialty 2020 disparity table (MC 95% CIs + trends).
#'
#' @param path CSV produced by scripts/compile_inferential_table.R.
#' @return A tibble of the seven disparity rows.
#' @export
e2sfca_disparity_2020 <- function(
    path = file.path("artifacts", "2sfca", "figures",
                     "allsubspec_2020_inferential_TABLE.csv")) {
  stopifnot(file.exists(path))
  disparity_tbl <- readr::read_csv(path, show_col_types = FALSE)
  stopifnot(nrow(disparity_tbl) == 7L)
  base::message("[e2sfca] disparity table: ", nrow(disparity_tbl),
                " specialties (source ", basename(path), ")")
  disparity_tbl
}

# ---- run as a script: print the validated canonical value block --------------
if (identical(environment(), globalenv()) &&
    !length(sys.calls())) {
  run_dir <- e2sfca_run_dir()
  national_tbl <- load_e2sfca_national_summary(run_dir)
  change_tbl <- e2sfca_specialty_change(national_tbl)

  fmt3 <- function(x) formatC(x, format = "f", digits = 3)
  fmt1 <- function(x) formatC(x, format = "f", digits = 1)

  cat("\n=== CANONICAL national access per 100,000 women (2013 vs 2023) ===\n")
  print(change_tbl |>
    dplyr::transmute(subspecialty,
      y2013 = fmt3(y2013), y2023 = fmt3(y2023),
      abs = fmt3(abs_change), rel_pct = fmt1(rel_change_pct),
      direction, series_low = fmt3(series_min), low_yr = series_min_year),
    n = 7)

  yr2020 <- national_tbl |> dplyr::filter(year == 2020L) |>
    dplyr::arrange(dplyr::desc(mean_pop_weighted_per100k))
  cat("\n=== 2020 ranking (per 100k women) ===\n")
  print(yr2020 |> dplyr::transmute(subspecialty,
    access_2020 = fmt3(mean_pop_weighted_per100k)), n = 7)
  cat(sprintf("\n2020 range: max %s (%s) / min %s (%s) = %.1f-fold\n",
    fmt3(max(yr2020$mean_pop_weighted_per100k)), yr2020$subspecialty[1],
    fmt3(min(yr2020$mean_pop_weighted_per100k)),
    yr2020$subspecialty[nrow(yr2020)],
    max(yr2020$mean_pop_weighted_per100k) /
      min(yr2020$mean_pop_weighted_per100k)))

  cat(sprintf("\nPopulation represented (2020): %s women\n",
    formatC(national_tbl$acs_pop_source[national_tbl$year == 2020L][1],
      format = "d", big.mark = ",")))
}
