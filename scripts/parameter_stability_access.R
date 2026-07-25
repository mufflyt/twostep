#!/usr/bin/env Rscript
# ==============================================================================
# parameter_stability_access.R  (roadmap #2: parameter-stability appendix)
#
# Tests whether the drive-time access findings depend on the chosen travel-time
# threshold or distance-decay weights. For each county we compute women 65+ within
# 30/60/120/180-min drive of a urogynecologist (cumulative isochrone unions), then
# a decay-weighted access fraction under three prespecified Gaussian schemes reused
# from the E2SFCA line (R/two_step_floating_catchment.R):
#   base    30=1.00 60=0.68 120=0.22 180=0.09   (primary)
#   steeper 30=1.00 60=0.50 120=0.10 180=0.02
#   flatter 30=1.00 60=0.85 120=0.55 180=0.30
# The binary "within 30-min" (step) is the W=(1,0,0,0) special case.
#
# Reports: Spearman correlations across thresholds and step-vs-decay; access-tier
# agreement; % of the women-65+ population changing access tier; and the set of
# "structurally low-access" counties in the bottom tier under EVERY specification.
# Output: manuscript/stats/parameter_stability_access.csv + parameter_stability_structural.csv
# ==============================================================================
# ---------------------------------------------------------------------------
# PRIMARY SOURCES (rebuild reference; re-open the originals, do not trust memory):
#  Distance-decay / floating-catchment lineage the Gaussian weight schemes reuse:
#    Luo W, Wang F. "Measures of spatial accessibility to health care in a GIS
#    environment: synthesis and a case study in the Chicago region." Environ Plann
#    B Plann Des. 2003;30(6):865-884.  (original 2SFCA -- the binary within-band case)
#    Luo W, Qi Y. "An enhanced two-step floating catchment area (E2SFCA) method for
#    measuring spatial accessibility to primary care physicians." Health Place.
#    2009;15(4):1100-1107.  (E2SFCA -- the Gaussian distance-decay weights)
#    Delamater PL. "Spatial accessibility in suboptimally configured health care
#    systems: A modified two-step floating catchment area (M2SFCA) metric." Health
#    Place. 2013;24:30-43.  (M2SFCA)
#    Implementation reused from R/two_step_floating_catchment.R and the
#    scripts/desjardins7/ sensitivity line (do not duplicate that machinery).
#  Drive-time threshold choice (30/60/120/180 min) tied to payer access standards:
#    Ndumele CD, et al. "Variation in Network Adequacy Standards in Medicaid
#    Managed Care." JAMA Health Forum. 2022;3(6):e221735.
#  Rank stability reported as Spearman's rho; spatial ops via sf
#    (Pebesma E. R Journal. 2018;10(1):439-446).
# ---------------------------------------------------------------------------
suppressMessages({ library(sf); library(dplyr); library(readr) })
sf::sf_use_s2(FALSE)
root <- tryCatch(here::here(), error = function(e) getwd())
datadir <- file.path(root, "vignettes/urogyn_app/data")
msg <- function(...) message(sprintf(...))
BANDS <- c(30,60,120,180)
NONCONUS <- c("02","15","72","78","66","69","60")
# SSOT anchor (E2SFCA_DEFAULT_WEIGHTS): `base` equals the engine's canonical weights
# (R/two_step_floating_catchment.R); `steeper`/`flatter` are deliberate sensitivity
# variants, not copies. This appendix script is standalone (no engine source), so the
# literal is retained; base-equality is guarded by tests/testthat/test-ssot-band-weights.R.
W <- list(base    = c(1.00,0.68,0.22,0.09),
          steeper = c(1.00,0.50,0.10,0.02),
          flatter = c(1.00,0.85,0.55,0.30))

# tract fem65 centroids + county
tc <- readRDS(file.path(root,"scratchpad/urogyn_tract_fem65_centroids.rds"))   # GEOID, fem65, geom(4326)
tc$fips <- substr(tc$GEOID,1,5); tc <- tc[!substr(tc$fips,1,2) %in% NONCONUS & !is.na(tc$fem65), ]

