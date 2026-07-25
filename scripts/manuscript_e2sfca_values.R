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
    identical(manifest_json$run_id, "e2sfca_20260712_190734"),
    identical(manifest_json$allocator$method_id, "mass_conserving"),
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

#' Canonical 2020 workforce counts (active board-certified provider supply).
#'
#' Derived from the run's step-4 provider objects (sum of `supply` per
#' specialty); not copied from prose.
#' @param path CSV of subspecialty, year, n_providers, n_origins.
#' @return A tibble of the seven 2020 workforce rows.
#' @export
e2sfca_workforce_counts <- function(
    path = file.path("manuscript", "data", "workforce_counts_2020.csv")) {
  stopifnot(file.exists(path))
  workforce_tbl <- readr::read_csv(path, show_col_types = FALSE)
  stopifnot(nrow(workforce_tbl) == 7L, all(workforce_tbl$n_providers > 0))
  base::message("[e2sfca] workforce: ", sum(workforce_tbl$n_providers),
                " providers across ", nrow(workforce_tbl), " specialties (2020)")
  workforce_tbl
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
  run_dir <- file.path(
    "artifacts", "2sfca", "ec2", "e2sfca_20260712_190734")
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
