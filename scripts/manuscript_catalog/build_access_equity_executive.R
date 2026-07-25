#!/usr/bin/env Rscript
# ============================================================================
# Executive access-equity map (interactive) for the seven OB/GYN subspecialties.
#
# An access-disparity exhibit built on the bivariate idea but re-weighted so the
# PRIORITY finding -- low driving access co-occurring with a high minority
# population share -- reads immediately:
#   * colorblind-safe 3x3 palette; only the priority corner is a strong red
#   * "Explore all tracts" vs "Show priority areas" modes
#   * large, directly-labeled, clickable 3x3 legend
#   * scale-dependent tract borders (hidden at national zoom)
#   * meaning-first popups (county name, priority category, national access
#     percentile, plain-language reason for the color)
#   * hover tooltip vs click-locked popup
#   * population-impact summary cards (women affected), per specialty+threshold
#   * subspecialty dropdown + 30/60/120/180-minute threshold toggle (2023)
#   * state outlines + zoom-to-state; equity-forward wording; distinct no-data
#
# Deferred (need extra inputs/services): year slider, provider markers,
# geocoder search, nearest-service minutes, inset locator.
#
# Same tertile logic + inputs as build_bivariate_hotspot_map.R so map values
# cannot drift from static Figure 6.
# Output -> manuscript/figures/figure6_access_equity_EXECUTIVE.html
# ============================================================================
suppressWarnings(suppressMessages({
  library(arrow); library(dplyr); library(data.table)
  library(sf); library(leaflet); library(htmlwidgets); library(htmltools)
  library(geojsonsf); library(jsonlite); library(tidycensus)
}))

FIGDIR <- "manuscript/figures"
OUT    <- file.path(FIGDIR, "figure6_access_equity_EXECUTIVE.html")
dir.create(FIGDIR, showWarnings = FALSE, recursive = TRUE)

BANDS <- c("30" = 1800L, "60" = 3600L, "120" = 7200L, "180" = 10800L)
SUBS <- c(
  GO   = "Gynecologic Oncology",
  MFM  = "Maternal-Fetal Medicine",
  REI  = "Reproductive Endocrinology & Infertility",
  URPS = "Female Pelvic Medicine & Reconstructive Surgery",
  MIGS = "Minimally Invasive Gynecologic Surgery",
  CFP  = "Complex Family Planning",
  PAG  = "Pediatric & Adolescent Gynecology")
SHORT <- c(GO = "Gynecologic oncology", MFM = "Maternal-fetal medicine",
           REI = "Reproductive endocrinology", URPS = "Urogynecology",
           MIGS = "Minimally invasive gyn surgery", CFP = "Complex family planning",
           PAG = "Pediatric & adolescent gynecology")
FULL <- c(GO = "Gynecologic Oncology", MFM = "Maternal-Fetal Medicine",
          REI = "Reproductive Endocrinology and Infertility",
          URPS = "Urogynecology and Reconstructive Pelvic Surgery (FPMRS)",
          MIGS = "Minimally Invasive Gynecologic Surgery",
          CFP = "Complex Family Planning",
          PAG = "Pediatric and Adolescent Gynecology")

# colorblind-safe: access low->high is red->grey->blue; minority share raises
# intensity. Only the low-access/high-minority corner ("13") is strong red.
BIPAL <- c(
  "11" = "#f4cccc", "21" = "#dedede", "31" = "#cfe0ee",
  "12" = "#e08e8e", "22" = "#bfbfbf", "32" = "#8fb4d6",
  "13" = "#a50f15", "23" = "#8f8f8f", "33" = "#5a8fbf")
NODATA <- "#eaeaea"
PRIORITY <- "13"

message("[1/8] geometry ...")
source("R/guard_simplified_map.R")
source("R/access_categories.R")  # SSOT: DENOMINATOR_CATEGORY
source("R/contour_bands.R")  # SSOT: PRIMARY_ACCESS_BAND_SEC
dir.create("manuscript/stats", showWarnings = FALSE, recursive = TRUE)
ALLOW_FALLBACK <- identical(Sys.getenv("ALLOW_SIMPLIFY_FALLBACK", "0"), "1")
KEEP <- as.numeric(Sys.getenv("SIMPLIFY_KEEP", "0.15"))

