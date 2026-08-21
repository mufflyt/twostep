#!/usr/bin/env Rscript
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Panel C — National E2SFCA access, 2013-2023, by subspecialty
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
# Plots population-weighted national E2SFCA access per 100,000 women, one line
# per subspecialty, 2013-2023. Values come DIRECTLY from the authoritative
# cell-level national-summary artifact of the frozen production run
# (e2sfca_20260712_190734, git ff3aac4a) — NOT recomputed from tract averages.
#
# The frozen-run PROVENANCE identifiers below are documented pointers, not
# scientific results. Every plotted value is read from the national-summary
# artifact; none are hardcoded. A sha256 guard fails loud if the artifact drifts.
#
# Deliverables:
#   * manuscript/stats/panel_c_e2sfca_national_access.csv          (source data, 77 rows)
#   * manuscript/figures/panel_c_e2sfca_national_access.{png,tiff} (figure; gitignored)
#
# Axis: MFM runs ~10-25x the smallest series, so a single linear axis would bury
# CFP/PAG. Per the figure spec we use a log10 y-axis (all values > 0), not a
# broken axis.
#
# Author: Tyler Muffly, MD / Claude Code
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

suppressPackageStartupMessages({
  library(here); library(readr); library(dplyr); library(ggplot2)
  library(scales)
})
if (!requireNamespace("digest", quietly = TRUE)) stop("package 'digest' required")

# --- frozen-run provenance (documented identifiers; NOT scientific results) --
RUN_ID       <- "e2sfca_20260712_190734"
GIT_SHA      <- "ff3aac4a7aa97094fc3a9e69422425fe1a52b091"
ALLOCATOR_ID <- "mass_conserving:2b78718bf65c2ecb7a1c99fb027d4aa52aeabc345faf6ec71291197e3fe25c43"
# sha256 of the authoritative national-summary artifact (fail-loud content guard)
EXPECTED_ARTIFACT_SHA256 <- "b33eb3e4f44c2a7f422a32d0b61c1afa5af4f76d55f230918a4dfedf6999ba3a"

EXPECTED_SUBSPECS <- c("CFP", "FPMRS", "GO", "MFM", "MIGS", "PAG", "REI")
EXPECTED_YEARS    <- 2013:2023
VINTAGE_SEAM_X    <- 2019.5   # 2010-vintage (<=2019) -> 2020-vintage (>=2020)

# Input resolution: prefer the run artifact; fall back to the tracked mirror
# (kept in-repo so the figure + test are reproducible in a clean CI checkout).
RUN_DIR      <- Sys.getenv("E2SFCA_RUN_DIR",
                           unset = here("artifacts", "2sfca", "ec2", RUN_ID))
ARTIFACT_CSV <- file.path(RUN_DIR, "e2sfca_national_summary.csv")
MIRROR_CSV   <- here("manuscript", "stats",
                     "e2sfca_national_summary_20260712_190734.csv")
SUMMARY_CSV  <- if (file.exists(ARTIFACT_CSV)) ARTIFACT_CSV else MIRROR_CSV

OUT_CSV <- here("manuscript", "stats", "panel_c_e2sfca_national_access.csv")
OUT_PNG <- here("manuscript", "figures", "panel_c_e2sfca_national_access.png")
OUT_TIF <- here("manuscript", "figures", "panel_c_e2sfca_national_access.tiff")

# --- load + content guard --------------------------------------------------
stopifnot(file.exists(SUMMARY_CSV))
src_sha256 <- digest::digest(file = SUMMARY_CSV, algo = "sha256")
if (!identical(src_sha256, EXPECTED_ARTIFACT_SHA256)) {
  stop(sprintf(paste0("national-summary artifact sha256 mismatch\n  got:      %s\n",
                      "  expected: %s\n  (source: %s)"),
               src_sha256, EXPECTED_ARTIFACT_SHA256, SUMMARY_CSV))
}

