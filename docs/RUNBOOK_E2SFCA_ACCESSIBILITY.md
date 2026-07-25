# RUNBOOK — E2SFCA Accessibility Analysis (OB/GYN subspecialists)

**Scope.** The Enhanced Two-Step Floating Catchment Area (E2SFCA) accessibility
workstream: national travel-time access to the seven OB/GYN subspecialties,
2013–2023, plus the rurality/race disparity analysis, inferential statistics, and
maps. This is a **standalone analysis layer** that consumes the main pipeline's
isochrones + cohort artifacts; it is **not** part of `00_MASTER_PUBLICATION_PIPELINE.R`.

**Last verified run:** `e2sfca_20260712_190734` (git `ff3aac4a`, engine=raster,
500 m, EPSG:5070, 77/77 cells, conservation 1e-14). Allocator module seam-validated
sha256 `2b78718b…` (`R/two_step_floating_catchment.R`).

**Allocator hash re-pin (2026-07-24):** the whole-file module hash is now
`11abdec3…`; the gate in `scripts/run_2sfca.R` pins this. Post-freeze additions to
sibling functions (M2SFCA / Gaussian / SPAR) and primary-source doc comments moved
the whole-file hash, but `allocate_pop_areaweighted()` and its grid helpers are
byte-identical to the seam-validated `ff3aac4a` (verified), so the certified
allocation is unchanged. If the allocator BODY ever changes, re-run the seam test
and re-pin from that run instead of editing the constant.

---

## 0. Frozen reference facts (do not drift)

| Thing | Value |
|---|---|
| Allocator module | `R/two_step_floating_catchment.R`; gate pins whole-file sha256 **`11abdec3…`** (seam-validated body ancestor `2b78718b…`, re-pinned 2026-07-24) |
| Production allocator fn | `allocate_pop_areaweighted()` (polygon-cell overlap, mass-conserving) |
| Production alloc mode | `alloc = "area"` (NOT `"center"`) — this is the authoritative seam gate method |
| Grid / CRS | 500 m raster, EPSG:5070 (`E2SFCA_AREA_CRS`) |
| Bands | 30 / 60 / 120 / 180 min, Gaussian band-decay (`E2SFCA_DEFAULT_WEIGHTS/THRESHOLDS`) |
| Method | **E2SFCA is authoritative** (`step2_power = 1`). M2SFCA (`= 2`), Gaussian-zonal, and SPAR relative access are **sensitivity variants only** (`scripts/sensitivity_e2sfca_2020.R`), never the headline |
| National conservation tol | 0.005 (`E2SFCA_NATIONAL_CONS_TOL`); breach ⇒ **stop the year** |
| SSOT stats module | `R/accessibility_stratification.R` (guarded by `tests/testthat/test-accessibility-stratification.R`, 397 checks) |
| EC2 AMI | `overlap-r45-spatial` (R 4.5.1); IAM `valhalla-ec2-profile`; region us-east-2; bucket `tyler-valhalla-tiles` |
| Env lock | R 4.5.1 / sf 1.1.1 / terra 1.9.34 / exactextractr 0.10.1 / GEOS 3.13.0 / GDAL 3.10.3 / PROJ 9.6.2 |
| Output dirs | `artifacts/2sfca/` (production), `artifacts/2sfca/figures/` (downstream), `artifacts/2sfca_seam/` (seam gate + surface maps), `artifacts/2sfca_superseded/` (dead runs — do NOT read) |

**Subspecialty codes:** `GO, MFM, REI, FPMRS, MIGS, PAG, CFP`.

---

## 1. Step order

Run top-to-bottom. Steps 1–3 are the production run (usually EC2); steps 4–7 are
local downstream analysis on the run's `step_4_2sfca_<SUB>_<YEAR>.rds` outputs.

