#!/usr/bin/env Rscript
# ============================================================================
# Interactive Leaflet version of Figure 6 (bivariate GO access map).
#
# A bivariate choropleth of contiguous-US census tracts for Gynecologic
# Oncology (GO):
#   X axis (access)  = share of women reachable to a GO within 60 min, tertiles
#   Y axis (equity)  = minority female population share, tertiles
#   fill             = 3x3 bivariate palette (dark red = low access AND high
#                      minority share = the equity-concern tracts). Grey = no data.
#
# Same tertile breaks and palette as build_bivariate_hotspot_map.R so the
# interactive map cannot drift from the static Figure 6. Popups expose each
# tract's actual access %, minority share %, female population, and class.
#
# Output -> manuscript/figures/figure6_bivariate_go_access_INTERACTIVE.html
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(data.table)
  library(sf); library(leaflet); library(htmlwidgets)
}))

source("R/contour_bands.R"); source("R/access_categories.R")  # SSOT: F/G access constants (R/contour_bands.R, R/access_categories.R)
BAND <- PRIMARY_ACCESS_BAND_SEC
DISC    <- "Gynecologic Oncology"
FIGDIR  <- "manuscript/figures"
OUT     <- file.path(FIGDIR, "figure6_bivariate_go_access_INTERACTIVE.html")
dir.create(FIGDIR, showWarnings = FALSE, recursive = TRUE)

# 3x3 bivariate palette, keyed "<access><equity>" (matches the static figure).
bipal <- c("11"="#5a3a4a","12"="#8a4a5a","13"="#c33d5b",
           "21"="#4a6a7a","22"="#8a8a9a","23"="#d98a9a",
           "31"="#3a9a8a","32"="#8ac9b0","33"="#e8e0c0")
NODATA <- "#dcdcdc"

message("[1/5] geometry ...")
g0 <- readRDS("data/cache/tract_boundaries/tracts_y2020_cb0_51st_v1.rds")
gid <- intersect(c("GEOID","fips_tract"), names(g0))[1]
g0 <- g0[, gid]; names(g0)[1] <- "fips_tract"
g0$fips_tract <- as.character(g0$fips_tract)
# SSOT anchor (NON_CONUS_FIPS): canonical non-contiguous set in scripts/manuscript_e2sfca_values.R (complement of CONUS_STATE_FIPS); guarded by tests/testthat/test-ssot-nonconus-fips.R
g0 <- g0[!substr(g0$fips_tract, 1, 2) %in% c("02","15","60","66","69","72","78"), ]
# simplify in an equal-area CRS for clean topology, then back to WGS84 for leaflet
g0 <- st_transform(g0, 5070)
g0 <- st_simplify(g0, dTolerance = 700, preserveTopology = TRUE)

message("[2/5] access + minority share ...")
source("scripts/manuscript_catalog/_staging_guard.R")  # fail-loud if comparator inputs not staged
ds <- open_dataset("scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet")
cov <- as.data.table(ds %>%
  filter(range == BAND, category == DENOMINATOR_CATEGORY, subspecialty == DISC) %>%
  select(fips_tract, percent) %>% collect())
cov <- cov[is.finite(percent)]
cov[, fips_tract := as.character(fips_tract)]

race <- as.data.table(ds %>%
  filter(range == BAND, subspecialty == DISC) %>%
  select(fips_tract, category, total) %>% collect())
race[, fips_tract := as.character(fips_tract)]
rw <- dcast(race, fips_tract ~ category, value.var = "total",
            fun.aggregate = function(x) x[1])
setnames(rw, gsub("^total_female_?", "", names(rw)))
if ("" %in% names(rw)) setnames(rw, "", "fem")
minc <- intersect(c("black","hispanic","asian","aian","other","two_or_more"), names(rw))
rw[, minority := rowSums(.SD, na.rm = TRUE), .SDcols = minc]
rw[, minority_share := 100 * minority / fem]
rw <- rw[is.finite(minority_share) & fem > 0]

message("[3/5] bivariate classes (tertiles) ...")
mbr <- unique(quantile(rw$minority_share, c(0, 1/3, 2/3, 1), na.rm = TRUE))
rw[, ay := as.integer(cut(minority_share, breaks = mbr, include.lowest = TRUE,
                          labels = c(1, 2, 3)))]
biv <- merge(cov, rw[, .(fips_tract, ay, fem, minority, minority_share)],
             by = "fips_tract")
# access tertiles are the fixed 1/3-2/3 cut on percent, same as the static figure
biv[, ax := as.integer(cut(percent, breaks = c(-Inf, 100/3, 200/3, Inf),
                           labels = c(1, 2, 3)))]
