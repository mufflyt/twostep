#!/usr/bin/env Rscript
# ============================================================================
# Interactive bivariate access map with a SUBSPECIALTY DROPDOWN (all 7).
#
# Bivariate choropleth of contiguous-US census tracts, switchable across all
# seven OB/GYN subspecialties from one <select> control:
#   X axis (access) = share of women reachable to the selected subspecialist
#                     within 60 min, tertiles (low <33 / med 33-67 / high >67)
#   Y axis (equity) = minority female population share, tertiles (a tract
#                     demographic -> CONSTANT across subspecialties)
#   fill            = 3x3 bivariate palette (dark red = low access AND high
#                     minority share). Grey = no coverage data for that subspec.
#
# Geometry is embedded ONCE as a GeoJSON layer; each feature carries a fill
# color + access % per subspecialty, so switching subspecialties only restyles
# (L.geoJSON.setStyle) instead of re-loading 83k polygons. Same tertile breaks
# and palette as build_bivariate_hotspot_map.R (static Figure 6) -> cannot drift.
#
# Output -> manuscript/figures/figure6_bivariate_access_INTERACTIVE_multi.html
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(data.table)
  library(sf); library(leaflet); library(htmlwidgets); library(htmltools)
  library(geojsonsf)
}))

source("R/contour_bands.R"); source("R/access_categories.R")  # SSOT: F/G access constants (R/contour_bands.R, R/access_categories.R)
BAND <- PRIMARY_ACCESS_BAND_SEC
FIGDIR <- "manuscript/figures"
OUT    <- file.path(FIGDIR, "figure6_bivariate_access_INTERACTIVE_multi.html")
dir.create(FIGDIR, showWarnings = FALSE, recursive = TRUE)

# short code -> parquet subspecialty label; codes drive property names + dropdown
SUBS <- c(
  GO   = "Gynecologic Oncology",
  MFM  = "Maternal-Fetal Medicine",
  REI  = "Reproductive Endocrinology & Infertility",
  URPS = "Female Pelvic Medicine & Reconstructive Surgery",
  MIGS = "Minimally Invasive Gynecologic Surgery",
  CFP  = "Complex Family Planning",
  PAG  = "Pediatric & Adolescent Gynecology")
DROPDOWN <- c(
  GO   = "Gynecologic Oncology",
  MFM  = "Maternal-Fetal Medicine",
  REI  = "Reproductive Endocrinology &amp; Infertility",
  URPS = "Urogynecology &amp; Reconstructive Pelvic Surgery",
  MIGS = "Minimally Invasive Gynecologic Surgery",
  CFP  = "Complex Family Planning",
  PAG  = "Pediatric &amp; Adolescent Gynecology")

bipal <- c("11"="#5a3a4a","12"="#8a4a5a","13"="#c33d5b",
           "21"="#4a6a7a","22"="#8a8a9a","23"="#d98a9a",
           "31"="#3a9a8a","32"="#8ac9b0","33"="#e8e0c0")
NODATA <- "#dcdcdc"

message("[1/6] geometry ...")
g0 <- readRDS("data/cache/tract_boundaries/tracts_y2020_cb0_51st_v1.rds")
gid <- intersect(c("GEOID","fips_tract"), names(g0))[1]
g0 <- g0[, gid]; names(g0)[1] <- "fips_tract"
g0$fips_tract <- as.character(g0$fips_tract)
# SSOT anchor (NON_CONUS_FIPS): canonical non-contiguous set in scripts/manuscript_e2sfca_values.R (complement of CONUS_STATE_FIPS); guarded by tests/testthat/test-ssot-nonconus-fips.R
g0 <- g0[!substr(g0$fips_tract, 1, 2) %in% c("02","15","60","66","69","72","78"), ]
g0 <- st_transform(g0, 5070)
# Light simplification only: 900 m erased the smallest (urban) tracts, leaving
# white holes where the basemap showed through. 300 m keeps dense-metro tracts
# intact while still shrinking the payload.
g0 <- st_simplify(g0, dTolerance = 300, preserveTopology = TRUE)
g0 <- st_make_valid(g0)
n_before <- nrow(g0)
g0 <- g0[!st_is_empty(g0), ]
if (nrow(g0) < n_before)
  message(sprintf("  dropped %d empty geoms after simplify", n_before - nrow(g0)))
g0 <- st_transform(g0, 4326)