| # | Step | Script | Where |
|---|---|---|---|
| 1 | Prefetch deterministic multi-year ACS bundle | `scripts/prefetch_2sfca_acs.R` | local (needs Census API) |
| 2 | Seam gate — prove the allocator (5 methods; pick `mass_conserving`) | `scripts/seam_test_2sfca.R` (`scripts/ec2_run_seam.sh`) | EC2 |
| 3 | **Production 11-year run** (all subspec × year) | `scripts/run_2sfca.R` via `scripts/ec2_run_2sfca.sh` | EC2 |
| 4 | Rurality + race stratification (all subspec, all years) | `scripts/stratify_allyears_access.R` | local |
| 5 | Inferential stats (MC 95% CIs + OLS trends) | `scripts/inferential_stats_access.R` | local |
| 6 | Cross-subspecialty summary table | `scripts/compile_inferential_table.R` | local |
| 7 | Figures & maps (national trends, coverage footprints, access surfaces) | `figure_2sfca_national_11yr.R`, `map_2sfca_coverage_by_year.R`, `map_go_2020_access_surface.R`, `map_fpmrs_allyears_access_surface.R` | local |

**Fast path for downstream-only work:** the full production access set
(`step_4_2sfca_<SUB>_<YEAR>.rds` for all 7×11 cells + `e2sfca_run_manifest.json`)
lives in the session scratchpad `go2020/`. Point `--access-dir` there and skip 1–3.

---

## 2. Per-script reference (purpose · key knobs · gotchas)

### `scripts/prefetch_2sfca_acs.R`  → `acs_bundle_2013_2022.rds`
- **Purpose:** deterministic ACS demand so the production run needs **no Census
  API** (hermetic). Bundle = `pop_by_year` (2013–2022 female totals) + `geom_by_vintage` (2010 & 2020 tract geometry).
- **Gotcha:** 2020 total must be **164,690,617**; 2020-vintage geom (83,776 tracts)
  is reused from the seam bundle. If a year is missing, the production run
  **fails closed** (`--acs-bundle missing pop for ACS year(s)…`).

### `scripts/seam_test_2sfca.R` (`ec2_run_seam.sh`)  → `artifacts/2sfca_seam/`
- **Purpose:** the allocator gate. Computes 5 methods — `raw`, `equal_total`
  (both center-based diagnostics), **`mass_conserving`** (area, native totals —
  the ONLY production-candidate), `mass_conserving_eqtot`, `geometry_only`.
- **Gotcha:** the **authoritative gate method is `mass_conserving`**. Diagnostic
  methods cannot authorize a different production allocator. The seam manifest
  records exactly one `authoritative_gate_method = TRUE`.
- **Caveat:** `map_go_2020_access_surface.R` (the pretty magma surface) also lives
  off the seam run — it is GO-2020 only unless regenerated.

### `scripts/run_2sfca.R` (`ec2_run_2sfca.sh`)  → `artifacts/2sfca/` + manifest
- **Purpose:** the national 11-year × 7-subspec run.
- **Key flags/env:** `--acs-bundle`, `--run-id`, `--seam-gate-rds`,
  `E2SFCA_SEAM_ALLOCATOR_SHA256`, `E2SFCA_NATIONAL_CONS_TOL` (0.005), `E2SFCA_GIT_SHA`.
- **Fail-closed gates (all `stop()`):**
  1. **Allocator identity** — module sha256 must `==` `SEAM_ALLOCATOR_SHA256`
     (`11abdec3…`, re-pinned 2026-07-24; body ancestor `2b78718b…`), fn `allocate_pop_areaweighted` must exist, default `alloc` must
     be `"area"`. Any mismatch aborts *before compute*.
  2. **National conservation** — per year, `abs(1 − pop_raster_total/acs_pop) > tol`
     stops that year. Do not relax the tol to "get past" a breach — a breach means
     the grid is dropping people.
- **Gotchas:**
  - Manifest PROJ field: use `unname(sf::sf_extSoftVersion()["PROJ"])` — the old
    `[["PROJ.4"]]` throws subscript-out-of-bounds.
  - Headline numbers come from `e2sfca_national_summary.csv` (cell-level,
    population-weighted) — **not** any tract-level re-aggregation.

