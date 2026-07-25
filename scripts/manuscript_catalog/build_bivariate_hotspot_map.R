#!/usr/bin/env Rscript
# ============================================================================
# Figures 6 & 7 for ALL SEVEN subspecialties (faceted, never pooled):
#   Figure 6: 3x3 bivariate choropleth (60-min access x minority population
#             share) per discipline, one shared 3x3 arrow legend.
#   Figure 7: Getis-Ord Gi* hotspot map (kNN=8) of 60-min access per discipline.
# Grey = no coverage data (Wyoming). Inputs: tracts_y2020_cb0_51st_v1.rds +
# 2023 step-4 coverage parquet. Outputs -> manuscript/figures/{figure6_bivariate_go_access,
# figure7_getis_ord_go_hotspots,figure6_bivariate_legend}.png + hotspot_go_summary.csv
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(tidyr); library(data.table)
  library(sf); library(ggplot2); library(patchwork)
}))
BAND <- 3600L
FIGDIR <- "manuscript/figures"; dir.create(FIGDIR, showWarnings = FALSE, recursive = TRUE)
dir.create("manuscript/stats", showWarnings = FALSE, recursive = TRUE)
FULL <- c(
  "Maternal-Fetal Medicine"                         = "Maternal-Fetal Medicine",
  "Gynecologic Oncology"                            = "Gynecologic Oncology",
  "Reproductive Endocrinology & Infertility"        = "Reproductive Endocrinology and Infertility",
  "Female Pelvic Medicine & Reconstructive Surgery" = "Urogynecology and Reconstructive Pelvic Surgery",
  "Minimally Invasive Gynecologic Surgery"          = "Minimally Invasive Gynecologic Surgery",
  "Complex Family Planning"                         = "Complex Family Planning",
  "Pediatric & Adolescent Gynecology"               = "Pediatric and Adolescent Gynecology")

message("[1/5] geometry ...")
g0 <- readRDS("data/cache/tract_boundaries/tracts_y2020_cb0_51st_v1.rds")
gid <- intersect(c("GEOID","fips_tract"), names(g0))[1]; g0 <- g0[, gid]; names(g0)[1] <- "fips_tract"
g0$fips_tract <- as.character(g0$fips_tract)
g0 <- g0[!substr(g0$fips_tract,1,2) %in% c("02","15","60","66","69","72","78"), ]
g0 <- st_transform(g0, 5070)
g0 <- st_simplify(g0, dTolerance = 900, preserveTopology = TRUE)
base <- g0[, "fips_tract"]

message("[2/5] coverage + minority share ...")
ds <- open_dataset("scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet")
cov <- as.data.table(ds %>% filter(range == BAND, category == "total_female") %>%
  select(fips_tract, subspecialty, percent) %>% collect())
cov <- cov[subspecialty %in% names(FULL) & is.finite(percent)]
cov[, disc := factor(FULL[subspecialty], levels = unname(FULL))]
race <- as.data.table(ds %>% filter(range == BAND, subspecialty == "Gynecologic Oncology") %>%
  select(fips_tract, category, total) %>% collect())
rw <- dcast(race, fips_tract ~ category, value.var = "total", fun.aggregate = function(x) x[1])
setnames(rw, gsub("^total_female_?", "", names(rw))); if ("" %in% names(rw)) setnames(rw, "", "fem")
minc <- intersect(c("black","hispanic","asian","aian","other","two_or_more"), names(rw))
rw[, minority := rowSums(.SD, na.rm = TRUE), .SDcols = minc]
rw[, minority_share := 100 * minority / fem]
rw <- rw[is.finite(minority_share) & fem > 0]
# shared minority tertile
mbr <- unique(quantile(rw$minority_share, c(0,1/3,2/3,1), na.rm = TRUE))
rw[, ay := cut(minority_share, breaks = mbr, include.lowest = TRUE, labels = c(1,2,3))]

message("[3/5] Figure 6: faceted bivariate ...")
bipal <- c("11"="#5a3a4a","12"="#8a4a5a","13"="#c33d5b",
           "21"="#4a6a7a","22"="#8a8a9a","23"="#d98a9a",
           "31"="#3a9a8a","32"="#8ac9b0","33"="#e8e0c0")
biv <- merge(cov[, .(fips_tract, disc, percent)], rw[, .(fips_tract, ay, fem, minority_share)], by = "fips_tract")
biv[, ax := cut(percent, breaks = c(-Inf, 100/3, 200/3, Inf), labels = c(1,2,3))]
biv[, bikey := paste0(ax, ay)]
gbiv <- merge(g0, biv[, .(fips_tract, disc, bikey)], by = "fips_tract", allow.cartesian = TRUE)
pmap <- ggplot() +
  geom_sf(data = base, fill = "grey88", color = NA) +
  geom_sf(data = gbiv, aes(fill = bikey), color = NA) +
  facet_wrap(~ disc, ncol = 2) +
  scale_fill_manual(values = bipal, guide = "none") +
  labs(title = "60-minute access and minority population share, by subspecialty (2023)",
       subtitle = "Darkest red = low access co-occurring with high minority share. Grey = no data (Wyoming). Disciplines not pooled.") +
  theme_void(base_size = 12) +
  theme(plot.title = element_text(face = "bold", size = rel(1.02)),
        plot.subtitle = element_text(size = rel(0.78), color = "grey30"),
        plot.title.position = "plot",
        strip.text = element_text(face = "bold", size = 9, margin = margin(3,3,3,3)))