ns <- readr::read_csv(SUMMARY_CSV, show_col_types = FALSE)
stopifnot(all(c("subspecialty", "year", "mean_pop_weighted_per100k") %in% names(ns)))

d <- ns %>%
  transmute(specialty = subspecialty,
            year = as.integer(year),
            pop_weighted_mean_per100k = mean_pop_weighted_per100k)

# --- fail-loud completeness contract (77 = 7 x 11) -------------------------
if (nrow(distinct(d, specialty, year)) != 77L)
  stop(sprintf("Expected 77 unique (specialty,year) cells; got %d",
               nrow(distinct(d, specialty, year))))
if (!setequal(unique(d$specialty), EXPECTED_SUBSPECS))
  stop("Subspecialty set mismatch vs expected 7-subspecialty production set")
if (!setequal(unique(d$year), EXPECTED_YEARS))
  stop("Year set mismatch vs expected 2013-2023")
if (any(!is.finite(d$pop_weighted_mean_per100k)) || any(d$pop_weighted_mean_per100k <= 0))
  stop("Non-finite or non-positive access value(s) — log axis / contract violated")

# --- write source-data CSV (77 rows + provenance) --------------------------
src <- d %>%
  arrange(specialty, year) %>%
  mutate(run_id = RUN_ID, git_sha = GIT_SHA, allocator_id = ALLOCATOR_ID,
         source_artifact_sha256 = src_sha256)
dir.create(dirname(OUT_CSV), recursive = TRUE, showWarnings = FALSE)
readr::write_csv(src, OUT_CSV)
message(sprintf("Wrote %s (%d rows)", OUT_CSV, nrow(src)))

# --- figure: 7 lines, log10 y, vintage seam marker, no smoothing -----------
dir.create(dirname(OUT_PNG), recursive = TRUE, showWarnings = FALSE)
y_top <- max(d$pop_weighted_mean_per100k)

p <- ggplot(d, aes(x = year, y = pop_weighted_mean_per100k,
                   colour = specialty, group = specialty)) +
  geom_vline(xintercept = VINTAGE_SEAM_X, linetype = "dashed",
             colour = "grey55", linewidth = 0.4) +
  annotate("text", x = VINTAGE_SEAM_X, y = y_top,
           label = "tract-vintage transition (2010→2020)",
           angle = 90, vjust = -0.4, hjust = 1, size = 8, size.unit = "pt",
           colour = "grey40") +
  geom_line(linewidth = 0.7) +               # NO smoothing (raw annual values)
  geom_point(size = 1.3) +
  scale_x_continuous(breaks = EXPECTED_YEARS,
                     guide = guide_axis(check.overlap = TRUE)) +
  scale_y_log10(labels = label_number(accuracy = 0.01)) +
  scale_colour_brewer(palette = "Dark2", name = "Subspecialty") +
  labs(
    title = "National E2SFCA access to gynecologic subspecialists, 2013-2023",
    subtitle = "Population-weighted access per 100,000 women (log scale)",
    x = NULL, y = "Access per 100,000 women (log10)",
    caption = paste(strwrap(paste0(
      "Population-weighted from the authoritative cell-level national summary ",
      "(run ", RUN_ID, ", mass-conserving allocator). Controlled national seam ",
      "analysis found negligible geometry-only effects across the 2019-2020 ",
      "tract-vintage transition. No smoothing applied."
    ), width = 95), collapse = "\n")
  ) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1)),
        plot.title.position = "plot",
        plot.caption = element_text(size = rel(0.7), hjust = 0),
        panel.grid.minor = element_blank())

ggsave(OUT_PNG, p, width = 9, height = 5.5, dpi = 300, bg = "white")
ggsave(OUT_TIF, p, width = 9, height = 5.5, dpi = 300, bg = "white",
       compression = "lzw")
message(sprintf("Wrote %s and %s", OUT_PNG, OUT_TIF))
message("Panel C build complete.")