### `scripts/sensitivity_e2sfca_2020.R`  → `sensitivity_2020_*.csv` + `sensitivity_2020_manifest.json`
- **Purpose:** the 2020 robustness sweep. One cross-section (2020) recomputed under
  seven parameter variants × seven subspecialties, to confirm the headline
  rank-order and disparity signs do not depend on a single decay/impedance choice.
- **Variants (all in `R/two_step_floating_catchment.R`):**

  | Variant | What changes | Engine knob |
  |---|---|---|
  | `base` | E2SFCA, band weights 1.00/0.68/0.22/0.09, 1000 m | `step2_power = 1` |
  | `sharper` | faster decay (1.00/0.42/0.09/0.02) | tighter catchment |
  | `slower` | slower decay (1.00/0.85/0.55/0.30) | wider catchment |
  | `drop180` | 180-min band removed (30/60/120 only) | shorter maximum catchment |
  | `res500` | base weights at **500 m** grid | resolution check |
  | `gaussian` | **Gaussian-derived ZONAL** band weights, σ = 60 min | `gaussian_band_weights()` |
  | `m2sfca` | **M2SFCA** maldistribution penalty (Delamater 2013) | `step2_power = 2` |

- **Methodological contracts (do NOT drift — each was a correction):**
  - M2SFCA squares the CUMULATIVE weights before differencing: the step-2 increment
    is `diff(W^2)`, **NOT** `diff(W)^2` (`e2sfca_incremental_weights(step2_power = 2)`).
    Step 1 (the demand denominator) is ALWAYS `step2_power = 1`; only step 2 gets the
    second distance penalty. M2SFCA national access must be `<=` base (a numerical
    gate enforces this).
  - The `gaussian` variant is a **zonal four-band approximation**, not a continuous
    distance function. `gaussian_band_weights()` normalizes G(d) to the inner band
    (W₁ = 1); the raw kernel `gaussian_decay_weights()` (G(0) = 1) is NOT normalized
    and must not be relabeled "continuous."
  - **Zero-demand semantics:** a provider whose weighted demand is 0 yields
    `ratio = NA` (undefined, not 0), `ratio_for_surface = 0`, `zero_demand = TRUE`,
    and its supply is reported in the `$audit` block (`n_zero_demand_origins`,
    `share_supply_zero_demand`). Never let `ratio = 0` silently hide an invalid
    denominator.
  - **SPAR** (Wan 2012 Spatial Access Ratio): every result carries
    `relative_access = access / national_pop_weighted_mean`, so the national mean is
    1.00 by construction and cross-subspecialty surfaces are directly comparable.
- **Frozen inputs + provenance:** `E2SFCA_YCM_PATH` (year-cohort-month coords) and
  `E2SFCA_COHORT_PATH` pin the exact inputs; every input + output SHA-256 is written
  to `sensitivity_2020_manifest.json`. The exploratory metro/rural composite is
  **disabled by default** (relabeled exploratory, gated behind
  `RUN_EXPLORATORY_COMPOSITE=1`) and is never part of the headline.
- **Numerical gates (all `stop()`):** `national == national_check`; all values finite
  and non-negative; exactly one row per (variant, subspec) with no missing cells;
  `m2sfca national <= base national`.
- **2020 result (robustness confirmed):** subspecialty rank correlation ρ = 1.000
  across all specs; rural < metro 7/7; AIAN < white 7/7 (6/7 under M2SFCA); M2SFCA
  national < base (e.g. GO 0.341 vs 0.541). `QUICK=1` runs GO only under
  base/gaussian/m2sfca at 1000 m for a smoke check.

### `scripts/ec2_run_2sfca.sh`  (EC2 harness — S3 transport only)
- **Gotchas (each was a real failed launch):**
  - AMI **lacks `testthat`**; `fs` won't compile without `USE_BUNDLED_LIBUV=1`;
    installs need `sudo Rscript scripts/ec2_install_pkgs.R` (system lib not writable).
  - Tarball **must ship** `R/utils/safe_save.R` (sourced by `write_rds_atomic.R`) —
    a missing-file mid-run once wrote `CFP_2013` then died.
  - Enforces the **env lock** and fails before compute on drift.
  - Distinct sentinels `_SUCCESS.json` / `_FAILED.json` — **no trap fabricates
    success**. Every prior failure correctly wrote `_FAILED`.
  - **Transport rule:** Mac↔EC2 bulk = **S3 multipart only** (`scripts/s3_multipart_put.sh`),
    presigned `curl` down, SHA-256 gate both ends. `rsync`/`scp` to EC2 breaks
    (broken pipe). `rsync` is Mac↔Mac only.