g0 <- readRDS("data/cache/tract_boundaries/tracts_y2020_cb0_51st_v1.rds")
gid <- intersect(c("GEOID","fips_tract"), names(g0))[1]
g0 <- g0[, gid]; names(g0)[1] <- "fips_tract"
g0$fips_tract <- as.character(g0$fips_tract)
# SSOT anchor (NON_CONUS_FIPS): canonical non-contiguous set in scripts/manuscript_e2sfca_values.R (complement of CONUS_STATE_FIPS); guarded by tests/testthat/test-ssot-nonconus-fips.R
g0 <- g0[!substr(g0$fips_tract, 1, 2) %in% c("02","15","60","66","69","72","78"), ]
g0 <- st_transform(g0, 4326)
g0$stfips <- substr(g0$fips_tract, 1, 2)
g_src <- g0                        # full-resolution source retained for the guards

# Topology-aware simplification (Visvalingam) instead of st_simplify: Douglas-
# Peucker self-intersects on complex tract rings and renders as diagonal "spike"
# needles. ms_simplify preserves shared borders (no spikes, no gaps) and
# keep_shapes=TRUE keeps every tract (no white holes). BUT ms_simplify loads the
# whole layer's topology into V8 and OOMs on all 83k at once, so run it PER STATE
# (~1-2k tracts each) and stitch back. Any per-state fallback is LEDGERED and
# fails the build unless ALLOW_SIMPLIFY_FALLBACK=1 (no silent mixed-algorithm map).
message("  simplifying per state (topology-aware, chunked, hard-guarded) ...")
.ledger <- list()
parts <- lapply(split(seq_len(nrow(g0)), g0$stfips), function(ix) {
  sub <- g0[ix, ]; st <- sub$stfips[1]
  tryCatch({
    o <- rmapshaper::ms_simplify(sub, keep = KEEP, keep_shapes = TRUE, explode = FALSE)
    o$.simplify_method <- "ms_simplify"; o
  }, error = function(e) {
    .ledger[[st]] <<- list(state = st, method = "st_simplify",
                           n_in = nrow(sub), error = conditionMessage(e))
    message("   ms_simplify fallback -> st_simplify for state ", st)
    s <- st_transform(sub, 5070); s <- st_simplify(s, 200, TRUE); s <- st_transform(s, 4326)
    s$.simplify_method <- "st_simplify"; s
  })
})
g0 <- do.call(rbind, parts)
g0 <- st_make_valid(g0)
g0 <- g0[!st_is_empty(g0), ]

# ---- fail-closed on any silent fallback ----
if (length(.ledger)) {
  led <- rbindlist(lapply(.ledger, function(x) data.table(
    state = x$state, method = x$method, n_in = x$n_in,
    error = substr(x$error, 1, 300))), fill = TRUE)
  fwrite(led, "manuscript/stats/simplify_fallback_ledger.csv")
  message("  FALLBACK used for ", nrow(led), " state(s):"); print(led)
  if (!ALLOW_FALLBACK)
    stop("Per-state simplification fell back to st_simplify (see ",
         "manuscript/stats/simplify_fallback_ledger.csv). Set ALLOW_SIMPLIFY_FALLBACK=1 ",
         "only after reviewing the mixed-algorithm map.", call. = FALSE)
}

# ---- HARD GUARDS: per-state distortion + interstate seam ----
# compute the (expensive) full-resolution source unions ONCE, reuse in both guards
message("  precomputing source per-state unions (5070) ...")
.src5 <- st_transform(g_src, 5070)
.src_unions <- lapply(split(seq_len(nrow(.src5)), as.character(.src5$stfips)),
                      function(ix) st_make_valid(st_union(.src5[ix, ])))
.src_nat <- st_make_valid(st_union(do.call(c, .src_unions)))
guard <- guard_simplified_map(g_src, g0, state_col = "stfips", id_col = "fips_tract",
                              allow_fallback = ALLOW_FALLBACK, src_unions = .src_unions)
g0 <- guard$geometry
fwrite(guard$audit, "manuscript/stats/simplify_state_audit.csv")
seam <- audit_interstate_seams(g_src, g0, state_col = "stfips", src_nat = .src_nat)
fwrite(seam$metrics, "manuscript/stats/simplify_seam_audit.csv")
rm(.src5); gc()

# ---- determinism fingerprint: sha256 of sorted WKB (compare across builds) ----
.wkb <- sf::st_as_binary(sf::st_geometry(g0[order(g0$fips_tract), ]))
.wkbhash <- digest::digest(.wkb, algo = "sha256")
writeLines(.wkbhash, "manuscript/stats/simplify_geometry_sha256.txt")
message("  geometry SHA256 (sorted WKB): ", .wkbhash)

