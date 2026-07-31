# ==============================================================================
# helpers.R -- shared logic for the twostep E2SFCA Access Explorer Shiny app.
#
# This app is the twostep ACCESS explorer (supply-to-demand accessibility). It is
# deliberately SEPARATE from, and different in kind to, the isochrones drive-time
# coverage maps: isochrones answers "is a subspecialist reachable"; twostep
# answers "how accessible, per capita and by whom." It reads twostep's frozen
# artifacts and never recomputes them.
#
# Map logic (palette, SUBS map, tertile breaks) is LIFTED FROM
# scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R so the app
# cannot drift from the static Figure 6 / the manuscript maps. Keep in sync.
# ==============================================================================

suppressWarnings(suppressMessages({
  library(dplyr)
  library(ggplot2)
}))

# ---- repo root (works from repo root, Rscript, or an installed package) -------
ax_root <- function() {
  r <- tryCatch(rprojroot::find_root(rprojroot::has_file("DESCRIPTION")),
                error = function(e) NULL)
  if (is.null(r)) r <- tryCatch(here::here(), error = function(e) getwd())
  r
}

# ---- SSOT band / category constants (same source the builders use) -----------
ax_load_ssot <- function(root = ax_root()) {
  suppressWarnings(suppressMessages({
    source(file.path(root, "R", "contour_bands.R"), local = TRUE)     # PRIMARY_ACCESS_BAND_SEC, CANONICAL_BANDS
    source(file.path(root, "R", "access_categories.R"), local = TRUE) # DENOMINATOR_CATEGORY
  }))
  list(primary_band_sec = PRIMARY_ACCESS_BAND_SEC,
       denominator_category = DENOMINATOR_CATEGORY)
}

# ---- vocab -------------------------------------------------------------------
# code -> parquet/CSV subspecialty label (lifted from build_bivariate_leaflet_multisubspec.R SUBS)
AX_SUBS <- c(
  GO   = "Gynecologic Oncology",
  MFM  = "Maternal-Fetal Medicine",
  REI  = "Reproductive Endocrinology & Infertility",
  URPS = "Female Pelvic Medicine & Reconstructive Surgery",
  MIGS = "Minimally Invasive Gynecologic Surgery",
  CFP  = "Complex Family Planning",
  PAG  = "Pediatric & Adolescent Gynecology"
)

# band seconds -> minutes label
AX_BANDS <- c(`1800` = "30 min", `3600` = "60 min", `7200` = "120 min", `10800` = "180 min")

# access-table category -> display label
AX_CATS <- c(
  total_female            = "All women",
  total_female_white_nh   = "White (non-Hispanic)",
  total_female_black      = "Black",
  total_female_hispanic   = "Hispanic",
  total_female_asian      = "Asian",
  total_female_aian       = "AI/AN",
  total_female_two_or_more = "Two or more",
  total_female_other      = "Other"
)

# 3x3 bivariate palette keyed "<access><equity>" (lifted from the builder, so the
# app's map cannot drift from the static Figure 6).
AX_BIPAL <- c("11"="#5a3a4a","12"="#8a4a5a","13"="#c33d5b",
              "21"="#4a6a7a","22"="#8a8a9a","23"="#d98a9a",
              "31"="#3a9a8a","32"="#8ac9b0","33"="#e8e0c0")
AX_NODATA <- "#dcdcdc"

# tertile classifier (same low<33 / med 33-67 / high>67 breaks as the builder)
ax_tertile <- function(x) cut(x, breaks = c(-Inf, 33, 67, Inf), labels = c(1, 2, 3))

# ---- disparity data (the always-present vendored 2023 cross-section) ----------
ax_load_disparity <- function(root = ax_root()) {
  f <- file.path(root, "data", "step_4_access_by_group.csv")
  if (!file.exists(f))
    stop("missing data/step_4_access_by_group.csv (the vendored access-by-group extract)")
  d <- utils::read.csv(f, stringsAsFactors = FALSE)
  d$subspecialty <- as.character(d$subspecialty)
  d$category     <- as.character(d$category)
  d
}