### `scripts/stratify_allyears_access.R`  → per-subspec CSVs + `allsubspec_allyears_stratified_LONG.csv`
- **Purpose:** rurality + race/ethnicity stratified access, per subspec, 2013–2023.
- **Flags:** `--access-dir DIR`, `--subspec all|GO,MFM`, `--acs-cache DIR`, `--out DIR`, `--no-figures`.
- **Wired to the SSOT module** (2026-07-14): `wmean`/`zshare`/`acs_year_of`/
  `vintage_of`/`VARS` come from `R/accessibility_stratification.R`.
- **Gotchas:**
  - **RUCA 99 is excluded** (`rurality_from_ruca` → NA → dropped): the ~368
    zero-population "not coded" 2020-vintage tracts. Zero-weight, so this moved no
    number — but do not "restore" them as Rural.
  - ACS demand is **per year, not per subspec** (fetched once, reused).
  - Tract vintage: 2013–2019 → 2010 tracts (RUCA 2010, ACS ≤2019); 2020–2023 →
    2020 tracts (RUCA 2020, ACS ≥2020, **2023 → ACS 2022**).

### `scripts/inferential_stats_access.R`  → `<SUB>_2020_inferential_MC_CI.csv`
- **Purpose:** 95% CIs by **Monte-Carlo propagation of ACS MOE** (weights ~
  Normal(est, MOE/1.645), B=2000) + OLS temporal trends (2013–2022, **2023 excluded**
  for right-censoring).
- **Wired to the SSOT module** for `wmean`/`zsh`.
- **CRITICAL gotcha (the bug this whole module exists to prevent):** do **NOT**
  clamp negative MC draws and do **NOT** filter `w>0`. Both put sparse-group
  (AIAN, NHPI) point estimates **outside their own CI** by injecting spurious
  weight into zero-estimate tracts. The estimators must **sum over ALL elements**.
  The regression guard is `make_sparse_group()` in the test file.
- **Flags:** `--access-dir`, `--subspec`, `--B`, `--acs-cache`.

### `scripts/compile_inferential_table.R`  → `allsubspec_2020_inferential_TABLE.csv`
- **Purpose:** cross-subspec MC-CI + trend one-liner table. Reads the per-subspec
  `*_2020_inferential_MC_CI.csv` + `…LONG.csv`. Run **after** step 5 for all subspecs.

### `scripts/figure_2sfca_national_11yr.R`  → `fig_2sfca_national_11yr_<run>.png`
- **Purpose:** 3-panel national figure (A conservation, B 2020 by subspec, C
  11-year trends, log scale).

### `scripts/map_2sfca_coverage_by_year.R`  → `map_coverage_by_year_<SUB>_<BAND>min.png`
- **Purpose:** per-year **footprint** small-multiple — the *union* of drive-time
  catchments around each year's active cohort (binary reachable/not).
- **Env:** `E2SFCA_MAP_SUB` (default GO), `E2SFCA_MAP_BAND` (default 60).
- **Gotcha:** loads `step_3_year_coord_map.rds` + `step_2.5_final_cohort.rds` via a
  `newest()` mtime search — make sure the newest is the one you intend (see
  cohort-pinning caveat §3).

### `scripts/map_go_2020_access_surface.R` / `scripts/map_fpmrs_allyears_access_surface.R`  → `artifacts/2sfca_seam/figures/`
- **Purpose:** the continuous magma **access surface** (per-100k score on the 500 m
  grid), coarsened to ~4 km for display, √-scaled, capped at p98. GO = 2020 only;
  FPMRS = all-years small-multiple.
