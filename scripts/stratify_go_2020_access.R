#!/usr/bin/env Rscript
# ==============================================================================
# stratify_go_2020_access.R
# ------------------------------------------------------------------------------
# Rurality- and race/ethnicity-stratified GO 2020 E2SFCA accessibility — the
# direct parallel to Desjardins et al. 2023 (Obstet Gynecol) Table.
#
# Access  : per-tract GO 2020 access (access_mean_population_per100k) from the
#           verified production run (mass-conserving allocator).
# Rurality: USDA RUCA 2020 tract crosswalk (Metropolitan = RUCA 1-3, else Rural).
# Race    : ACS 2020 B01001[*]_017 = FEMALE TOTAL per race/ethnicity group
#           (race-iterated tables use _017 for female total, NOT _026).
#
# For each stratum we report the FEMALE-POPULATION-WEIGHTED mean access (the
# access experienced by the average woman in that group) and the share of that
# group's women in tracts with ZERO reachable GO (parallel to "no physician
# within 100 miles").
# ==============================================================================
suppressWarnings(suppressMessages({ library(dplyr); library(ggplot2); library(patchwork) }))
ROOT <- if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(".")
OUT  <- file.path(ROOT, "artifacts", "2sfca", "figures")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)
say <- function(...) cat(sprintf("[strat] %s\n", sprintf(...)))
conus <- function() sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))

# ── 1. per-tract GO 2020 access (production, verified) ───────────────────────
acc_rds <- Sys.getenv("GO2020_ACCESS_RDS",
  file.path(ROOT, "artifacts", "2sfca", "ec2", "e2sfca_20260712_190734",
            "run_e2sfca_20260712_190734", "step_4_2sfca_GO_2020.rds"))
if (!file.exists(acc_rds)) acc_rds <- Sys.getenv("GO2020_ACCESS_RDS_FALLBACK", acc_rds)
stopifnot(file.exists(acc_rds))
acc <- readRDS(acc_rds) |>
  transmute(GEOID = as.character(GEOID), access = access_mean_population_per100k)
say("access tracts: %d  (zero-access: %d)", nrow(acc), sum(acc$access == 0, na.rm = TRUE))

# ── 2. rurality (RUCA 2020) ──────────────────────────────────────────────────
ruca <- read.csv(file.path(ROOT, "data", "external", "ruca_tract_mapping.csv"),
                 colClasses = "character") |>
  transmute(GEOID = tract_geoid,
            rurality = ifelse(as.integer(ruca_code) %in% 1:3, "Metropolitan", "Rural"))
say("RUCA crosswalk tracts: %d", nrow(ruca))

# ── 3. ACS 2020 female denominators: total + by race/ethnicity ───────────────
# race-iterated female TOTAL = _017 (NOT _026). H = White non-Hispanic,
# I = Hispanic (any race); B/C/D/E = race alone.
vars <- c(total_f = "B01001_026", white_nh = "B01001H_017", hispanic = "B01001I_017",
          black = "B01001B_017", aian = "B01001C_017", asian = "B01001D_017",
          nhpi = "B01001E_017")
say("fetching ACS 2020 female denominators (total + 6 race/ethnicity groups)")
raw <- purrr::map_dfr(conus(), function(s) suppressMessages(tidycensus::get_acs(
  geography = "tract", variables = vars, state = s, year = 2020L, geometry = FALSE)))
den <- raw |>
  transmute(GEOID = as.character(GEOID), variable, estimate = as.numeric(estimate)) |>
  tidyr::pivot_wider(names_from = variable, values_from = estimate)
say("ACS denominator tracts: %d", nrow(den))

# ── 4. join (inner on GEOID) ─────────────────────────────────────────────────
d <- acc |> inner_join(ruca, by = "GEOID") |> inner_join(den, by = "GEOID")
say("joined tracts: %d (access %d / ruca %d / acs %d)", nrow(d), nrow(acc), nrow(ruca), nrow(den))
d$access[is.na(d$access)] <- 0

# weighted helpers
wmean <- function(x, w) { ok <- !is.na(x) & !is.na(w) & w > 0; sum(x[ok]*w[ok]) / sum(w[ok]) }
zero_share <- function(access, w) { ok <- !is.na(w) & w > 0; sum(w[ok][access[ok] == 0]) / sum(w[ok]) }

# ── 5a. rurality strata (weighted by total female) ───────────────────────────
rur <- d |> group_by(rurality) |>
  summarise(women = sum(total_f, na.rm = TRUE),
            mean_access = wmean(access, total_f),
            pct_zero = 100 * zero_share(access, total_f),
            n_tracts = n(), .groups = "drop")
