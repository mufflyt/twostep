#!/usr/bin/env Rscript
# ==============================================================================
# map_equity_heatmap.R
# ------------------------------------------------------------------------------
# Greenberg-style "equity at a glance" heatmap: one row per OB/GYN subspecialty,
# one column per disadvantaged group, each cell colored by whether that group's
# 2020 potential accessibility is WORSE / SIMILAR / BETTER than its reference
# group, WITHIN that subspecialty (a within-subspecialty relative contrast, so the
# common-denominator scope differences do not drive the comparison; interpret with
# caution where absolute access is low).
#
# Metric      : population-weighted mean E2SFCA access per 100,000 women (2020).
# Reference   : rurality -> Metropolitan; race/ethnicity -> White, non-Hispanic.
# Classing    : ratio = group / reference. WORSE if <=0.90 (>=10% lower access),
#               BETTER if >=1.10, SIMILAR otherwise. Cell text = % difference.
# Source truth: artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv
#               (the same canonical stratified series behind Figures 3-5).
# No values are hardcoded; everything is read + computed from that CSV.
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(ggplot2) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
LONG <- readr::read_csv(file.path(ROOT, "artifacts", "2sfca", "figures",
  "allsubspec_allyears_stratified_LONG.csv"), show_col_types = FALSE)
YR <- 2020L
THR_LO <- 0.90; THR_HI <- 1.10

# Deliberate SENTENCE-case variant of the canonical figure labels
# (E2SFCA_SUBSPECIALTY_LABELS in scripts/manuscript_e2sfca_values.R). Kept literal
# because a mechanical case transform would corrupt the FPMRS acronym; the guard
# test enforces no en-dash/em-dash here. (Fixed en-dash -> hyphen in "Maternal-fetal".)
full_name <- c(GO = "Gynecologic oncology", MFM = "Maternal-fetal medicine",
  REI = "Reproductive endocrinology", FPMRS = "Urogynecology (FPMRS)",
  MIGS = "Minimally invasive gyn surgery", PAG = "Pediatric & adolescent gyn",
  CFP = "Complex family planning")

d <- LONG |> filter(year == YR)

# reference access per subspecialty (rurality + race references)
ref_rur <- d |> filter(stratum == "Metropolitan") |>
  select(subspec, ref = mean_access)
ref_race <- d |> filter(stratum == "White, non-Hispanic") |>
  select(subspec, ref = mean_access)

# comparison groups (label carries the reference so the figure is self-describing)
cmp <- bind_rows(
  d |> filter(stratum == "Rural") |>
    left_join(ref_rur, by = "subspec") |>
    mutate(group = "Rural\n(vs metro)"),
  d |> filter(stratum == "Black alone") |>
    left_join(ref_race, by = "subspec") |> mutate(group = "Black\n(vs White)"),
  d |> filter(stratum == "Hispanic (any race)") |>
    left_join(ref_race, by = "subspec") |> mutate(group = "Hispanic\n(vs White)"),
  d |> filter(stratum == "Asian alone") |>
    left_join(ref_race, by = "subspec") |> mutate(group = "Asian\n(vs White)"),
  d |> filter(stratum == "Am. Indian/Alaska Native") |>
    left_join(ref_race, by = "subspec") |> mutate(group = "AIAN\n(vs White)"),
  d |> filter(stratum == "Nat. Hawaiian/Pac. Isl.") |>
    left_join(ref_race, by = "subspec") |> mutate(group = "NHOPI\n(vs White)")
) |>
  mutate(ratio = mean_access / ref,
         pct = 100 * (ratio - 1),
         cls = factor(dplyr::case_when(
           ratio <= THR_LO ~ "Worse access",
           ratio >= THR_HI ~ "Better access",
           TRUE            ~ "Similar"),
           levels = c("Worse access", "Similar", "Better access")),
         lab = sprintf("%+.0f%%", pct),
         row = factor(full_name[subspec],
                      levels = full_name[c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")]),
         col = factor(group, levels = c("Rural\n(vs metro)", "Black\n(vs White)",
           "Hispanic\n(vs White)", "Asian\n(vs White)", "AIAN\n(vs White)",
           "NHOPI\n(vs White)")))

pal <- c("Worse access" = "#b2182b", "Similar" = "#f0f0f0",
         "Better access" = "#2166ac")
txtcol <- ifelse(cmp$cls == "Similar", "grey20", "white")

fig <- ggplot(cmp, aes(col, row, fill = cls)) +
  geom_tile(colour = "white", linewidth = 1.1) +
  geom_text(aes(label = lab), colour = txtcol, size = 10, size.unit = "pt",
            fontface = "bold") +
  scale_fill_manual(values = pal, name = NULL, drop = FALSE) +
  scale_x_discrete(position = "top", guide = guide_axis(check.overlap = TRUE)) +
  labs(
    title = "Potential accessibility for disadvantaged groups relative to reference, 2020",
    subtitle = paste0(
      "Each cell compares a group's 2020 population-weighted accessibility with its reference group ",
      "WITHIN that subspecialty.\nRed = ≥10% lower access; blue = ",
      "≥10% higher; grey = within ±10%. Value = percent difference from the reference group. ",
      "Interpret cautiously where absolute access is low."),
    x = NULL, y = NULL,
    caption = paste0("Reference groups: rurality = metropolitan; race and ethnicity = White, non-Hispanic. ",
      "Enhanced two-step floating catchment area access per 100,000 female residents; ",
      "tract-level population-weighted; contiguous United States. AIAN, American Indian or Alaska Native; ",
      "NHOPI, Native Hawaiian or Other Pacific Islander.")) +
  theme_minimal(base_size = 13) +
  theme(plot.title = element_text(size = rel(1.15), face = "bold"),
        plot.title.position = "plot",
        plot.subtitle = element_text(size = rel(0.8), colour = "grey30"),
        plot.caption = element_text(size = rel(0.66), colour = "grey40", hjust = 0),
        axis.text.x.top = element_text(face = "bold", size = rel(0.9)),
        axis.text.y = element_text(face = "bold", size = rel(0.95)),
        panel.grid = element_blank(),
        legend.position = "bottom",
        plot.margin = margin(10, 14, 10, 10))

FIG <- file.path(ROOT, "manuscript", "figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
out_jpg <- file.path(FIG, "fig_equity_heatmap.jpg")
ggsave(out_jpg, fig, width = 11, height = 6.4, dpi = 200, bg = "white")
cat("wrote", out_jpg, "\n")

# echo the underlying numbers so the figure is auditable against the CSV
cat("\n2020 group-vs-reference ratios (from canonical stratified series):\n")
print(as.data.frame(cmp |> arrange(row, col) |>
  transmute(subspecialty = subspec, group = gsub("\n", " ", group),
            group_access = round(mean_access, 3), ref_access = round(ref, 3),
            ratio = round(ratio, 3), pct = round(pct, 1),
            class = as.character(cls))), row.names = FALSE)
