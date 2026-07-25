#!/usr/bin/env Rscript
# ==============================================================================
# figure_2sfca_national_11yr.R
# ------------------------------------------------------------------------------
# Publication figure for the COMPLETE 11-year national E2SFCA production series
# (2013-2023, 7 OB/GYN subspecialties, CONUS, 500 m EPSG:5070), computed under
# the seam-validated mass-conserving area-overlap allocator
# (allocate_pop_areaweighted, module sha 2b78718b == seam gate).
#
#   Panel A : 2020 national accessibility by subspecialty (production run)
#   Panel B : 11-year national accessibility trends, per subspecialty
# (The demand-conservation validation panel was removed as a methods detail —
#  see note below; it is stated in the manuscript Methods instead.)
#
# Source of truth: the verified production national summary (checksum-matched):
#   artifacts/2sfca/ec2/<RUN_ID>/e2sfca_national_summary.csv
# Follows project ggplot2 standards (title size rel, title.position=plot,
# check.overlap axis, geom_text size.unit=pt, ggsave bg=white).
# ==============================================================================
suppressWarnings(suppressMessages({
  library(ggplot2); library(dplyr); library(patchwork)
}))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
# SSOT: frozen run id (and its E2SFCA_RUN_ID env override) come from the canonical
# constant in scripts/manuscript_e2sfca_values.R; no local literal default.
source(file.path(ROOT, "scripts", "manuscript_e2sfca_values.R"))
RUN_ID <- E2SFCA_FROZEN_RUN_ID
NAT_CSV <- file.path(ROOT, "artifacts", "2sfca", "ec2", RUN_ID, "e2sfca_national_summary.csv")
OUT  <- file.path(ROOT, "artifacts", "2sfca", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
stopifnot(file.exists(NAT_CSV))

# SSOT: national 2020 ACS female-pop denominator from the canonical constant
# (scripts/manuscript_e2sfca_values.R), pinned to the frozen artifact by the tests.
ACS2020 <- E2SFCA_ACS_FEMALE_POP_2020
nat <- readr::read_csv(NAT_CSV, show_col_types = FALSE)
mcol <- "mean_pop_weighted_per100k"
stopifnot(mcol %in% names(nat), nrow(nat) == 77L)

# Colorblind-safe (Okabe-Ito) palette, ordered by 2020 accessibility (low->high).
ord20 <- nat |> filter(year == 2020L) |> arrange(mean_pop_weighted_per100k) |> pull(subspecialty)
pal <- setNames(c("#000000","#E69F00","#56B4E9","#009E73","#F0E442","#0072B2","#D55E00"), ord20)
nat <- nat |> mutate(subspecialty = factor(subspecialty, levels = ord20))

# NOTE: the demand-conservation validation panel (mass-conserving vs legacy
# center-based allocation) was removed from this clinical figure — it is a
# methods point (the 0.00% vs 1.06% loss is stated in the manuscript Methods),
# not a clinical result, and its truncated y-axis overstated a ~1% difference.

# ── Panel A: national E2SFCA accessibility by subspecialty (2020, production) ─
b <- nat |> filter(year == 2020L) |>
  transmute(subspec = subspecialty, mean = .data[[mcol]], n = n_cells_valid) |>
  arrange(mean) |> mutate(subspec = factor(subspec, levels = subspec))
fold    <- max(b$mean) / min(b$mean)
top_lab <- as.character(b$subspec[which.max(b$mean)])
bot_lab <- as.character(b$subspec[which.min(b$mean)])

pB <- ggplot(b, aes(mean, subspec)) +
  geom_segment(aes(x = 0, xend = mean, yend = subspec), colour = "grey82", linewidth = 0.7) +
  geom_point(aes(fill = subspec), shape = 21, colour = "white", size = 5, stroke = 1.1) +
  geom_text(aes(label = sprintf("%.3f", mean)), hjust = -0.35, size = 10, size.unit = "pt",
            colour = "grey25", fontface = "bold") +
  scale_fill_manual(values = pal, guide = "none") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.24)),
                     guide = guide_axis(check.overlap = TRUE)) +
  labs(title = "A. National accessibility by subspecialty (2020)",
       subtitle = sprintf("E2SFCA providers per 100,000 women, a %.0f-fold spread from %s to %s",
                          fold, bot_lab, top_lab),
       x = "Accessibility (per 100k women)", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", panel.grid.major.y = element_blank(),
        panel.grid.minor.x = element_blank(),
        axis.text.y = element_text(face = "bold"))

# ── Panel C: 11-year national accessibility trends per subspecialty ───────────
# Log y so the 25x spread (CFP ~0.04 .. MFM ~1.0) resolves all trends together.
lab23 <- nat |> filter(year == 2023L)
pC <- ggplot(nat, aes(year, .data[[mcol]], colour = subspecialty, group = subspecialty)) +
  geom_line(linewidth = 0.9) + geom_point(size = 1.6) +
  ggrepel::geom_text_repel(data = lab23, aes(label = subspecialty), hjust = 0,
            direction = "y", nudge_x = 0.15, size = 9 / ggplot2::.pt, fontface = "bold",
            segment.size = 0.25, segment.colour = "grey75", min.segment.length = 0,
            box.padding = 0.1, xlim = c(2023.2, NA), seed = 1) +
  scale_colour_manual(values = pal, guide = "none") +
  scale_x_continuous(breaks = 2013:2023, limits = c(2013, 2024.2),
                     guide = guide_axis(check.overlap = TRUE)) +
  scale_y_log10() +
  labs(title = "B. National accessibility over time, 2013-2023",
       subtitle = "Per-year cohorts (retirement, certification, relocation) drive the trends; log scale",
       x = NULL, y = "Accessibility (per 100k women, log)") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", panel.grid.minor = element_blank())

fig <- pB / pC +
  plot_layout(heights = c(1, 1.15)) +
  plot_annotation(
    title = "National spatial accessibility to OB/GYN subspecialists, 2013-2023 (E2SFCA, CONUS)",
    subtitle = "Complete 11-year national series, all seven ABOG-certified subspecialties (CONUS)",
    caption = sprintf("Run %s | 500 m equal-area (EPSG:5070); ACS B01001_026 female pop; 77/77 (subspec x year) cells, conservation to 1e-14; allocator sha 2b78718b == seam.",
                      RUN_ID),
    theme = theme(plot.title = element_text(size = rel(1.25), face = "bold"),
                  plot.title.position = "plot"))

out_png <- file.path(OUT, sprintf("fig_2sfca_national_11yr_%s.png", RUN_ID))
ggsave(out_png, fig, width = 12, height = 9, dpi = 200, bg = "white")
cat(sprintf("wrote %s\n", out_png))