biv[, bikey := paste0(ax, ay)]
acc_lab <- c("1" = "low (<33%)", "2" = "medium (33-67%)", "3" = "high (>67%)")
eq_lab  <- c("1" = "low", "2" = "medium", "3" = "high")
biv[, fill := bipal[bikey]]

message("[4/5] join to geometry + popups ...")
gb <- merge(g0, biv[, .(fips_tract, percent, minority_share, fem, minority,
                        ax, ay, bikey, fill)],
            by = "fips_tract", all.x = TRUE)
gb$fill[is.na(gb$fill)] <- NODATA
gb <- st_transform(gb, 4326)

has <- !is.na(gb$bikey)
st  <- substr(gb$fips_tract, 1, 2)
popup <- ifelse(
  has,
  sprintf(
    paste0("<b>Tract %s</b><br/>",
           "GO 60-min access: <b>%.1f%%</b> (%s)<br/>",
           "Minority female share: <b>%.1f%%</b> (%s)<br/>",
           "Female pop: %s &nbsp;|&nbsp; minority: %s<br/>",
           "<span style='color:#666'>Bivariate class %s</span>"),
    gb$fips_tract, gb$percent, acc_lab[as.character(gb$ax)],
    gb$minority_share, eq_lab[as.character(gb$ay)],
    format(round(gb$fem), big.mark = ","),
    format(round(gb$minority), big.mark = ","), gb$bikey),
  sprintf("<b>Tract %s</b><br/>No coverage data (Wyoming)", gb$fips_tract))

# 3x3 legend as an HTML control (access ->, minority-share ^)
legend_html <- sprintf("
<div style='background:white;padding:8px 10px;border-radius:6px;
  box-shadow:0 1px 4px rgba(0,0,0,.3);font:11px/1.3 sans-serif;'>
  <div style='font-weight:bold;margin-bottom:4px'>GO access &times; minority share</div>
  <table style='border-collapse:collapse'>
    <tr><td rowspan='3' style='writing-mode:vertical-rl;transform:rotate(180deg);
        font-size:10px;padding-right:2px'>Higher minority share &rarr;</td>
      <td style='width:18px;height:18px;background:%s'></td>
      <td style='width:18px;height:18px;background:%s'></td>
      <td style='width:18px;height:18px;background:%s'></td></tr>
    <tr><td style='background:%s'></td><td style='background:%s'></td><td style='background:%s'></td></tr>
    <tr><td style='background:%s'></td><td style='background:%s'></td><td style='background:%s'></td></tr>
    <tr><td></td><td colspan='3' style='font-size:10px;text-align:center'>Higher access &rarr;</td></tr>
  </table>
  <div style='margin-top:4px'><span style='display:inline-block;width:12px;height:12px;
    background:%s;vertical-align:middle'></span> no data</div>
</div>",
  bipal["13"], bipal["23"], bipal["33"],
  bipal["12"], bipal["22"], bipal["32"],
  bipal["11"], bipal["21"], bipal["31"], NODATA)

message("[5/5] leaflet ...")
m <- leaflet(gb, options = leafletOptions(preferCanvas = TRUE)) %>%
  addProviderTiles(providers$CartoDB.PositronNoLabels, group = "Light") %>%
  addProviderTiles(providers$CartoDB.DarkMatterNoLabels, group = "Dark") %>%
  setView(lng = -96, lat = 38.5, zoom = 4) %>%
  addPolygons(
    fillColor = ~fill, fillOpacity = 0.85, weight = 0.15,
    color = "#ffffff", opacity = 0.4,
    label = lapply(popup, htmltools::HTML),
    highlightOptions = highlightOptions(weight = 1.5, color = "#000",
                                        fillOpacity = 0.95, bringToFront = TRUE)) %>%
  addControl(html = htmltools::HTML(legend_html), position = "bottomright") %>%
  addControl(html = htmltools::HTML(
    "<div style='background:white;padding:6px 10px;border-radius:6px;
      box-shadow:0 1px 4px rgba(0,0,0,.3);font:13px sans-serif;max-width:340px'>
      <b>Gynecologic oncology: 60-min access &times; minority share (2023)</b><br/>
      <span style='font-size:11px;color:#555'>Each tract colored by both variables.
      Dark red = low access co-occurring with high minority share.
      Hover a tract for its numbers.</span></div>"),
    position = "topright") %>%
  addLayersControl(baseGroups = c("Light", "Dark"),
                   options = layersControlOptions(collapsed = TRUE))

saveWidget(m, file = normalizePath(OUT, mustWork = FALSE), selfcontained = TRUE,
           title = "GO access x minority share (interactive)")
cat(sprintf("DONE -> %s  (%d tracts, %d with data)\n",
            OUT, nrow(gb), sum(has)))