# ---- plots -------------------------------------------------------------------
ax_theme <- function() {
  theme_minimal(base_size = 13) +
    theme(plot.title = element_text(size = rel(1.1)),
          plot.title.position = "plot",
          panel.grid.minor = element_blank(),
          legend.position = "none")
}

# access % by race/ethnicity for one subspecialty + band, 2023 (with MOE bars)
ax_plot_disparity <- function(d, subspec_label, band_sec) {
  sub <- d %>%
    filter(subspecialty == subspec_label, range == band_sec,
           category %in% names(AX_CATS)) %>%
    mutate(cat = factor(AX_CATS[category], levels = rev(unname(AX_CATS))),
           is_all = category == "total_female")
  if (!nrow(sub)) return(NULL)
  ref <- sub$percent[sub$is_all][1]
  ggplot(sub, aes(cat, percent, fill = is_all)) +
    geom_col(width = 0.72) +
    { if (!is.na(ref)) geom_hline(yintercept = ref, linetype = "22", colour = "#556") } +
    geom_errorbar(aes(ymin = pmax(0, percent - percent_moe),
                      ymax = pmin(100, percent + percent_moe)),
                  width = 0.25, colour = "#33414a", na.rm = TRUE) +
    geom_text(aes(label = sprintf("%.0f%%", percent)),
              hjust = -0.15, size = 11, size.unit = "pt", colour = "#33414a") +
    scale_fill_manual(values = c(`TRUE` = "#0d7d76", `FALSE` = "#7fa9a4")) +
    coord_flip(clip = "off") +
    scale_y_continuous(limits = c(0, 105), expand = expansion(mult = c(0, 0.02))) +
    labs(title = sprintf("%% of women within %s of a %s",
                         AX_BANDS[as.character(band_sec)], subspec_label),
         subtitle = "2023, by race/ethnicity. Dashed line = all women. Bars = 90% MOE.",
         x = NULL, y = "% of women with access") +
    ax_theme()
}

# access % across the four bands, all-women, for one subspecialty (the coverage curve)
ax_plot_band_curve <- function(d, subspec_label, denom_cat) {
  sub <- d %>%
    filter(subspecialty == subspec_label, category == denom_cat) %>%
    mutate(band_lab = factor(AX_BANDS[as.character(range)], levels = unname(AX_BANDS)))
  if (!nrow(sub)) return(NULL)
  ggplot(sub, aes(band_lab, percent, group = 1)) +
    geom_line(colour = "#0d7d76", linewidth = 1.1) +
    geom_point(colour = "#0d7d76", size = 2.6) +
    geom_text(aes(label = sprintf("%.0f%%", percent)),
              vjust = -0.9, size = 11, size.unit = "pt", colour = "#33414a") +
    scale_y_continuous(limits = c(0, 105), expand = expansion(mult = c(0, 0.05))) +
    labs(title = sprintf("Access vs drive-time band -- %s", subspec_label),
         subtitle = "2023, all women. Cumulative % within each band.",
         x = "Drive-time band", y = "% of women with access") +
    ax_theme()
}

# ---- SENSITIVITY: decay-weight robustness (live, from the 2023 cross-section) --
# Gaussian decay schemes lifted VERBATIM from scripts/parameter_stability_access.R
# (bands 30/60/120/180 min). `base` equals the engine's E2SFCA_DEFAULT_WEIGHTS.
AX_DECAY <- list(
  base    = c(1.00, 0.68, 0.22, 0.09),
  steeper = c(1.00, 0.50, 0.10, 0.02),
  flatter = c(1.00, 0.85, 0.55, 0.30)
)
AX_DECAY_LABEL <- c(base = "Base (E2SFCA default)", steeper = "Steeper decay", flatter = "Flatter decay")