message("[2/6] read access (all subspec) + minority share ...")
source("scripts/manuscript_catalog/_staging_guard.R")  # fail-loud if comparator inputs not staged
ds <- open_dataset("scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet")
cov <- as.data.table(ds %>%
  filter(range == BAND, category == DENOMINATOR_CATEGORY, subspecialty %in% unname(SUBS)) %>%
  select(fips_tract, subspecialty, percent) %>% collect())
cov <- cov[is.finite(percent)]
cov[, fips_tract := as.character(fips_tract)]
code_of <- setNames(names(SUBS), unname(SUBS))
cov[, code := code_of[subspecialty]]

# minority share is a tract demographic -> take it from GO's race breakdown once
race <- as.data.table(ds %>%
  filter(range == BAND, subspecialty == "Gynecologic Oncology") %>%
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
mbr <- unique(quantile(rw$minority_share, c(0, 1/3, 2/3, 1), na.rm = TRUE))
rw[, ay := as.integer(cut(minority_share, breaks = mbr, include.lowest = TRUE,
                          labels = c(1, 2, 3)))]

message("[3/6] bivariate class per subspecialty (wide) ...")
cov[, ax := as.integer(cut(percent, breaks = c(-Inf, 100/3, 200/3, Inf),
                           labels = c(1, 2, 3)))]
# wide: acc_<code> (access %) and ax_<code> (access tertile)
accw <- dcast(cov, fips_tract ~ code, value.var = "percent")
setnames(accw, setdiff(names(accw), "fips_tract"),
         paste0("acc_", setdiff(names(accw), "fips_tract")))
axw  <- dcast(cov, fips_tract ~ code, value.var = "ax")
setnames(axw, setdiff(names(axw), "fips_tract"),
         paste0("ax_", setdiff(names(axw), "fips_tract")))

props <- Reduce(function(a, b) merge(a, b, by = "fips_tract", all = TRUE),
                list(rw[, .(fips_tract, mshare = round(minority_share, 1),
                           fem = round(fem), minority = round(minority), ay)],
                     accw, axw))

# per-subspecialty fill hex (dark grey where that subspec has no access value)
for (k in names(SUBS)) {
  axk <- props[[paste0("ax_", k)]]
  bik <- ifelse(is.na(axk) | is.na(props$ay), NA_character_, paste0(axk, props$ay))
  props[[paste0("fill_", k)]] <- ifelse(is.na(bik), NODATA, bipal[bik])
  props[[paste0("acc_", k)]]  <- round(props[[paste0("acc_", k)]], 1)  # display precision
}

message("[4/6] attach props to geometry ...")
keepcols <- c("fips_tract", "mshare", "fem", "minority", "ay",
              paste0("acc_", names(SUBS)), paste0("fill_", names(SUBS)))
gb <- merge(g0, props[, ..keepcols], by = "fips_tract", all.x = TRUE)
# tracts absent from props: no data for any subspec
for (k in names(SUBS)) {
  fc <- paste0("fill_", k)
  gb[[fc]][is.na(gb[[fc]])] <- NODATA
}
gb$mshare[is.na(gb$mshare)]     <- -1        # sentinel -> "no data" in popup
gb$ay[is.na(gb$ay)]             <- 0

message("[5/6] geojson ...")
# 5 digits (~1 m) so coordinate rounding cannot collapse small tracts to invalid
# rings (which geojsonsf silently drops -> white holes). Verify feature retention.
gj <- geojsonsf::sf_geojson(gb, digits = 5)
n_emitted <- length(gregexpr('"fips_tract"', gj, fixed = TRUE)[[1]])
message(sprintf("  geojson features: %d of %d tracts (%.2f%%)",
                n_emitted, nrow(gb), 100 * n_emitted / nrow(gb)))
if (n_emitted < nrow(gb) * 0.999)
  stop(sprintf("geojson dropped %d tracts -> would render as white holes",
               nrow(gb) - n_emitted), call. = FALSE)

# ---- palette / legend / dropdown HTML built in R, wired to JS below ----
pal_js <- sprintf("{%s}", paste(sprintf('"%s":"%s"', names(bipal), bipal), collapse = ","))
opts   <- paste(sprintf('<option value="%s"%s>%s</option>',
                        names(DROPDOWN), ifelse(names(DROPDOWN) == "GO", " selected", ""),
                        unname(DROPDOWN)), collapse = "")

legend_html <- sprintf("
<div style='background:white;padding:8px 10px;border-radius:6px;
  box-shadow:0 1px 4px rgba(0,0,0,.3);font:11px/1.3 sans-serif;'>
  <div style='font-weight:bold;margin-bottom:4px'>Access &times; minority share</div>
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

control_html <- sprintf("
<div style='background:white;padding:8px 10px;border-radius:6px;
  box-shadow:0 1px 4px rgba(0,0,0,.3);font:13px sans-serif;max-width:360px'>
  <b>60-min access &times; minority share (2023)</b><br/>
  <label style='font-size:12px'>Subspecialty:
    <select id='subspec-select' style='font-size:12px;margin-top:3px'>%s</select>
  </label><br/>
  <span id='subspec-note' style='font-size:11px;color:#555'>Dark red = low access
  co-occurring with high minority share. Hover a tract for its numbers.</span>
</div>", opts)

message("[6/6] leaflet + JS restyle ...")
m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) %>%
  addProviderTiles(providers$CartoDB.PositronNoLabels, group = "Light") %>%
  addProviderTiles(providers$CartoDB.DarkMatterNoLabels, group = "Dark") %>%
  setView(lng = -96, lat = 38.5, zoom = 4) %>%
  addControl(html = HTML(control_html), position = "topright") %>%
  addControl(html = HTML(legend_html), position = "bottomright") %>%
  addLayersControl(baseGroups = c("Light", "Dark"),
                   options = layersControlOptions(collapsed = TRUE))

# inject the GeoJSON + interaction as an onRender JS closure
js <- sprintf("
function(el, x) {
  var map = this;
  var DATA = %s;
  var SUBS = %s;               // ['GO','MFM',...]
  var LABEL = %s;              // {GO:'Gynecologic Oncology',...}
  var ACC = {1:'low (<33%%)',2:'medium (33-67%%)',3:'high (>67%%)'};
  var EQ  = {0:'no data',1:'low',2:'medium',3:'high'};
  var sel = 'GO';

  function styleFor(f){ return {fillColor: f.properties['fill_'+sel], weight:0.15,
      color:'#fff', opacity:0.4, fillOpacity:0.85}; }

  function popupHtml(p){
    var acc = p['acc_'+sel];
    var axcode = p['ax_'+sel];
    if (acc === null || acc === undefined) {
      return '<b>Tract '+p.fips_tract+'</b><br/>No coverage data for '+LABEL[sel];
    }
    var eqTxt = (p.mshare < 0) ? 'no data' : (p.mshare.toFixed(1)+'%% ('+EQ[p.ay]+')');
    return '<b>Tract '+p.fips_tract+'</b><br/>'+
      LABEL[sel]+' 60-min access: <b>'+acc.toFixed(1)+'%%</b><br/>'+
      'Minority female share: <b>'+eqTxt+'</b><br/>'+
      'Female pop: '+(p.fem>=0?p.fem.toLocaleString():'NA')+
      ' &nbsp;|&nbsp; minority: '+(p.minority>=0?p.minority.toLocaleString():'NA');
  }

  var layer = L.geoJSON(DATA, {
    style: styleFor,
    onEachFeature: function(f, lyr){
      lyr.on({
        mouseover: function(e){
          e.target.setStyle({weight:1.5, color:'#000', fillOpacity:0.95});
          if (e.target.bringToFront) e.target.bringToFront();
          e.target.bindTooltip(popupHtml(f.properties), {sticky:true}).openTooltip(e.latlng);
        },
        mouseout: function(e){ layer.resetStyle(e.target); e.target.closeTooltip(); },
        click: function(e){ e.target.bindPopup(popupHtml(f.properties)).openPopup(e.latlng); }
      });
    }
  }).addTo(map);

  // dropdown wiring (the <select> lives inside an addControl panel)
  function wire(){
    var s = document.getElementById('subspec-select');
    if (!s){ setTimeout(wire, 120); return; }
    s.addEventListener('change', function(){
      sel = s.value;
      layer.setStyle(styleFor);   // one call restyles all features
    });
  }
  wire();
}", gj, jsonlite::toJSON(names(SUBS)),
    jsonlite::toJSON(as.list(setNames(gsub("&amp;","&",DROPDOWN), names(DROPDOWN))),
                     auto_unbox = TRUE))

m <- htmlwidgets::onRender(m, js)

saveWidget(m, file = normalizePath(OUT, mustWork = FALSE), selfcontained = TRUE,
           title = "Bivariate access x minority share (all subspecialties)")
cat(sprintf("DONE -> %s  (%d tracts, %d subspecialties)\n",
            OUT, nrow(gb), length(SUBS)))