# women 65+ within each cumulative band, per county. Enforce physical nesting
# (a tract reachable within 30 min is reachable within 60/120/180 min) since the
# separately-dissolved unions are not guaranteed perfectly nested.
within <- list(); prev <- rep(FALSE, nrow(tc))
for (b in BANDS) {
  cov <- sf::st_make_valid(sf::st_read(file.path(datadir, sprintf("coverage_%dmin.geojson", b)), quiet=TRUE))
  ins <- (lengths(sf::st_within(tc, cov)) > 0) | prev       # cumulative OR (enforces monotone nesting)
  prev <- ins
  within[[as.character(b)]] <- tapply(ifelse(ins, tc$fem65, 0), tc$fips, sum)
}
tot <- tapply(tc$fem65, tc$fips, sum)
fips <- names(tot)
P <- sapply(BANDS, function(b) { v <- within[[as.character(b)]][fips]; v[is.na(v)] <- 0; as.numeric(v) })
colnames(P) <- paste0("w", BANDS)                              # cumulative within-band women 65+
totv <- as.numeric(tot[fips])
pct <- P / totv                                                # cumulative within-band fraction
colnames(pct) <- paste0("pct", BANDS)

# decay-weighted access fraction per county (cumulative bands, incremental weights)
decay_frac <- function(w) {
  # cumulative bands + incremental weights: W30*P30 + W60*(P60-P30) + W120*(P120-P60) + W180*(P180-P120)
  (w[1]*P[,1] + w[2]*(P[,2]-P[,1]) + w[3]*(P[,3]-P[,2]) + w[4]*(P[,4]-P[,3])) / totv
}
score <- sapply(names(W), function(k) decay_frac(W[[k]]))
colnames(score) <- paste0("decay_", names(W))

D <- data.frame(fips, tot=totv, pct, score, check.names=FALSE)

# ---- Spearman stability ------------------------------------------------------
sp <- function(a,b) round(suppressWarnings(cor(a,b,method="spearman")),3)
msg("=== Spearman correlations (county access, n=%d) ===", nrow(D))
msg("Threshold: pct30~pct60=%s pct30~pct120=%s pct30~pct180=%s pct60~pct120=%s",
    sp(D$pct30,D$pct60), sp(D$pct30,D$pct120), sp(D$pct30,D$pct180), sp(D$pct60,D$pct120))
msg("Step (within-30) vs decay: base=%s steeper=%s flatter=%s ; base~steeper=%s base~flatter=%s",
    sp(D$pct30,D$decay_base), sp(D$pct30,D$decay_steeper), sp(D$pct30,D$decay_flatter),
    sp(D$decay_base,D$decay_steeper), sp(D$decay_base,D$decay_flatter))

# ---- RANK-based access tiers (quintiles) -> ordinal stability -----------------
# Rank tiers isolate the geography-of-access question from the absolute score
# level (a flatter decay raises every score but preserves order).
specs <- c("pct30","pct60","pct120","pct180","decay_base","decay_steeper","decay_flatter")
tier <- sapply(specs, function(s) dplyr::ntile(D[[s]], 5))
ref <- tier[,"decay_base"]
msg("\n=== Access-quintile agreement vs primary (decay_base; rank tiers) ===")
for (s in specs) {
  msg("  %-14s unit-agreement=%.1f%%  women-65+ same quintile=%.1f%%",
      s, mean(tier[,s]==ref)*100, sum(D$tot[tier[,s]==ref])/sum(D$tot)*100)
}
dspecs <- c("decay_base","decay_steeper","decay_flatter")
chg_pop <- sum(D$tot[apply(tier[,dspecs],1,function(t) length(unique(t))>1)])/sum(D$tot)*100
msg("  %% women 65+ changing access quintile across the 3 decay schemes: %.1f%%", chg_pop)

# ---- structurally low-access: bottom quintile under ALL decay schemes AND <25%
#      within a 30-min drive (rank-robust + absolute) --------------------------
low <- apply(tier[,dspecs], 1, function(t) all(t==1)) & (D$pct30 < 0.25)
msg("\n=== Structurally low-access counties (bottom access quintile under ALL 3 decay schemes AND <25%% within 30-min) ===")
msg("  counties=%d  women 65+=%s (%.1f%% of CONUS women 65+)",
    sum(low), format(round(sum(D$tot[low])), big.mark=","), sum(D$tot[low])/sum(D$tot)*100)
struct <- low

readr::write_csv(D, file.path(root,"manuscript/stats/parameter_stability_access.csv"))
readr::write_csv(D[struct, c("fips","tot","pct30","pct180","decay_base")],
                 file.path(root,"manuscript/stats/parameter_stability_structural.csv"))
saveRDS(list(D=D, tier=tier, struct=struct, W=W, specs=specs),
        file.path(root,"scratchpad/parameter_stability_state.rds"))
msg("\nDONE -> manuscript/stats/parameter_stability_access.csv (+ structural)")