# decay-weighted composite access per subspecialty per scheme, from the cumulative
# within-band percents (incremental weights, exactly as the appendix does:
# W30*P30 + W60*(P60-P30) + W120*(P120-P60) + W180*(P180-P120)).
ax_sensitivity_table <- function(d) {
  tf <- d[d$category == "total_female", ]
  rng <- c(1800, 3600, 7200, 10800)
  subs <- intersect(unname(AX_SUBS), unique(tf$subspecialty))
  rows <- list()
  for (s in subs) {
    p <- vapply(rng, function(r) { v <- tf$percent[tf$subspecialty == s & tf$range == r]
      if (length(v)) v[1] else NA_real_ }, numeric(1))
    if (any(!is.finite(p))) next
    incr <- c(p[1], diff(p))
    for (k in names(AX_DECAY))
      rows[[paste(s, k)]] <- data.frame(subspecialty = s, scheme = k,
        composite = sum(AX_DECAY[[k]] * incr), step30 = p[1], stringsAsFactors = FALSE)
  }
  out <- do.call(rbind, rows)
  out %>% group_by(scheme) %>% mutate(rank = rank(-composite, ties.method = "min")) %>% ungroup()
}

ax_plot_sensitivity <- function(d, highlight_label = NULL) {
  st <- ax_sensitivity_table(d)
  if (is.null(st) || !nrow(st)) return(NULL)
  ord <- st %>% filter(scheme == "base") %>% arrange(composite) %>% pull(subspecialty)
  st$subspecialty <- factor(st$subspecialty, levels = ord)
  st$scheme <- factor(st$scheme, levels = c("steeper", "base", "flatter"))
  # rank stability across schemes (Spearman of composite vs base)
  wide <- tidyr::pivot_wider(st[, c("subspecialty","scheme","composite")],
                             names_from = scheme, values_from = composite)
  rho_s <- suppressWarnings(round(cor(wide$base, wide$steeper, method = "spearman"), 2))
  rho_f <- suppressWarnings(round(cor(wide$base, wide$flatter, method = "spearman"), 2))
  cols <- c(steeper = "#e8590c", base = "#0d7d76", flatter = "#2f9e44")
  ggplot(st, aes(composite, subspecialty)) +
    geom_line(aes(group = subspecialty), colour = "#c6d0d6", linewidth = 1.4) +
    geom_point(aes(colour = scheme), size = 3.4) +
    { if (!is.null(highlight_label) && highlight_label %in% ord)
        geom_point(data = subset(st, subspecialty == highlight_label),
                   size = 5.2, shape = 21, fill = NA, colour = "#14202a", stroke = 1.1) } +
    scale_colour_manual(values = cols, labels = AX_DECAY_LABEL[c("steeper","base","flatter")], name = NULL) +
    labs(title = "Does the ranking survive the distance-decay assumption?",
         subtitle = sprintf("2023 composite access per subspecialty under three decay schemes. Rank stability vs base: Spearman rho = %.2f (steeper), %.2f (flatter).", rho_s, rho_f),
         x = "Decay-weighted composite access (% of women, incremental weights)", y = NULL) +
    ax_theme() + theme(legend.position = "top")
}

# ---- TEMPORAL: access over 2013-2023 by stratum (from the all-years artifact) --
ax_load_temporal <- function(root = ax_root()) {
  f <- file.path(root, "artifacts", "2sfca", "figures", "allsubspec_allyears_stratified_LONG.csv")
  if (!file.exists(f)) return(NULL)
  utils::read.csv(f, stringsAsFactors = FALSE)
}

# full subspecialty label -> the all-years artifact's subspec code (URPS -> FPMRS)
AX_LONG_CODE <- c(
  "Gynecologic Oncology" = "GO", "Maternal-Fetal Medicine" = "MFM",
  "Reproductive Endocrinology & Infertility" = "REI",
  "Female Pelvic Medicine & Reconstructive Surgery" = "FPMRS",
  "Minimally Invasive Gynecologic Surgery" = "MIGS",
  "Complex Family Planning" = "CFP", "Pediatric & Adolescent Gynecology" = "PAG"
)