leg <- expand.grid(ax = 1:3, ay = 1:3); leg$bikey <- paste0(leg$ax, leg$ay)
pLeg <- ggplot(leg, aes(ax, ay, fill = bikey)) + geom_tile(color = "white", linewidth = 0.5) +
  scale_fill_manual(values = bipal, guide = "none") +
  annotate("segment", x = 0.4, xend = 3.6, y = 0.25, yend = 0.25,
           arrow = grid::arrow(length = grid::unit(0.14,"cm")), linewidth = 0.5) +
  annotate("segment", x = 0.25, xend = 0.25, y = 0.4, yend = 3.6,
           arrow = grid::arrow(length = grid::unit(0.14,"cm")), linewidth = 0.5) +
  annotate("text", x = 2, y = -0.28, label = "Higher access", size = 3) +
  annotate("text", x = -0.28, y = 2, label = "Higher minority share", angle = 90, size = 3) +
  coord_equal(clip = "off") + theme_void(base_size = 9) + theme(plot.margin = margin(6,8,18,18))
final6 <- pmap + patchwork::inset_element(pLeg, left = 0.52, bottom = 0.02, right = 0.99, top = 0.30, align_to = "full")
ggsave(file.path(FIGDIR, "figure6_bivariate_go_access.png"), final6, width = 11, height = 12, dpi = 250, bg = "white")
ggsave(file.path(FIGDIR, "figure6_bivariate_legend.png"), pLeg, width = 2.2, height = 2.2, dpi = 300, bg = "white")

message("[4/5] Figure 7: faceted Getis-Ord Gi* ...")
if (requireNamespace("spdep", quietly = TRUE)) {
  ctr <- st_coordinates(st_centroid(st_geometry(g0)))
  knn <- spdep::knn2nb(spdep::knearneigh(ctr, k = 8))
  lw  <- spdep::nb2listw(spdep::include.self(knn), style = "B")
  key <- data.table(fips_tract = g0$fips_tract)
  hotlist <- rbindlist(lapply(unname(FULL), function(dl) {
    v <- cov[disc == dl][match(key$fips_tract, fips_tract), percent]
    v[is.na(v)] <- 0
    z <- as.numeric(spdep::localG(v, lw))
    data.table(fips_tract = key$fips_tract, disc = dl, giz = z)
  }))
  hotlist[, hot := cut(giz, c(-Inf,-2.58,-1.96,1.96,2.58,Inf),
                       labels = c("Cold 99%","Cold 95%","n.s.","Hot 95%","Hot 99%"))]
  hotlist[, disc := factor(disc, levels = unname(FULL))]
  ghot <- merge(g0, hotlist, by = "fips_tract", allow.cartesian = TRUE)
  hotpal <- c("Cold 99%"="#2166ac","Cold 95%"="#92c5de","n.s."="#f0f0f0",
              "Hot 95%"="#f4a582","Hot 99%"="#b2182b")
  p7 <- ggplot() +
    geom_sf(data = base, fill = "grey88", color = NA) +
    geom_sf(data = ghot, aes(fill = hot), color = NA) +
    facet_wrap(~ disc, ncol = 2) +
    scale_fill_manual(values = hotpal, name = "Gi* cluster\n(60-min access)") +
    labs(title = "Getis-Ord Gi* clusters of 60-minute access, by subspecialty (2023)",
         subtitle = "Blue = clusters of LOW access (access deserts); red = high-access clusters. Grey = no data (Wyoming).") +
    theme_void(base_size = 12) +
    theme(plot.title = element_text(face = "bold", size = rel(1.02)),
          plot.subtitle = element_text(size = rel(0.78), color = "grey30"),
          plot.title.position = "plot", legend.position = "right",
          strip.text = element_text(face = "bold", size = 9, margin = margin(3,3,3,3)))
  ggsave(file.path(FIGDIR, "figure7_getis_ord_go_hotspots.png"), p7, width = 11, height = 12, dpi = 250, bg = "white")
  # GO summary retained for the Results text
  go <- merge(hotlist[disc == "Gynecologic Oncology"], rw[, .(fips_tract, fem, minority_share)], by = "fips_tract")
  summ <- go[, .(tracts = .N, women_M = round(sum(fem,na.rm=TRUE)/1e6,1),
                 mean_minority = round(mean(minority_share,na.rm=TRUE),1)), by = hot][order(hot)]
  fwrite(summ, "manuscript/stats/hotspot_go_summary.csv")
  message("[5/5] GO hotspot summary:"); print(summ)
}
message("DONE.")