# ---- visual smoke test: national + region crops for eyeball review ----
tryCatch({
  qa <- "manuscript/figures/qa"; dir.create(qa, showWarnings = FALSE, recursive = TRUE)
  gm <- sf::st_geometry(g0)
  cc <- suppressWarnings(sf::st_coordinates(sf::st_centroid(gm)))
  inbox <- function(b) which(cc[,1] >= b[1] & cc[,1] <= b[2] & cc[,2] >= b[3] & cc[,2] <= b[4])
  crops <- list(Northeast = c(-80,-67,39,45.5), Florida = c(-88,-79.5,24.5,31.5),
                `TX-LA coast` = c(-98,-89,28,31.5), `WA-ID` = c(-125,-114,45.5,49.2),
                `Chicago-Detroit` = c(-89,-82,41,43.6))
  grDevices::png(file.path(qa, "simplify_smoke.png"), width = 1900, height = 1200)
  op <- graphics::par(mfrow = c(2,3), mar = c(1,1,2.4,1))
  plot(gm, col = "grey86", border = "grey55", lwd = 0.1, main = "National (simplified tracts)")
  for (nm in names(crops)) { b <- crops[[nm]]
    plot(gm[inbox(b)], col = "grey86", border = "grey45", lwd = 0.35,
         xlim = b[1:2], ylim = b[3:4], main = nm) }
  graphics::par(op); grDevices::dev.off()
  message("  QA smoke render -> ", file.path(qa, "simplify_smoke.png"))
}, error = function(e) message("  QA render skipped: ", conditionMessage(e)))

rm(g_src); gc()

message("[2/8] state outlines + per-state bounds ...")
STAB <- { f <- tidycensus::fips_codes
          setNames(f$state[!duplicated(f$state_code)], f$state_code[!duplicated(f$state_code)]) }
g0$stfips <- substr(g0$fips_tract, 1, 2)
# per-state bounding boxes for the zoom-to-state control
STBOUNDS <- list()
for (sc in sort(unique(g0$stfips))) {
  bb <- st_bbox(g0[g0$stfips == sc, ])
  STBOUNDS[[ STAB[[sc]] ]] <- c(south = unname(bb["ymin"]), west = unname(bb["xmin"]),
                                north = unname(bb["ymax"]), east = unname(bb["xmax"]))
}
states_gj <- tryCatch({
  gd <- rmapshaper::ms_dissolve(g0[, "stfips"], field = "stfips")
  gd <- rmapshaper::ms_simplify(gd, keep = 0.02, keep_shapes = TRUE)
  geojsonsf::sf_geojson(gd, digits = 4)
}, error = function(e) { message("  state dissolve skipped: ", conditionMessage(e)); "null" })

message("[3/8] access, all subspecialty x band (2023) ...")
source("scripts/manuscript_catalog/_staging_guard.R")  # fail-loud if comparator inputs not staged
ds <- open_dataset("scratchpad/seam_tracts/step_4_access_by_tract_with_ruca_y2023.parquet")
cov <- as.data.table(ds %>%
  filter(range %in% unname(BANDS), category == DENOMINATOR_CATEGORY,
         subspecialty %in% unname(SUBS)) %>%
  select(fips_tract, subspecialty, range, percent) %>% collect())
cov[, fips_tract := as.character(fips_tract)]
cov <- cov[is.finite(percent)]
code_of <- setNames(names(SUBS), unname(SUBS))
band_of <- setNames(names(BANDS), as.character(unname(BANDS)))
cov[, code := code_of[subspecialty]]
cov[, bandk := band_of[as.character(range)]]
cov[, combo := paste0(code, "_", bandk)]

# fixed combo order: subspecialty (outer) x band (inner)
COMBOS <- as.vector(t(outer(names(SUBS), names(BANDS), paste, sep = "_")))
cov[, combo := factor(combo, levels = COMBOS)]