ax_plot_temporal <- function(td, subspec_label, stratum_type = "race",
                             metric = c("mean_access", "pct_zero")) {
  metric <- match.arg(metric)
  code <- AX_LONG_CODE[[subspec_label]]
  sub <- td[td$subspec == code & td$stratum_type == stratum_type, ]
  if (!nrow(sub)) return(NULL)
  ylab <- if (metric == "mean_access") "Mean E2SFCA access" else "% with zero access"
  ggplot(sub, aes(year, .data[[metric]], colour = stratum, group = stratum)) +
    geom_smooth(method = "lm", se = FALSE, linewidth = 0.5, linetype = "22", na.rm = TRUE) +
    geom_line(linewidth = 0.9) + geom_point(size = 1.8) +
    scale_x_continuous(breaks = seq(2013, 2023, 2),
                       guide = guide_axis(check.overlap = TRUE)) +
    labs(title = sprintf("%s over time -- %s", ylab, subspec_label),
         subtitle = sprintf("2013-2023, by %s. Dashed = OLS trend.", stratum_type),
         x = NULL, y = ylab, colour = NULL) +
    ax_theme() + theme(legend.position = "right")
}

# ---- SCENARIOS: precomputed accessibility scenario cube (gated) ----------------
# See docs/accessibility-scenario-cube.md. The app READS a frozen slice; it never
# recomputes E2SFCA reactively. Cube expected at artifacts/2sfca/scenario_cube.*.
ax_scenario_cube_path <- function(root = ax_root()) {
  for (ext in c("parquet", "csv")) {
    p <- file.path(root, "artifacts", "2sfca", paste0("scenario_cube.", ext))
    if (file.exists(p)) return(p)
  }
  NA_character_
}
ax_scenario_present <- function(root = ax_root()) !is.na(ax_scenario_cube_path(root))

# ---- PROVENANCE: per-tab data lineage with live presence check ----------------
ax_provenance_df <- function(root = ax_root()) {
  chk  <- function(rel) file.exists(file.path(root, rel))
  chkg <- function(dir, pat) { d <- file.path(root, dir); dir.exists(d) && length(list.files(d, pat)) > 0 }
  data.frame(
    tab = c("Disparities", "Sensitivity", "Temporal (2013-2023)", "Access map"),
    source = c(
      "data/step_4_access_by_group.csv",
      "data/step_4_access_by_group.csv  (+ decay reweighting)",
      "artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv",
      "data/cache/tract_boundaries/*.rds  +  scratchpad/seam_tracts/*.parquet"),
    grain = c(
      "2023 cross-section; subspecialty x band x race-category",
      "2023; all women, 4 bands; recomputed live under 3 decay schemes",
      "subspecialty x year (2013-2023) x stratum (race / rurality)",
      "census tract; bivariate access x minority share"),
    fields = c(
      "range, category, subspecialty, percent, percent_moe, count, total",
      "percent at range 1800/3600/7200/10800 (cumulative within-band, total_female)",
      "subspec, year, stratum_type, stratum, mean_access, pct_zero, women",
      "fips_tract geometry; parquet percent + race totals per tract"),
    lineage = c(
      "Vendored Step-4 access extract (data/PROVENANCE_vendored_inputs.md). SSOT: DENOMINATOR_CATEGORY (R/access_categories.R), band via range.",
      "Decay schemes lifted verbatim from scripts/parameter_stability_access.R; base = E2SFCA_DEFAULT_WEIGHTS from the SHA-gated engine R/two_step_floating_catchment.R. Composite computed live (incremental weights), not stored.",
      "scripts/stratify_allyears_access.R over the frozen E2SFCA production run. Trend = OLS (mirrors accessibility_stratification::annual_trend). Note: artifact code FPMRS = URPS.",
      "Reuses scripts/manuscript_catalog/build_bivariate_leaflet_multisubspec.R (same tertile breaks + 3x3 palette, cannot drift from Figure 6). SSOT: PRIMARY_ACCESS_BAND_SEC, DENOMINATOR_CATEGORY. Gated by the staging discipline (_staging_guard.R)."),
    present = c(
      chk("data/step_4_access_by_group.csv"),
      chk("data/step_4_access_by_group.csv"),
      chk("artifacts/2sfca/figures/allsubspec_allyears_stratified_LONG.csv"),
      chkg("data/cache/tract_boundaries", "\\.rds$") && chkg("scratchpad/seam_tracts", "\\.parquet$")),
    stringsAsFactors = FALSE)
}

