#!/usr/bin/env Rscript
# ============================================================================
# Figure 5: faceted 60-minute geographic-access choropleth for ALL SEVEN
# obstetric-gynecologic subspecialties (2023). One panel per discipline, shared
# 0-100% color scale, full discipline names as panel titles. Grey = no coverage
# data (Wyoming). Never pooled. This is the paper's primary "all subspecialties"
# figure.
# Inputs (local, corrected lineage): tracts_y2020_cb0_51st_v1.rds + the 2023
# step-4 coverage parquet. Output -> manuscript/figures/figure1_subspecialty_access_map.png
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(data.table); library(sf); library(ggplot2)
}))
source("R/contour_bands.R"); source("R/access_categories.R")  # SSOT: F/G access constants (R/contour_bands.R, R/access_categories.R)
BAND <- PRIMARY_ACCESS_BAND_SEC
FIGDIR <- "manuscript/figures"; dir.create(FIGDIR, showWarnings = FALSE, recursive = TRUE)
FULL <- c(
  "Maternal-Fetal Medicine"                         = "Maternal-Fetal Medicine",
  "Gynecologic Oncology"                            = "Gynecologic Oncology",
  "Reproductive Endocrinology & Infertility"        = "Reproductive Endocrinology and Infertility",
  "Female Pelvic Medicine & Reconstructive Surgery" = "Urogynecology and Reconstructive Pelvic Surgery",
  "Minimally Invasive Gynecologic Surgery"          = "Minimally Invasive Gynecologic Surgery",
  "Complex Family Planning"                         = "Complex Family Planning",
  "Pediatric & Adolescent Gynecology"               = "Pediatric and Adolescent Gynecology")

message("[1/4] geometry ...")
g <- readRDS("data/cache/tract_boundaries/tracts_y2020_cb0_51st_v1.rds")
gid <- intersect(c("GEOID","fips_tract"), names(g))[1]; g <- g[, gid]; names(g)[1] <- "fips_tract"
g$fips_tract <- as.character(g$fips_tract)
# SSOT anchor (NON_CONUS_FIPS): canonical non-contiguous set in scripts/manuscript_e2sfca_values.R (complement of CONUS_STATE_FIPS); guarded by tests/testthat/test-ssot-nonconus-fips.R
g <- g[!substr(g$fips_tract,1,2) %in% c("02","15","60","66","69","72","78"), ]  # CONUS
g <- st_transform(g, 5070)
g <- st_simplify(g, dTolerance = 900, preserveTopology = TRUE)  # faster faceted render
base <- g[, "fips_tract"]  # grey underlay (shows in every facet)

message("[2/4] coverage (7 disciplines) ...")
source("scripts/manuscript_catalog/_staging_guard.R")  # fail-loud if comparator inputs not staged
ds <- open_dataset("scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet")
cov <- as.data.table(ds %>% filter(range == BAND, category == DENOMINATOR_CATEGORY) %>%
  select(fips_tract, subspecialty, percent) %>% collect())
cov <- cov[subspecialty %in% names(FULL) & is.finite(percent)]
cov[, disc := factor(FULL[subspecialty], levels = unname(FULL))]

message("[3/4] join + facet ...")
gl <- merge(g, cov[, .(fips_tract, disc, percent)], by = "fips_tract", allow.cartesian = TRUE)

p <- ggplot() +
  geom_sf(data = base, fill = "grey88", color = NA) +
  geom_sf(data = gl, aes(fill = percent), color = NA) +
  facet_wrap(~ disc, ncol = 2) +
  scale_fill_viridis_c(name = "Women within\n60-min drive (%)", limits = c(0, 100),
                       option = "viridis", direction = 1) +
  labs(title = "Geographic access to each obstetric-gynecologic subspecialty, 2023",
       subtitle = "Census-tract percentage of women within a 60-minute drive. Grey = no data (Wyoming). Each discipline analyzed separately.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = rel(1.05)),
        plot.subtitle = element_text(size = rel(0.8), color = "grey30"),
        plot.title.position = "plot",
        strip.text = element_text(face = "bold", size = 10, margin = margin(3,3,3,3)),
        legend.position = "right")

message("[4/4] saving ...")
ggsave(file.path(FIGDIR, "figure1_subspecialty_access_map.png"), p,
       width = 11, height = 12, dpi = 250, bg = "white")
cat("DONE -> figure1_subspecialty_access_map.png\n")
