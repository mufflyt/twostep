#!/usr/bin/env Rscript
# ==============================================================================
# figure3_allsubspec_stratified_2020.R
# ------------------------------------------------------------------------------
# Manuscript Figure 3 (replacement). Generalizes the former gynecologic-oncology
# only Figure 3 to ALL SEVEN OB/GYN subspecialties: 2020 population-weighted
# E2SFCA accessibility by (A) rurality and (B) race and ethnicity.
#
# Source of truth (vendored in this repo, so the figure regenerates from twostep
# alone): artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv, the
# same cross-subspecialty stratified series behind Figures 4-6 (frozen run
# e2sfca_20260712_190734). Rurality = USDA RUCA 2020 (Metro = 1-3). Race groups
# are ACS 2020 female totals; race-alone groups are not mutually exclusive with
# the White-non-Hispanic and Hispanic groups.
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(ggplot2); library(patchwork) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
FIG  <- file.path(ROOT, "manuscript", "figures")
dir.create(FIG, showWarnings = FALSE, recursive = TRUE)
LONG <- readr::read_csv(file.path(ROOT, "artifacts", "2sfca", "figures",
          "allsubspec_allyears_stratified_LONG.csv"), show_col_types = FALSE) |>
  mutate(year = as.integer(year), mean_access = as.numeric(mean_access),
         women = as.numeric(women))

disp <- c(MFM = "Maternal-fetal medicine", GO = "Gynecologic oncology",
  REI = "Reproductive endocrinology", FPMRS = "Urogynecology (URPS)",
  MIGS = "Minimally invasive gyn surgery", PAG = "Pediatric & adolescent gyn",
  CFP = "Complex family planning")

d20 <- LONG |> filter(year == 2020L)

# common x-axis across both panels so absolute access is comparable
xmax  <- ceiling(max(d20$mean_access, na.rm = TRUE) / 0.25) * 0.25   # -> 1.25
xscale <- scale_x_continuous(limits = c(0, xmax), breaks = seq(0, xmax, 0.25),
                             expand = expansion(mult = c(0.01, 0.03)))

# row order: national mean per subspecialty (female-weighted over rurality)
ord <- d20 |> filter(stratum_type == "rurality") |>
  group_by(subspec) |>
  summarise(natmean = sum(mean_access * women) / sum(women), .groups = "drop") |>
  arrange(desc(natmean))
lev <- unname(disp[ord$subspec])                 # display names, access-descending
mk  <- function(df) df |> mutate(sub = factor(disp[subspec], levels = rev(lev)))

# ---- Panel A: rurality dumbbell (Rural -> Metropolitan) ----------------------
rw <- d20 |> filter(stratum_type == "rurality") |> mk() |>
  select(sub, rurality = stratum, mean_access) |>
  tidyr::pivot_wider(names_from = rurality, values_from = mean_access)
pA <- ggplot(rw, aes(y = sub)) +
  geom_segment(aes(x = Rural, xend = Metropolitan, yend = sub),
               colour = "grey70", linewidth = 1) +
  geom_point(aes(x = Rural, colour = "Rural"), size = 3) +
  geom_point(aes(x = Metropolitan, colour = "Metropolitan"), size = 3) +
  scale_colour_manual(NULL, values = c(Metropolitan = "#2171b5", Rural = "#cb4b16"),
                      breaks = c("Metropolitan", "Rural")) +
  xscale +
  labs(title = "(A) By rurality", x = "Access per 100,000 women (2020)", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", legend.position = "top",
        panel.grid.major.y = element_blank())

# ---- Panel B: race / ethnicity dot plot (6 groups per subspecialty) ----------
race_lab <- c("Asian alone" = "Asian", "White, non-Hispanic" = "White NH",
  "Black alone" = "Black", "Hispanic (any race)" = "Hispanic",
  "Nat. Hawaiian/Pac. Isl." = "NHPI", "Am. Indian/Alaska Native" = "AIAN")
oi <- c(Asian = "#0072B2", `White NH` = "#E69F00", Black = "#009E73",
        Hispanic = "#CC79A7", NHPI = "#56B4E9", AIAN = "#D55E00")
race <- d20 |> filter(stratum_type == "race") |> mk() |>
  mutate(grp = factor(race_lab[stratum], levels = names(oi)))
seg <- race |> group_by(sub) |>
  summarise(lo = min(mean_access), hi = max(mean_access), .groups = "drop")
pB <- ggplot(race, aes(y = sub)) +
  geom_segment(data = seg, aes(x = lo, xend = hi, yend = sub),
               colour = "grey80", linewidth = 0.8) +
  geom_point(aes(x = mean_access, colour = grp), size = 2.6) +
  scale_colour_manual("Race / ethnicity", values = oi) +
  xscale +
  labs(title = "(B) By race and ethnicity",
       x = "Access per 100,000 women (2020)", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", legend.position = "top",
        panel.grid.major.y = element_blank(), axis.text.y = element_blank())

fig <- (pA | pB) + plot_layout(widths = c(1, 1.05))
ggsave(file.path(FIG, "fig3_allsubspec_stratified_2020.jpg"), fig,
       width = 13, height = 6.2, dpi = 200, bg = "white")
cat("wrote manuscript/figures/fig3_allsubspec_stratified_2020.jpg\n")