- **Gotchas:**
  - Builds **one grid per tract vintage** (2010 & 2020), not per year — the all-years
    version holds demand at a **vintage-representative ACS year** (2019 / 2020) so
    the panel-to-panel driver *within a vintage* is the cohort, not demand noise.
  - Full ACS-with-geometry fetch (CONUS) is heavy; `options(tigris_use_cache=TRUE)`.
  - `compute_e2sfca_raster(..., return_surface=TRUE)` → `res$surface * 1e5`.

---

## 3. Cross-cutting caveats

- **Coverage map ≠ surface map.** Coverage (`map_2sfca_coverage_by_year`) = binary
  "reachable within BAND min". Surface (`map_*_access_surface`) = continuous E2SFCA
  score blending all 4 bands + supply. Don't conflate them in captions.

- **Cohort pinning.** The map scripts resolve `ycm` / `cohort` by newest-mtime.
  Different snapshots give slightly different provider counts (e.g. FPMRS 2016 =
  859 origins from `20260702_120134` vs the ~783 active-2020 figure from another
  snapshot). **Before quoting counts in the manuscript, pin every figure to the
  same frozen cohort** used by the production run.

- **ACS race-female footgun.** Race-iterated tables `B01001[B–I]` use **`_017`** for
  the female total; the full table `B01001` uses **`_026`**. Using `_026` on a race
  table silently returns the wrong cell. Codes are pinned in `RACE_FEMALE_VARS`.

- **Race code assignment.** `C = AIAN`, `D = Asian`, `E = NHPI`, `B = Black`,
  `H = White NH`, `I = Hispanic`. A `C↔D` swap silently **inverts the headline AIAN
  finding**. Pinned + tested.

- **RUCA cut.** Metropolitan = primary RUCA **1–3**; Rural = **4–10**; **99 / uncoded
  → NA → excluded** (zero-pop tracts).

- **Retirement / year-specific cohort.** Each year's surface/footprint uses only
  physicians **active that year** (`retirement_year > Y`, strict). Isochrone geometry
  is year-agnostic; the yearly union/surface moves because the **cohort** moves. If
  a subspec × band shows bit-identical footprints across years, the temporal cohort
  filter is broken (see CLAUDE.md #2).

- **Valhalla is EC2-only.** No local Valhalla for any band. Local scripts may
  *consume* prebuilt isochrone artifacts (`artifacts/isochrones/isochrones_<band>min_consolidated.rds`)
  but must not start a Valhalla server.

- **Do not read `artifacts/2sfca_superseded/`.** Those are `INCOMPLETE`/dead runs
  kept only for forensics.

- **Trend caveat for the manuscript.** OLS treats each annual estimate as one
  observation; P values index the consistency of a monotone trend, not a formal
  population inference. 2023 is excluded from trends (workforce right-censoring).

---

## 4. Verification checklist (before trusting/reporting numbers)

1. `shasum -a 256 R/two_step_floating_catchment.R | cut -c1-16` → `11abdec3e577e81e`
   (was `2b78718bf65c2ecb` pre-2026-07-24 re-pin; allocator body unchanged between them).
2. Production manifest `identity_verified = true` and per-year conservation within tol.
3. `Rscript -e 'testthat::test_file("tests/testthat/test-accessibility-stratification.R")'`
   → **397 checks, 0 failures** (guards the MC estimator + race codes + RUCA + wiring).
4. Headline national numbers come from `e2sfca_national_summary.csv` (cell-level).
5. Any manuscript figure's cohort matches the frozen production cohort (§3).
6. Sparse-group (AIAN/NHPI) point estimates lie **inside** their MC CIs (if not, the
   `w>0`/clamp bug is back).

---

*Related: `manuscript/RESULTS_e2sfca_accessibility_DRAFT.md` (Results draft + Methods
note), CLAUDE.md #2 (temporal cohort), #17 (5 km haversine coverage), #18 (cache
provenance), #19 (canonical source / grain).*

*Last updated: 2026-07-14.*