message("[4/8] 2023 demographics + minority tertile ...")
race <- as.data.table(ds %>%
  filter(range == PRIMARY_ACCESS_BAND_SEC, subspecialty == "Gynecologic Oncology") %>%
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

message("[5/8] per-tract access array + county names ...")
accw <- dcast(cov, fips_tract ~ combo, value.var = "percent", drop = FALSE)
for (cc in COMBOS) if (!cc %in% names(accw)) accw[[cc]] <- NA_real_
setcolorder(accw, c("fips_tract", COMBOS))
# order arrays exactly as COMBOS; -1 sentinel = no data
acc_mat <- as.matrix(accw[, ..COMBOS]); acc_mat[!is.finite(acc_mat)] <- -1
acc_mat <- round(acc_mat, 1)
# store the 28-value access vector as a comma-joined STRING (geojsonsf cannot
# serialize a list-column; JS splits it back to an array once per feature)
accw_arr <- data.table(fips_tract = accw$fips_tract,
                       ac = apply(acc_mat, 1, function(v) paste(v, collapse = ",")))

tract <- merge(rw[, .(fips_tract, fem = round(fem), minority = round(minority),
                      msh = round(minority_share, 1), ay)],
               accw_arr, by = "fips_tract", all = TRUE)

# county "County, ST" names (fips_codes), keyed by 5-digit county fips
fp <- as.data.table(tidycensus::fips_codes)
fp[, fips5 := paste0(state_code, county_code)]
CTY <- setNames(sprintf("%s, %s", fp$county, fp$state), fp$fips5)
present5 <- unique(substr(tract$fips_tract, 1, 5))
CTY <- as.list(CTY[intersect(names(CTY), present5)])

message("[6/8] national access percentiles + population summaries ...")
# per combo: 101-point quantile array (for popup percentile), and summary stats
QTL <- vector("list", length(COMBOS)); names(QTL) <- COMBOS
SUMMARY <- data.table(combo = COMBOS, womenLow = 0, womenPriority = 0,
                      pctMinLow = 0, nPriority = 0L, nPriorityCty = 0L)
ay_by <- setNames(rw$ay, rw$fips_tract)
fem_by <- setNames(rw$fem, rw$fips_tract); min_by <- setNames(rw$minority, rw$fips_tract)
for (i in seq_along(COMBOS)) {
  cc <- COMBOS[i]
  d <- cov[combo == cc & is.finite(percent)]
  QTL[[cc]] <- if (nrow(d)) round(as.numeric(quantile(d$percent, probs = seq(0, 1, 0.01),
                                                      na.rm = TRUE)), 2) else rep(0, 101)
  d[, ay := ay_by[fips_tract]]; d[, fem := fem_by[fips_tract]]; d[, minority := min_by[fips_tract]]
  d <- d[is.finite(fem) & fem > 0]
  d[, ax := as.integer(cut(percent, c(-Inf, 100/3, 200/3, Inf), labels = c(1,2,3)))]
  low  <- d[ax == 1]; prio <- d[ax == 1 & ay == 3]
  set(SUMMARY, i, "womenLow",     sum(low$fem, na.rm = TRUE))
  set(SUMMARY, i, "womenPriority",sum(prio$fem, na.rm = TRUE))
  set(SUMMARY, i, "pctMinLow", if (sum(d$minority,na.rm=TRUE)>0)
        round(100*sum(low$minority,na.rm=TRUE)/sum(d$minority,na.rm=TRUE),1) else 0)
  set(SUMMARY, i, "nPriority",    nrow(prio))
  set(SUMMARY, i, "nPriorityCty", length(unique(substr(prio$fips_tract,1,5))))
}
SUMMARY[, combo := NULL]

message("[7/8] geojson ...")
gb <- merge(g0[, c("fips_tract")], tract, by = "fips_tract", all.x = TRUE)
gb$ay[is.na(gb$ay)]   <- 0L
gb$fem[is.na(gb$fem)] <- -1L; gb$minority[is.na(gb$minority)] <- -1L
gb$msh[is.na(gb$msh)] <- -1
gb$cty <- substr(gb$fips_tract, 1, 5)
# tracts with no access row -> all-(-1) string
naidx <- is.na(gb$ac)
if (any(naidx)) gb$ac[naidx] <- paste(rep(-1, length(COMBOS)), collapse = ",")
gb <- gb[, c("fips_tract","cty","ay","fem","minority","msh","ac")]
names(gb)[names(gb) == "fips_tract"] <- "f"
gj <- geojsonsf::sf_geojson(gb, digits = 5)
n_emit <- length(gregexpr('"f":', gj, fixed = TRUE)[[1]])
message(sprintf("  geojson features: %d of %d (%.2f%%)", n_emit, nrow(gb),
                100 * n_emit / nrow(gb)))
if (n_emit < nrow(gb) * 0.999) stop("geojson dropped tracts -> white holes", call. = FALSE)

message("[8/8] leaflet + JS ...")
# --- static control skeletons (JS fills dynamic bits; no % chars in R strings) ---
opts_sub  <- paste(sprintf('<option value="%s"%s>%s</option>', names(SHORT),
                           ifelse(names(SHORT)=="URPS"," selected",""), unname(SHORT)),
                   collapse = "")
opts_band <- paste(sprintf('<option value="%s"%s>%s minutes</option>', names(BANDS),
                           ifelse(names(BANDS)=="60"," selected",""), names(BANDS)),
                   collapse = "")
opts_state <- paste0('<option value="">Zoom to state...</option>',
                     paste(sprintf('<option value="%s">%s</option>',
                                   names(STBOUNDS), names(STBOUNDS)), collapse=""))

panel_html <- sprintf("
<div style='background:#fff;padding:11px 13px;border-radius:8px;max-width:340px;
  box-shadow:0 1px 6px rgba(0,0,0,.25);font:13px/1.35 -apple-system,sans-serif'>
  <div id='t-title' style='font-weight:700;font-size:15px;color:#222'></div>
  <div id='t-sub' style='font-size:11.5px;color:#666;margin:2px 0 8px'></div>
  <div style='display:flex;gap:6px;margin-bottom:6px'>
    <button id='mode-explore' class='modebtn'>Explore all tracts</button>
    <button id='mode-priority' class='modebtn'>Show priority areas</button>
  </div>
  <label style='font-size:12px;color:#333'>Subspecialty
    <select id='sel-sub' style='width:100%%;margin-top:2px'>%s</select></label>
  <label style='font-size:12px;color:#333;display:block;margin-top:5px'>Driving threshold
    <select id='sel-band' style='width:100%%;margin-top:2px'>%s</select></label>
  <div id='t-settings' style='font-size:11px;color:#555;margin-top:7px'></div>
  <div style='display:flex;gap:6px;margin-top:8px;align-items:center'>
    <select id='sel-state' style='font-size:11px;flex:1'>%s</select>
    <button id='btn-reset' style='font-size:11px'>Reset</button>
    <button id='btn-about' style='font-size:11px'>&#9432; About</button>
  </div>
  <div id='about' style='display:none;font-size:11px;color:#444;margin-top:8px;
    border-top:1px solid #eee;padding-top:6px'></div>
</div>", opts_sub, opts_band, opts_state)

# large, labeled, clickable 3x3 legend
cellstyle <- "width:74px;height:34px;cursor:pointer;color:#fff;font:9px/1.05 sans-serif;
  text-align:center;vertical-align:middle;border:2px solid #fff;padding:1px"
legend_html <- sprintf("
<div style='background:#fff;padding:9px 11px;border-radius:8px;
  box-shadow:0 1px 6px rgba(0,0,0,.25);font:11px sans-serif'>
  <div style='font-weight:700;margin-bottom:5px'>Access and population equity</div>
  <table style='border-collapse:collapse'>
    <tr><td></td>
      <td style='font-size:9px;text-align:center;color:#555'>Lower access</td>
      <td style='font-size:9px;text-align:center;color:#555'>Medium</td>
      <td style='font-size:9px;text-align:center;color:#555'>Higher access</td></tr>
    <tr><td style='font-size:9px;color:#555;text-align:right;padding-right:3px'>Higher<br>minority</td>
      <td class='lgc' data-k='13' style='%s;background:%s'><b>Highest priority</b></td>
      <td class='lgc' data-k='23' style='%s;background:%s;color:#222'>Disparity concern</td>
      <td class='lgc' data-k='33' style='%s;background:%s'>Better access</td></tr>
    <tr><td style='font-size:9px;color:#555;text-align:right;padding-right:3px'>Medium</td>
      <td class='lgc' data-k='12' style='%s;background:%s;color:#222'>Access concern</td>
      <td class='lgc' data-k='22' style='%s;background:%s;color:#222'>Middle</td>
      <td class='lgc' data-k='32' style='%s;background:%s;color:#222'>Better access</td></tr>
    <tr><td style='font-size:9px;color:#555;text-align:right;padding-right:3px'>Lower<br>minority</td>
      <td class='lgc' data-k='11' style='%s;background:%s;color:#222'>Access concern</td>
      <td class='lgc' data-k='21' style='%s;background:%s;color:#222'>Lower concern</td>
      <td class='lgc' data-k='31' style='%s;background:%s;color:#222'>Lowest concern</td></tr>
  </table>
  <div style='margin-top:6px;font-size:10px;color:#555'>
    <b style='color:#a50f15'>Highest priority</b> = low access with high minority share.
    Click a cell to isolate it.<br>
    <span style='display:inline-block;width:12px;height:12px;background:%s;
      border:1px dashed #999;vertical-align:middle'></span> no coverage data (e.g. Wyoming)
  </div>
</div>",
  cellstyle, BIPAL["13"], cellstyle, BIPAL["23"], cellstyle, BIPAL["33"],
  cellstyle, BIPAL["12"], cellstyle, BIPAL["22"], cellstyle, BIPAL["32"],
  cellstyle, BIPAL["11"], cellstyle, BIPAL["21"], cellstyle, BIPAL["31"], NODATA)

summary_html <- "
<div id='summary' style='background:#fff;padding:9px 12px;border-radius:8px;
  box-shadow:0 1px 6px rgba(0,0,0,.25);font:12px -apple-system,sans-serif;max-width:250px'></div>"

css <- HTML("<style>
.modebtn{flex:1;font-size:11px;padding:5px 4px;border:1px solid #bbb;border-radius:5px;
  background:#f4f4f4;cursor:pointer}
.modebtn.on{background:#a50f15;color:#fff;border-color:#a50f15;font-weight:600}
#summary .big{font-size:20px;font-weight:800;color:#a50f15;line-height:1.1}
#summary .card{border-top:1px solid #eee;padding:4px 0;font-size:11.5px;color:#333}
#summary .card b{font-size:14px;color:#111}
.leaflet-tooltip.eq{font:12px sans-serif;padding:3px 6px}
</style>")

m <- leaflet(options = leafletOptions(preferCanvas = TRUE)) %>%
  addProviderTiles(providers$CartoDB.PositronNoLabels, group = "Light") %>%
  addProviderTiles(providers$CartoDB.DarkMatterNoLabels, group = "Dark") %>%
  setView(-96, 38.5, 4) %>%
  addControl(css, position = "topleft") %>%
  addControl(HTML(panel_html), position = "topright") %>%
  addControl(HTML(summary_html), position = "topleft") %>%
  addControl(HTML(legend_html), position = "bottomright") %>%
  addLayersControl(baseGroups = c("Light","Dark"),
                   options = layersControlOptions(collapsed = TRUE))

# ---- inject data (plain JSON, avoids sprintf % pitfalls) ----
about_txt <- paste0(
  "Each census tract is shaded by two things at once: how many local women can ",
  "reach the selected subspecialist within the chosen driving time (2023), and ",
  "the tract's minority share of female population (a tract demographic, so it ",
  "does not change between subspecialties). Access is split into thirds (low ",
  "under 33 percent, medium, high over 67 percent); minority share into thirds. ",
  "The concern flagged is inequitable access affecting minority populations, not ",
  "minority composition itself. Study area is the contiguous United States; ",
  "Alaska, Hawaii, and territories are outside scope. Grey with a dashed edge = ",
  "no coverage data. Full subspecialty terms: ",
  paste(sprintf("%s = %s", names(FULL), unname(FULL)), collapse = "; "), ".")

data_js <- paste0(
  "var DATA=", gj, ";\n",
  "var STATES=", states_gj, ";\n",
  "var CTY=", toJSON(CTY, auto_unbox = TRUE), ";\n",
  "var QTL=", toJSON(unname(QTL)), ";\n",
  "var SUMMARY=", toJSON(SUMMARY, dataframe = "rows"), ";\n",
  "var STBOUNDS=", toJSON(STBOUNDS, auto_unbox = TRUE), ";\n",
  "var SUBS=", toJSON(names(SUBS)), ";\n",
  "var BANDKEYS=", toJSON(names(BANDS)), ";\n",
  "var COMBOS=", toJSON(COMBOS), ";\n",
  "var SHORT=", toJSON(as.list(SHORT), auto_unbox = TRUE), ";\n",
  "var BIPAL=", toJSON(as.list(BIPAL), auto_unbox = TRUE), ";\n",
  "var NODATA=", toJSON(NODATA, auto_unbox = TRUE), ";\n",
  "var ABOUT=", toJSON(about_txt, auto_unbox = TRUE), ";\n")

js_body <- "
  var map = this;
  var selSub='URPS', selBand='60', mode='explore', catFilter=null;
  var CLS={'13':'Highest priority','23':'Disparity concern','33':'Better access',
    '12':'Access concern','22':'Middle','32':'Better access',
    '11':'Access concern','21':'Lower concern','31':'Lowest concern'};
  var AYW={1:'lower',2:'middle',3:'higher'};
  function comboIdx(){ return COMBOS.indexOf(selSub+'_'+selBand); }
  function acArr(p){ if(!p._ac) p._ac=p.ac.split(',').map(Number); return p._ac; }
  function axOf(ac){ if(ac<0) return 0; if(ac<100/3) return 1; if(ac<200/3) return 2; return 3; }
  function classOf(p){ var ac=acArr(p)[comboIdx()]; var ax=axOf(ac); if(ax===0||!p.ay) return null; return ''+ax+p.ay; }
  function bw(){ var z=map.getZoom(); return z<5?0:(z<7?0.12:(z<9?0.4:0.8)); }
  function pct(ac){ var q=QTL[comboIdx()]; if(!q||ac<0) return null; var lo=0; for(var i=0;i<q.length;i++){ if(q[i]<=ac) lo=i; else break;} return lo; }

  function styleFor(f){
    var p=f.properties, cls=classOf(p), w=bw();
    if(cls===null) return {fillColor:NODATA,fillOpacity:mode==='priority'?0.18:0.5,
      weight:Math.max(w,0.15),color:'#b0b0b0',opacity:0.5,dashArray:'2,3'};
    var isP=(cls==='13');
    var vis=(mode==='priority')?isP:(catFilter?cls===catFilter:true);
    if(!vis) return {fillColor:'#ededed',fillOpacity:0.3,weight:0,color:'#ededed',opacity:0.2};
    return {fillColor:BIPAL[cls],fillOpacity:isP?0.92:0.8,
      weight:isP?Math.max(w,0.5):w,color:isP?'#4a0d1f':'#ffffff',opacity:isP?0.9:0.35,dashArray:null};
  }

  function county(p){ return CTY[p.cty]||('FIPS '+p.cty); }
  function tip(p){ var cls=classOf(p); var ac=acArr(p)[comboIdx()];
    return '<b>'+county(p)+'</b><br>'+(cls?CLS[cls]:'No data')+
      (ac>=0?(' &middot; access '+ac.toFixed(1)+'%'):''); }
  function popup(p){
    var cls=classOf(p), idx=comboIdx(), ac=acArr(p)[idx];
    if(cls===null) return '<div style=\"font:12px sans-serif\"><b>'+county(p)+
      '</b><br>No coverage data for '+SHORT[selSub]+'<br><span style=\"color:#999;font-size:10px\">Census tract: '+p.f+'</span></div>';
    var pc=pct(ac); var col=BIPAL[cls];
    var why='Shown in this color because access is '+(axOf(ac)===1?'low':(axOf(ac)===2?'medium':'high'))+
      ' and minority share is in the '+AYW[p.ay]+' third.';
    return '<div style=\"font:12px/1.4 sans-serif;max-width:230px\">'+
      '<b>'+county(p)+'</b><br>'+
      '<span style=\"font-weight:700;color:'+col+'\">'+CLS[cls]+'</span> category'+
      '<div style=\"margin-top:5px\">'+
      'Women within '+selBand+' min of care: <b>'+ac.toFixed(1)+'%</b><br>'+
      'Minority share: <b>'+(p.msh>=0?p.msh.toFixed(1)+'%':'NA')+'</b> ('+AYW[p.ay]+' third)<br>'+
      'Female population: '+(p.fem>=0?p.fem.toLocaleString():'NA')+'<br>'+
      'Minority female population: '+(p.minority>=0?p.minority.toLocaleString():'NA')+'<br>'+
      (pc!==null?'National access percentile: <b>'+pc+'th</b><br>':'')+
      '</div><div style=\"margin-top:5px;color:#555;font-size:11px\">'+why+'</div>'+
      '<div style=\"margin-top:4px;color:#999;font-size:10px\">Census tract: '+p.f+'</div></div>';
  }

  var layer=L.geoJSON(DATA,{style:styleFor,onEachFeature:function(f,ly){
    ly.on({
      mouseover:function(e){ e.target.setStyle({weight:Math.max(bw(),1.4),color:'#111',fillOpacity:0.97});
        if(e.target.bringToFront)e.target.bringToFront();
        e.target.bindTooltip(tip(f.properties),{sticky:true,className:'eq'}).openTooltip(e.latlng); },
      mouseout:function(e){ layer.resetStyle(e.target); e.target.closeTooltip(); },
      click:function(e){ e.target.bindPopup(popup(f.properties)).openPopup(e.latlng); }
    });
  }}).addTo(map);

  if(STATES){ L.geoJSON(STATES,{fill:false,color:'#555',weight:1,opacity:0.6,
    interactive:false}).addTo(map); }

  function fmtM(n){ return n>=1e6?(n/1e6).toFixed(1)+' million':(n>=1e3?Math.round(n/1e3)+'k':(''+n)); }
  function refresh(){
    layer.setStyle(styleFor);
    document.getElementById('t-title').innerHTML='Geographic inequities in '+SHORT[selSub].toLowerCase()+' access';
    document.getElementById('t-sub').innerHTML='Women within '+selBand+' minutes\\u2019 driving time of care, by census tract, 2023';
    document.getElementById('t-settings').innerHTML='Specialty: <b>'+SHORT[selSub]+
      '</b> &middot; Threshold: <b>'+selBand+' min</b> &middot; Year: <b>2023</b>';
    var s=SUMMARY[comboIdx()];
    document.getElementById('summary').innerHTML=
      '<div class=\"big\">'+fmtM(s.womenPriority)+' women</div>'+
      '<div style=\"font-size:11px;color:#555;margin-bottom:4px\">live in highest-priority tracts (low access, high minority share)</div>'+
      '<div class=\"card\">Women in low-access tracts: <b>'+fmtM(s.womenLow)+'</b></div>'+
      '<div class=\"card\">Minority women in low-access tracts: <b>'+s.pctMinLow.toFixed(1)+'%</b></div>'+
      '<div class=\"card\">Priority tracts: <b>'+s.nPriority.toLocaleString()+'</b> in '+s.nPriorityCty.toLocaleString()+' counties</div>';
    document.querySelectorAll('.lgc').forEach(function(c){
      c.style.outline=(catFilter&&c.getAttribute('data-k')===catFilter)?'3px solid #111':'none'; });
    document.getElementById('mode-explore').className='modebtn'+(mode==='explore'?' on':'');
    document.getElementById('mode-priority').className='modebtn'+(mode==='priority'?' on':'');
  }

  function wire(){
    var ss=document.getElementById('sel-sub'); if(!ss){setTimeout(wire,120);return;}
    ss.value=selSub;
    ss.addEventListener('change',function(){selSub=ss.value;refresh();});
    document.getElementById('sel-band').addEventListener('change',function(e){selBand=e.target.value;refresh();});
    document.getElementById('mode-explore').addEventListener('click',function(){mode='explore';refresh();});
    document.getElementById('mode-priority').addEventListener('click',function(){mode='priority';catFilter=null;refresh();});
    document.querySelectorAll('.lgc').forEach(function(c){ c.addEventListener('click',function(){
      var k=c.getAttribute('data-k'); catFilter=(catFilter===k)?null:k; if(catFilter)mode='explore'; refresh(); }); });
    document.getElementById('sel-state').addEventListener('change',function(e){
      var b=STBOUNDS[e.target.value]; if(b) map.fitBounds([[b.south,b.west],[b.north,b.east]]); });
    document.getElementById('btn-reset').addEventListener('click',function(){
      map.setView([38.5,-96],4); mode='explore'; catFilter=null;
      document.getElementById('sel-state').value=''; refresh(); });
    var ab=document.getElementById('about'); ab.innerHTML=ABOUT;
    document.getElementById('btn-about').addEventListener('click',function(){
      ab.style.display=(ab.style.display==='none')?'block':'none'; });
    refresh();
  }
  wire();
  map.on('zoomend', function(){ layer.setStyle(styleFor); });
"

m <- htmlwidgets::onRender(m, paste0("function(el,x){\n", data_js, js_body, "\n}"))

saveWidget(m, file = normalizePath(OUT, mustWork = FALSE), selfcontained = TRUE,
           title = "Geographic inequities in OB/GYN subspecialty access (2023)")
cat(sprintf("DONE -> %s  (%d tracts)\n", OUT, nrow(gb)))