# ---- MAP (gated): reuse the bivariate leaflet logic; NULL when the tract layer
#      is not staged locally. Mirrors build_bivariate_leaflet_multisubspec.R. ----
ax_map_inputs_present <- function(root = ax_root()) {
  geo_dir <- file.path(root, "data", "cache", "tract_boundaries")
  pq_dir  <- file.path(root, "scratchpad", "seam_tracts")
  geo <- if (dir.exists(geo_dir)) list.files(geo_dir, "\\.rds$", full.names = TRUE) else character(0)
  pq  <- if (dir.exists(pq_dir))  list.files(pq_dir, "\\.parquet$", full.names = TRUE) else character(0)
  list(ok = length(geo) > 0 && length(pq) > 0, geo = geo, pq = pq,
       geo_dir = geo_dir, pq_dir = pq_dir)
}

# Builds a bivariate access x minority-share leaflet for one subspecialty + band.
# Returns a leaflet widget, or NULL if the staged tract layer is unavailable.
ax_build_map <- function(subspec_label, band_sec, root = ax_root()) {
  ins <- ax_map_inputs_present(root)
  if (!ins$ok) return(NULL)
  suppressWarnings(suppressMessages({
    library(sf); library(arrow); library(data.table); library(leaflet)
  }))
  ssot <- ax_load_ssot(root)
  tryCatch({
    g0 <- readRDS(ins$geo[1])
    gid <- intersect(c("GEOID", "fips_tract"), names(g0))[1]
    g0 <- g0[, gid]; names(g0)[1] <- "fips_tract"
    g0$fips_tract <- as.character(g0$fips_tract)
    g0 <- g0[!substr(g0$fips_tract, 1, 2) %in% c("02","15","60","66","69","72","78"), ]
    g0 <- sf::st_transform(g0, 5070)
    g0 <- sf::st_simplify(g0, dTolerance = 700, preserveTopology = TRUE)
    g0 <- sf::st_transform(g0, 4326)

    ds <- arrow::open_dataset(ins$pq[1])
    cov <- as.data.table(ds %>%
      filter(range == band_sec, category == ssot$denominator_category,
             subspecialty == subspec_label) %>%
      select(fips_tract, percent) %>% collect())
    cov[, fips_tract := as.character(fips_tract)]

    race <- as.data.table(ds %>%
      filter(range == band_sec, subspecialty == subspec_label) %>%
      select(fips_tract, category, total) %>% collect())
    race[, fips_tract := as.character(fips_tract)]
    rw <- dcast(race, fips_tract ~ category, value.var = "total", fun.aggregate = sum)
    denom <- if ("total_female" %in% names(rw)) rw$total_female else NA_real_
    minor <- rowSums(rw[, setdiff(names(rw), c("fips_tract","total_female","total_female_white_nh")), with = FALSE], na.rm = TRUE)
    rw$minority_pct <- 100 * minor / denom

    df <- merge(cov, rw[, .(fips_tract, minority_pct)], by = "fips_tract", all = TRUE)
    df[, ax := as.character(ax_tertile(percent))]
    df[, eq := as.character(ax_tertile(minority_pct))]
    df[, cls := paste0(ax, eq)]
    df[, fill := AX_BIPAL[cls]]
    df[is.na(fill), fill := AX_NODATA]

    m <- merge(g0, df, by = "fips_tract", all.x = TRUE)
    m$fill[is.na(m$fill)] <- AX_NODATA
    pops <- sprintf("<b>Tract %s</b><br>access: %s%%<br>minority share: %s%%",
                    m$fips_tract,
                    ifelse(is.na(m$percent), "n/a", sprintf("%.0f", m$percent)),
                    ifelse(is.na(m$minority_pct), "n/a", sprintf("%.0f", m$minority_pct)))
    leaflet::leaflet(m) |>
      leaflet::addProviderTiles("CartoDB.PositronNoLabels") |>
      leaflet::addPolygons(fillColor = ~fill, fillOpacity = 0.85, weight = 0.2,
                           color = "#ffffff", popup = pops,
                           highlightOptions = leaflet::highlightOptions(weight = 1.5, color = "#000")) |>
      leaflet::setView(-96, 38, zoom = 4)
  }, error = function(e) NULL)
}