overall_rur <- tibble(rurality = "All (CONUS)", women = sum(d$total_f, na.rm = TRUE),
            mean_access = wmean(d$access, d$total_f),
            pct_zero = 100 * zero_share(d$access, d$total_f), n_tracts = nrow(d))
rur_tbl <- bind_rows(overall_rur, rur)
ratio <- rur$mean_access[rur$rurality=="Metropolitan"] / rur$mean_access[rur$rurality=="Rural"]

# ── 5b. race/ethnicity strata (each weighted by that group's female pop) ─────
grp <- tibble::tribble(~key, ~label,
  "white_nh","White, non-Hispanic", "black","Black alone", "hispanic","Hispanic (any race)",
  "asian","Asian alone", "aian","Am. Indian/Alaska Native alone", "nhpi","Native Hawaiian/Pacific Isl. alone")
race_tbl <- purrr::map_dfr(seq_len(nrow(grp)), function(i) {
  w <- d[[grp$key[i]]]
  tibble(group = grp$label[i], women = sum(w, na.rm = TRUE),
         mean_access = wmean(d$access, w), pct_zero = 100 * zero_share(d$access, w))
}) |> arrange(mean_access)

say("=== RURALITY ===");  print(as.data.frame(rur_tbl), digits = 4)
say("Metropolitan:Rural access ratio = %.1fx", ratio)
say("=== RACE/ETHNICITY ==="); print(as.data.frame(race_tbl), digits = 4)

readr::write_csv(rur_tbl,  file.path(OUT, "go_2020_access_by_rurality.csv"))
readr::write_csv(race_tbl, file.path(OUT, "go_2020_access_by_race.csv"))

# ── 6. figure ────────────────────────────────────────────────────────────────
rur_p <- rur_tbl |> filter(rurality != "All (CONUS)") |>
  mutate(rurality = factor(rurality, levels = c("Metropolitan","Rural")))
pA <- ggplot(rur_p, aes(rurality, mean_access, fill = rurality)) +
  geom_col(width = 0.6) +
  geom_text(aes(label = sprintf("%.3f\n(%.1f%% zero access)", mean_access, pct_zero)),
            vjust = -0.25, size = 10, size.unit = "pt") +
  scale_fill_manual(values = c(Metropolitan = "#2171b5", Rural = "#cb4b16"), guide = "none") +
  scale_y_continuous(expand = expansion(mult = c(0, 0.25))) +
  labs(title = "A. Access by rurality",
       subtitle = sprintf("Metropolitan : Rural ratio = %.1fx (population-weighted)", ratio),
       x = NULL, y = "GO access (per 100k women)") +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", panel.grid.major.x = element_blank())

race_p <- race_tbl |> mutate(group = factor(group, levels = group))
pB <- ggplot(race_p, aes(mean_access, group)) +
  geom_segment(aes(x = 0, xend = mean_access, yend = group), colour = "grey75") +
  geom_point(size = 4, colour = "#6a51a3") +
  geom_text(aes(label = sprintf("%.3f  (%.1f%% zero)", mean_access, pct_zero)),
            hjust = -0.12, size = 9, size.unit = "pt", colour = "grey20") +
  scale_x_continuous(expand = expansion(mult = c(0, 0.34)),
                     guide = guide_axis(check.overlap = TRUE)) +
  labs(title = "B. Access by race / ethnicity",
       subtitle = "Weighted by each group's female population; '% zero' = women with no GO reachable",
       x = "GO access (per 100k women)", y = NULL) +
  theme_minimal(base_size = 12) +
  theme(plot.title = element_text(size = rel(1.1), face = "bold"),
        plot.title.position = "plot", panel.grid.major.y = element_blank())

fig <- (pA | pB) +
  plot_layout(widths = c(1, 1.6)) +
  plot_annotation(
    title = "GO accessibility disparities by rurality and race/ethnicity — E2SFCA, 2020 (CONUS)",
    subtitle = "Parallel to Desjardins et al. 2023 (Obstet Gynecol): population-weighted E2SFCA access per 100,000 women; travel-time catchment, tract level",
    caption = "Access = production mass-conserving E2SFCA (run e2sfca_20260712_190734). Rurality = USDA RUCA 2020 (Metro=1-3). Race = ACS 2020 B01001[*]_017 female totals (H=White NH, I=Hispanic; B/C/D/E race-alone, not mutually exclusive with H/I).",
    theme = theme(plot.title = element_text(size = rel(1.25), face = "bold"),
                  plot.title.position = "plot"))

out_png <- file.path(OUT, "fig_go_2020_access_stratified.png")
ggsave(out_png, fig, width = 13, height = 6.5, dpi = 200, bg = "white")
say("wrote %s", out_png)
