# SSOT audit ledger (twostep)

Cumulative record of the single-source-of-truth loop so no value is audited twice.
Loop: every 30 minutes, up to 16 iterations (~8 hours). No commits (per instruction).

| # | Candidate | Status | Notes |
|---|---|---|---|
| 1 | Base E2SFCA band weights `(30=1.00, 60=0.68, 120=0.22, 180=0.09)` | **COMPLETE** (audit + guard + refactor, iter 1-2) | see below |
| 2 | Frozen production `run_id` `e2sfca_20260712_190734` | **COMPLETE** (audit + resolver + guard + refactor, iter 3) | see below |
| 3 | National ACS 2020 female-pop denominator `164690617` | **COMPLETE** (audit + constant + accessor + guard + refactor, iter 4) | see below |
| 4 | Allocator `method_id` `mass_conserving` | **COMPLETE** (constant + manifest guard, iter 5) | see below |
| — | Allocator `module_sha256` `2b78718b` | **STOPPED — authority split / intentional two-value distinction** (iter 5) | see below |
| 5 | Seven-subspecialty CODE SET `{MFM,GO,REI,FPMRS,MIGS,PAG,CFP}` | **COMPLETE** (set constant + repo-wide guard + manuscript wired, iter 6) | see below |
| 6 | Subspecialty figure/map FULL-NAME label map | **COMPLETE** (label constant + 3 scripts wired + en-dash fixed + guard, iter 7) | see below |
| 7 | Equal-area CRS `5070` (`E2SFCA_AREA_CRS`) | **COMPLETE** (already canonical; alias wired + drift guard, iter 8) | see below |
| 8 | Production raster resolution `500 m` | **COMPLETE** (constant + manifest guard + 2 production scripts wired, iter 9) | see below |
| 9 | Allocator conservation tolerance `1e-6` | **COMPLETE** (producer reads engine default via formals; engine untouched — sha-gated, iter 10) | see below |
| 10 | Figure display em-dashes (style rule) | **COMPLETE** (8 figure titles fixed + display-scope guard, iter 11) | see below |
| 11 | Seam method vocabulary (`SEAM_METHODS`) | **COMPLETE** (2 identical vectors consolidated + guard; fixed 1 regression, iter 12) | see below |
| 12 | Access thresholds `c(0,1,5,10,20,50)` | **VERIFIED already-SSOT** (no refactor; hardening guard added; seam lock preserved, iter 13) | see below |
| 13 | Subspecialty workforce sizes (7 counts) | **COMPLETE** (run-derivation + CSV cross-check + adversarial guard, iter 14) | see below |
| 14 | CONUS state FIPS vector (`conus()` x12) | **COMPLETE** (`CONUS_STATE_FIPS`; 4 wired, 8 anchored, drift guard, iter 15) | see below |

## Iteration 1 — base E2SFCA band weights

**Why high risk:** the distance-decay weights drive every access number; defined
independently in 5+ files, so a one-place edit silently changes published results.

**Provenance (audit):**

| File:line | Value | Role |
|---|---|---|
| `R/two_step_floating_catchment.R:140` | `E2SFCA_DEFAULT_WEIGHTS <- c("30"=1.00,"60"=0.68,"120"=0.22,"180"=0.09)` | **AUTHORITATIVE** |
| `R/desjardins7_e2sfca.R:37` | `DJ7_WC_BASE <- c(...)` | duplicate |
| `scripts/desjardins7/06_tract_e2sfca_denominator.R:22` | `Wc <- c(...)` | duplicate |
| `scripts/parameter_stability_access.R:47` | `W$base <- c(1.00,0.68,0.22,0.09)` | duplicate (base scenario) |
| `scripts/sensitivity_e2sfca_2020.R:69` | `.BASE_W <- c(...)` | duplicate (base scenario) |
| `scripts/run_2sfca.R:24` (comment) | doc string | documentation only |

**Discrepancies:** none numeric; all base copies equal the canonical (true
duplicates, not drift). The `sharper`/`slower`/`drop180` sensitivity variants are
DELIBERATE scenario differences and are preserved (`drop180` = 3-band, correctly
excluded by the guard after an adversarial fix).

**Canonical contract:** name `E2SFCA_DEFAULT_WEIGHTS`; four cumulative-band decay
weights keyed "30"/"60"/"120"/"180"; unitless in (0,1]; W1==1, monotone
non-increasing; source = engine; consumers = engine + every access script.

**Done this iteration:** guard test `tests/testthat/test-ssot-band-weights.R`
(canonical value + names + monotonicity + normalization; and a repo scan that fails
if any file defines a drifted FOUR-band base vector). Suite: 565 pass, 0 fail.

**Deferred to iteration 2 (same candidate):** replace the duplicate DEFINITIONS in
scripts that `source()` the engine with `E2SFCA_DEFAULT_WEIGHTS` (verify each sources
the engine first; leave comments/provenance and genuine scenario vectors untouched).

## Iteration 2 — base E2SFCA band weights (refactor completed)

**Adjudication of each duplicate DEFINITION:**

| File:line | Sources engine? | Treatment | Rationale |
|---|---|---|---|
| `R/two_step_floating_catchment.R:140` | authoritative | unchanged | canonical `E2SFCA_DEFAULT_WEIGHTS` |
| `scripts/sensitivity_e2sfca_2020.R:69` | YES (line 52) | **`.BASE_W <- E2SFCA_DEFAULT_WEIGHTS`** | real consumer; canonical now physically reaches it; scenario vectors sharper/slower/drop180 left literal |
| `R/desjardins7_e2sfca.R:41` | no (standalone base-R module) | SSOT-anchor comment | file is deliberately dependency-light + self-testable; equality enforced by guard |
| `scripts/parameter_stability_access.R:51` | no (standalone appendix) | SSOT-anchor comment | `base` == canonical; `steeper`/`flatter` are deliberate variants (distinct from sensitivity's sharper/slower) |
| `scripts/desjardins7/06_tract_e2sfca_denominator.R:25` | no (standalone) | SSOT-anchor comment | matches the file's existing `CANONICAL_BANDS` anchor idiom |

**Idiom chosen:** the repo already anchors standalone literals with an
`# SSOT anchor (NAME): ... literal retained for standalone execution` comment
(pre-existing for `CANONICAL_BANDS`). Applied the same idiom to the base weights so
standalone scripts stay standalone (no new heavy engine dependency at load time)
while any drift is caught by the guard test rather than silently accepted.

**Guard strengthened:** added a positive cross-module semantic test
(`DJ7_WC_BASE` == `E2SFCA_DEFAULT_WEIGHTS`, names + values) alongside the existing
repo-scan drift detector. Both the engine and the base-R desjardins7 module are light
to `source()`, so the two named in-code constants are asserted identical directly.

**Discrepancies:** `parameter_stability_access.R` uses scenario labels
`steeper`/`flatter` while `sensitivity_e2sfca_2020.R` uses `sharper`/`slower`; these
are DISTINCT deliberate sweeps (different values except a coincidental
0.85/0.55/0.30) and were preserved, not merged.

**Files changed:** `scripts/sensitivity_e2sfca_2020.R`,
`scripts/parameter_stability_access.R`,
`scripts/desjardins7/06_tract_e2sfca_denominator.R`, `R/desjardins7_e2sfca.R`,
`tests/testthat/test-ssot-band-weights.R` (guard).

**Tests:** narrow guard 7/7; full suite **567 pass / 0 fail** (was 565; +2 from the
new cross-module test). 2 pre-existing lm perfect-fit warnings, unrelated. Parse-check
+ canonical-resolution sanity check both pass.

**Remaining risk:** the `manuscript` HTML prints the weights as prose ("1, 0.68,
0.22, 0.09") in three spots; those are rendered narrative, not a live copy, and are a
separate (lower-risk) candidate if a future iteration wants displayed==canonical.

## Iteration 3 — frozen production run_id `e2sfca_20260712_190734`

**Why high risk:** the run id is the pointer to the frozen artifacts that back
every manuscript Abstract/Results number. It was pasted as a literal into ~17
places (paths, an assertion, an env-var default, captions, docs, the manifest) via
THREE different mechanisms (bare literal, `Sys.getenv(...,"literal")`, and manifest
lookup). A stale/renamed run silently feeds wrong numbers with no error.

**Provenance (audit):**

| File:line | Value | Role |
|---|---|---|
| `artifacts/2sfca/ec2/<RUN>/e2sfca_run_manifest.json` `run_id` | the id | **AUTHORITATIVE** (self-declared) |
| `scripts/manuscript_e2sfca_values.R:30` | `E2SFCA_FROZEN_RUN_ID <- Sys.getenv("E2SFCA_RUN_ID", <literal>)` | **CANONICAL constant** (new) |
| `scripts/manuscript_e2sfca_values.R` `e2sfca_run_dir()` | resolver + fail-loud manifest match | **CANONICAL resolver** (new) |
| `manuscript/...Rmd:29` | was literal path → now `e2sfca_run_dir()` | manuscript consumer (highest risk) |
| `manuscript_e2sfca_values.R` assertion + script-mode run_dir | was literal → constant/resolver | consumer |
| `scripts/figure_2sfca_national_11yr.R:24` | was `Sys.getenv(...,literal)` → `E2SFCA_FROZEN_RUN_ID` | consumer (env override preserved) |
| `scripts/stratify_go_2020_access.R:27-29` | literal ×2 (dir + `run_<id>`) → constant + `paste0("run_",...)` | consumer |
| `scripts/desjardins7/06_tract_e2sfca_denominator.R:18` | literal path → constant | consumer |
| `scripts/stratify_go_allyears_access.R:116`, `scripts/stratify_allyears_access.R:194` | caption **display** literal | SSOT-anchored (data dir = `GO_ACCESS_DIR`) |
| `R/two_step_floating_catchment.R:83`, `docs/*` | prose/provenance record | documentation, left literal |

**Canonical contract:** `E2SFCA_FROZEN_RUN_ID` = character scalar naming the frozen
run dir under `artifacts/2sfca/ec2/`; env-overridable via `E2SFCA_RUN_ID` (this
subsumes the figure script's separate env pattern). `e2sfca_run_dir()` resolves the
path and **fails loudly** if the dir/manifest is missing or the manifest's declared
run_id disagrees (stale-pointer guard; no silent fallback).

**Discrepancies/adjudication:** the two all-years stratify captions hardcode the id
as a *display label* while loading data from `GO_ACCESS_DIR` — injecting the constant
could MISLABEL a different run, so they were anchor-commented (not wired). Docs and
the engine header state the id as provenance and were left as records.

**Files changed:** `manuscript_e2sfca_values.R` (constant + resolver + 2 rewires),
`e2sfca_accessibility_manuscript.Rmd`, `figure_2sfca_national_11yr.R`,
`stratify_go_2020_access.R` (path ×2 + live caption), `desjardins7/06_...R`,
`stratify_go_allyears_access.R` + `stratify_allyears_access.R` (anchors),
`tests/testthat/test-ssot-frozen-run-id.R` (new).

**Guards/tests:** runtime resolver fail-loud on missing + mismatched manifest;
7-test guard file (constant shape; resolver matches manifest; unknown id stops;
mismatched manifest stops; no `file.path` embeds the literal; exactly one `<-`
assignment of the literal = the canonical). 10 assertions, all pass.

**Failures:** none refactor-caused. Manuscript load chain re-verified end-to-end
(resolver → `load_e2sfca_national_summary` still returns 77 rows). Sourcing the
loader from consumer scripts confirmed side-effect-free (script-mode block guarded).

**Tests:** full suite **577 pass / 0 fail** (was 567; +10). 2 pre-existing lm
warnings, unrelated.

**Remaining risk:** the all-years caption labels can still drift from an overridden
`GO_ACCESS_DIR` (flagged, not fixed — would need the label derived from the actual
source dir). Docs restate the id in 4 spots (provenance records, low risk).

## Iteration 4 — national ACS 2020 female-pop denominator `164690617`

**Why high risk:** it divides national coverage into every "% of ACS" fraction; a
stale/mistyped copy silently rescales those percentages with no error. It was pasted
as a literal into two figure scripts (both labelled "source of truth") and a figure
data row, while the true value lives in the frozen national summary.

**Provenance (audit):**

| File:line | Value | Role |
|---|---|---|
| `artifacts/.../e2sfca_national_summary.csv` `acs_pop_source` (year 2020) | 164690617 (unique across all 7 subspecs) | **AUTHORITATIVE** |
| `scripts/manuscript_e2sfca_values.R` `E2SFCA_ACS_FEMALE_POP_2020` | `164690617L` | **CANONICAL constant** (new) |
| `scripts/manuscript_e2sfca_values.R` `e2sfca_acs_female_pop()` | reads CSV, returns `acs_pop_source` | **CANONICAL accessor** (new) |
| `scripts/figure_2sfca_national_11yr.R:33` | was literal (DEAD — defined, never used) → constant | consumer |
| `scripts/figure_2sfca_seam_outcomes.R:19` | `ACS` denominator: literal → constant | consumer |
| `scripts/figure_2sfca_seam_outcomes.R:25` | mass-conserving `represented`: literal → `ACS` (conservation identity) | consumer |
| `docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md:69` | "2020 total must be 164,690,617" | doc/provenance, left as record |
| `scripts/figure_2sfca_seam_outcomes.R` legacy `162947926` | distinct MEASURED value | preserved literal |

**Canonical contract:** `E2SFCA_ACS_FEMALE_POP_2020` = integer national ACS female
count (all ages, CONUS, 2020); range guarded to (1e8, 2.5e8). `e2sfca_acs_female_pop(year)`
re-derives it live from the frozen summary and **fails loudly** if the year is absent
or the `acs_pop_source` is not unique. The test suite pins the constant == the
artifact-derived value, so the in-code copy cannot drift from the CSV.

**Discrepancies/adjudication:** the seam figure used the literal TWICE with different
meanings — as `ACS` (denominator) and as the mass-conserving `represented` value.
Because mass-conserving allocation recovers *exactly* the ACS population (the figure's
whole thesis), the represented value IS `ACS`; wired it to `ACS`. The legacy
center-based `162947926` is a genuinely different measured result and stays literal.
`ACS2020` in the 11yr figure was dead (defined, never referenced) — repointed to the
constant rather than deleted (SSOT scope, not dead-code removal).

**Files changed:** `manuscript_e2sfca_values.R` (constant + accessor),
`figure_2sfca_national_11yr.R`, `figure_2sfca_seam_outcomes.R` (×2),
`tests/testthat/test-ssot-acs-female-pop.R` (new).

**Guards/tests:** runtime fail-loud accessor (missing year, non-unique denominator);
10-assertion guard file — constant type/range/integer-ness; constant == artifact
derivation; absent-year stops; adversarial non-unique-denominator CSV stops; no code
file hardcodes the literal except the canonical constant.

**Failures:** none refactor-caused. Parse-checks pass; the seam tribble now coerces
`represented` to numeric (integer `ACS` + double legacy) — same value, behavior
preserved.

**Tests:** full suite **587 pass / 0 fail** (was 577; +10). 2 pre-existing lm
warnings, unrelated.

**Remaining risk:** the runbook restates "164,690,617" as a provenance gotcha (record,
low risk). Only the 2020 denominator is canonicalized; other years' `acs_pop_source`
are read live from the CSV wherever needed (no other hardcoded year-denominators found).

## Iteration 5 — allocator identity (`method_id` refactored; `module_sha256` stopped)

**Candidate selected:** the allocator provenance identity. On audit it split into two
sub-values with very different safety, so only the safe half was refactored.

**Why high risk:** `method_id` asserts WHICH allocator produced the frozen numbers; a
silent disagreement would let the manuscript claim a run it did not use.

**Provenance (audit):**

| File:line | Value | Role |
|---|---|---|
| `artifacts/.../e2sfca_run_manifest.json` `allocator$method_id` | "mass_conserving" | **AUTHORITATIVE** (written by producer) |
| `scripts/run_2sfca.R:462` | `method_id = "mass_conserving"` | **PRODUCER** (writes the manifest) — left as source |
| `scripts/manuscript_e2sfca_values.R:118` | assertion literal → `E2SFCA_ALLOCATOR_METHOD_ID` | manuscript consumer (refactored) |
| `scripts/seam_test_2sfca.R:64,335,…` | member of `EXPECTED_METHODS` / `METHOD_ORDER` | **deliberate method vocabulary** — preserved |
| `docs/*`, `run_2sfca.R` comments | prose | provenance records — left |

**method_id — refactor:** added `E2SFCA_ALLOCATOR_METHOD_ID <- "mass_conserving"` to
the shared loader and pointed the loader's own validation assertion at it. The
producer (`run_2sfca.R`) keeps its literal — it is the SOURCE that writes the
manifest, not a copy of the manuscript's expectation (correct SSOT direction:
producer → manifest → manuscript constant validated against manifest). The seam
five-method vocabulary is a labeled code list and was NOT collapsed.

**module_sha256 — STOPPED (authority unclear / intentional distinction):** the code
carries TWO deliberately different shas — `2b78718bf65c…` (the frozen run's
seam-validated allocator body sha, immutable in the manifest) and `11abdec3…` (the
current whole-file sha of `R/two_step_floating_catchment.R` after the 2026-07-24
annotation re-pin; allocator body unchanged). The manifest is already SSOT for the
frozen sha, and the producer already writes it from the `SEAM_ALLOCATOR_SHA256`
variable (not a literal); the remaining `2b78718b` occurrences are provenance
comments + one figure caption. Collapsing the two shas would erase a real historical
distinction. Per the loop rule, stopped rather than forced.

**Files changed:** `scripts/manuscript_e2sfca_values.R` (constant + assertion),
`tests/testthat/test-ssot-allocator-method-id.R` (new). No behavior change.

**Guards/tests:** 8-assertion guard — constant is a single non-empty string; constant
== frozen manifest `method_id` and manifest `identity_verified` is TRUE; constant is a
member of the seam `EXPECTED_METHODS` vocabulary (parsed from the seam script, not
hand-copied); loader holds exactly one `"mass_conserving"` quoted literal (the
constant). Manuscript load chain re-verified (77 rows).

**Tests:** full suite **595 pass / 0 fail** (was 587; +8). 2 pre-existing lm
warnings, unrelated.

**Remaining risk:** the seam method vocabulary (`raw`/`equal_total`/`mass_conserving`/
`mass_conserving_eqtot`/`geometry_only`) is itself an un-canonicalized code list
repeated across `EXPECTED_METHODS`, `METHOD_ORDER`, and switch/label maps in
`seam_test_2sfca.R` — a future candidate. The two allocator shas remain
manifest-/variable-managed (documented, not refactored).

## Iteration 6 — seven-subspecialty CODE SET (labels + non-canonical orders scoped OUT)

**Why high risk:** the 7-code set is repeated in ~15 vectors (engine, scripts,
manuscript, seam, figure label maps). A drifted MEMBER (misspelling, dropped/added
subspecialty) silently changes which specialties are analysed or labelled.

**Audit — the set appears in THREE deliberate variants (not collapsed):**

| Variant | Where | Treatment |
|---|---|---|
| Manuscript display order `MFM,GO,REI,FPMRS,MIGS,PAG,CFP` | engine `DJ7_SUBS`, manuscript `subs7` + factor levels, several scripts | **CANONICAL** `E2SFCA_SUBSPECIALTIES` |
| Alphabetical `CFP,FPMRS,GO,MFM,MIGS,PAG,REI` | `seam_test_2sfca.R` (`ALL7`, compared via `sort()`), `run_2sfca.R` `ALL_CODES`, `stratify_allyears_access.R` | order-agnostic membership list — **preserved**, guarded by SET |
| `URPS` synonym + different tail order | `scripts/manuscript_catalog/*` | deliberate label variant — **preserved**; guard maps URPS->FPMRS |

**Scope decision:** canonicalized the SET (membership), not the orderings or the
full-name labels. Physically wiring every vector to one ordered constant would change
output row-order in scripts that deliberately order differently (GO-first vs
MFM-first) — a behavior change the audit does not justify. So the refactor wires only
consumers already in canonical order; all others are validated by an order-agnostic
set guard.

**Canonical:** `E2SFCA_SUBSPECIALTIES <- c("MFM","GO","REI","FPMRS","MIGS","PAG","CFP")`
in the shared loader; order = manuscript Table/figure display order (factor-levels
consumers rely on it; set consumers may sort).

**Refactor:** manuscript Rmd `subs7` (line 92) + both factor-`levels` (678, 1129) →
`E2SFCA_SUBSPECIALTIES` (all already in canonical order, loader already sourced).
`DJ7_SUBS` anchor-commented (base-R standalone module, like `DJ7_WC_BASE`).

**Files changed:** `manuscript_e2sfca_values.R` (constant), `...manuscript.Rmd` (×3),
`R/desjardins7_e2sfca.R` (anchor), `tests/testthat/test-ssot-subspecialties.R` (new).

**Guards/tests:** 8-assertion guard — canonical length 7/unique/exact order;
`DJ7_SUBS` == canonical (set + order); no literal 7-code vector remains in the Rmd +
the Rmd references the constant; **repo-wide scan** parses every `c(...)` block and
requires each subspecialty code-vector (>=4 known codes) to be set-equal to the
canonical after mapping URPS->FPMRS (order-agnostic, so alphabetical + catalog
variants pass, real drift fails).

**Tests:** full suite **603 pass / 0 fail** (was 595; +8). 2 pre-existing lm
warnings, unrelated. No behavior change (manuscript order identical).

**Remaining risk:** the full-name label maps (`full_name <- c(GO=..., MFM=...)`) are a
SEPARATE un-canonicalized mapping repeated across 5+ scripts + the Rmd, and they
DISAGREE on casing ("Gynecologic Oncology" vs "gynecologic oncology") and one uses an
EN-DASH ("Maternal–fetal medicine", `map_equity_heatmap.R:27`) — a strong future
candidate (display-label SSOT). The non-canonical code ORDERINGS remain per-site
(guarded by set-equality only).

## Iteration 7 — subspecialty figure/map FULL-NAME label map

**Why high risk:** the code->display-name map appears in 5+ places; three map scripts
held BYTE-IDENTICAL copies, so a one-file relabel would silently desync sibling
figures. One copy also carried an en-dash (a display defect + a standing style-rule
violation).

**Audit — three deliberate label STYLES (only the triplicate consolidated):**

| Style | Where | Treatment |
|---|---|---|
| Title Case, abbreviated ("Gynecologic Oncology", "Minimally Invasive Gyn Surgery") | `map_2sfca_coverage_by_year.R`, `map_allsubspec_allyears_access_surface.R`, `map_fpmrs_allyears_access_surface.R` — **byte-identical** | **CANONICAL** `E2SFCA_SUBSPECIALTY_LABELS`; 3 scripts wired |
| Sentence case, abbreviated ("Gynecologic oncology") | `map_equity_heatmap.R` | preserved as deliberate variant; **en-dash fixed**; anchor-commented |
| Full lowercase, unabbreviated formal names ("reproductive endocrinology and infertility") | manuscript Rmd:208 (single def) | left — deliberate inline-prose style, not a duplicate |

**Discrepancies/adjudication:** the sentence-case heatmap map cannot be mechanically
derived from the canonical (a tolower transform would corrupt the "FPMRS" acronym in
"Urogynecology (FPMRS)"), so it stays literal. The manuscript uses different WORDS
(full formal names), not a casing of the same strings, so it is a separate label set,
not drift. Canonical key-order (E2SFCA_SUBSPECIALTIES order) is behavior-neutral: all
three wired consumers use keyed `full_name[[code]]` lookup.

**Canonical:** `E2SFCA_SUBSPECIALTY_LABELS` (named char[7], keyed by code) in the
shared loader; Title-Case abbreviated figure/legend style, values identical to the
former triplicate.

**Files changed:** `manuscript_e2sfca_values.R` (constant), the 3 map scripts (source
+ reference), `map_equity_heatmap.R` (en-dash -> hyphen + anchor),
`tests/testthat/test-ssot-subspecialty-labels.R` (new).

**Guards/tests:** 16-assertion guard — canonical keyed by the code set, non-empty,
pinned values; **no en/em-dash in the canonical**; the 3 scripts hold no literal
`full_name <- c(` and reference the constant; **repo-wide scan: no subspecialty label
map (any file) contains an en/em-dash** (scoped to `full_name` blocks, so it does not
touch the out-of-scope sprintf figure-title em-dashes). Keyed-lookup behavior
re-verified identical.

**Tests:** full suite **619 pass / 0 fail** (was 603; +16). 2 pre-existing lm
warnings, unrelated.

**Remaining risk:** several figure TITLES use an em-dash in `sprintf("Access to %s —
E2SFCA…")` (`map_*` scripts) — a separate display-string family (not a label map),
still violating the no-em-dash rule; a dedicated dash-sweep candidate. The heatmap
sentence-case + manuscript full-name label sets remain per-context (documented).

## Iteration 8 — equal-area CRS 5070 (largely already canonical)

**Why high risk (in principle):** area/overlap math in the wrong CRS is a SILENT
error (plausible-but-wrong areas). In practice this was found LOW-risk: the canonical
already exists and the core path already uses it.

**Audit — TWO deliberate equal-area CRSs (confirmed the caution, NOT unified):**

| CRS | Where | Role |
|---|---|---|
| **5070** (NAD83 CONUS Albers) | engine `E2SFCA_AREA_CRS`, seam gate, `map_allsubspec`, `map_go`, `run_2sfca` (all already reference the constant) | **CANONICAL** (`E2SFCA_AREA_CRS`, engine, seam-validated) |
| **9311** (NAD83(2011) US National Atlas Equal Area) | `R/calculate_subspecialty_accessibility.R`, `R/create_bivariate_map_access_x_adi.R` | **deliberate alt** for the older subspecialty/bivariate subsystems — preserved |
| `5070` literals | `map_2sfca_coverage_by_year.R` (`CRS5070 <- 5070L`), `desjardins7/06`, `manuscript_catalog/*`, captions | duplicates/standalone/display |

**Adjudication:** the engine header explicitly documents 5070+9311 coexistence, so a
blanket "all equal-area = 5070" unification would be WRONG. Only one literal was
cleanly wirable: `map_2sfca_coverage_by_year.R` sources the engine, so its redundant
`CRS5070 <- 5070L` became `CRS5070 <- E2SFCA_AREA_CRS`. The bare `5070` literals in
standalone catalog/desjardins scripts (no engine source) were left; wiring them would
force heavy sf/terra engine sourcing (over-reach). Captions are display strings.

**Files changed:** `scripts/map_2sfca_coverage_by_year.R` (alias wired),
`tests/testthat/test-ssot-area-crs.R` (new).

**Guards/tests:** 6-assertion guard — `E2SFCA_AREA_CRS` defined exactly once (engine),
== 5070L, no other file re-defines it; coverage map references the constant not the
literal; **drift scan**: every `st_transform()/crs=` EPSG literal across R/scripts is
in the known-good set {4326, 3857, 5070, 9311} (permits BOTH deliberate equal-area
CRSs; fails only on a typo'd/foreign EPSG).

**Tests:** full suite **625 pass / 0 fail** (was 619; +6). 2 pre-existing lm warnings.

**Remaining risk:** bare `5070` literals persist in standalone catalog/desjardins
scripts (guarded by the drift scan, but not wired to the constant). Raster RESOLUTION
(500 vs 1000 m) and conservation TOLERANCES (1e-6 vs 1e-14) were scoped OUT: both have
documented INTENTIONAL variation (the manuscript reports 500 m and 1,000 m as a
sensitivity; tolerances differ by conservation level) and would need per-value
adjudication — separate future candidates, do NOT collapse.

## Iteration 9 — production raster resolution (500 m)

**Why high risk:** the grid resolution sets how demand is rasterised; a production
surface built at the wrong resolution silently disagrees with the frozen run. The
value 500 was hardcoded across two production surface scripts, the seam default, and
figure/manuscript captions, while the engine/CLI DEFAULT is a different number (250).

**Audit — resolutions serve FOUR distinct roles (only production canonicalized):**

| Value | Where | Role |
|---|---|---|
| **500 m** | frozen manifest `resolution_m`; `map_go_2020` `RES<-500`; `map_fpmrs` `RES<-500L`; seam default; captions; manuscript prose | **PRODUCTION** (authority = manifest) |
| 250 m | engine `build_e2sfca_grid_geometry/raster_grid(resolution=250)`; `run_2sfca.R --resolution` default | function/CLI **fallback** — production always overrides (manifest proves 500), left |
| 1000 m | `map_allsubspec_allyears` `E2SFCA_MAP_RES` default (DISPLAY small-multiples, coarsened to ~4 km) | deliberate speed variant — preserved |
| `res500`/1000 m | `sensitivity_e2sfca_2020.R` | labelled sensitivity scenario — preserved |
| `"20m"` | `tigris::states(resolution="20m")` | cartographic map SCALE, unrelated — left |

**Authority resolved (the flagged 250-vs-500 concern):** the frozen manifest records
`resolution_m = 500`, so 500 is authoritative for production; 250 is only a
never-hit fallback default. Confirmed by reading the manifest, not by trusting the
function default.

**Canonical:** `E2SFCA_PRODUCTION_RESOLUTION_M <- 500L` in the shared loader, pinned
to the manifest by a new `stopifnot` in `load_e2sfca_national_summary`
(`as.integer(manifest$resolution_m) == E2SFCA_PRODUCTION_RESOLUTION_M`).

**Refactor:** `map_go_2020_access_surface.R` and `map_fpmrs_allyears_access_surface.R`
`RES` now `<- E2SFCA_PRODUCTION_RESOLUTION_M` (both source the loader; map_go got a
top source, map_fpmrs's redundant later label-source was consolidated to the top).

**Files changed:** `manuscript_e2sfca_values.R` (constant + assertion),
`map_go_2020_access_surface.R`, `map_fpmrs_allyears_access_surface.R`,
`tests/testthat/test-ssot-resolution.R` (new).

**Guards/tests:** 12-assertion guard — constant type/value; constant == manifest
`resolution_m`; **adversarial: a manifest patched to 250 m makes the loader stop**;
production scripts reference the constant not a `RES<-500` literal; the deliberate 250
default + 1000 m display default are asserted still present. Manuscript load chain
re-verified (77 rows) with the new assertion.

**Tests:** full suite **637 pass / 0 fail** (was 625; +12). 2 pre-existing lm warnings.

**Remaining risk:** figure/manuscript CAPTIONS still say "500 m" as display literals
(records; not grid params). The seam-test `--resolution` default "500" is left (it is
the seam's own CLI default; it already matches production). Conservation tolerances
remain a separate candidate.

## Iteration 10 — allocator conservation tolerance (1e-6); most tolerances STOPPED

**Candidate:** conservation tolerances. The audit confirmed the caution — these are
mostly independent thresholds; only ONE was a real drift point.

**Audit — tolerance landscape:**

| Value | Where | Verdict |
|---|---|---|
| **1e-6** allocator tol | engine `allocate_pop_areaweighted(conservation_tol=1e-6)` (default) + restated literal in `run_2sfca.R:468` manifest record | **the one drift point** (fixed) |
| `NATIONAL_CONSERVATION_TOL` 0.005 | `run_2sfca.R:140` env var, used in check + manifest | **already SSOT** (a variable) — left |
| 1e-9, 1e-12, `.Machine$double.eps` | monotonicity/power/division float-guards across engine + seam | independent numerical guards — STOPPED (not unified) |
| seam `TOL_MEAN_REL=0.02`, `TOL_SHARE_ABS=0.01` | prespecified relaunch-gate tolerances | deliberate, already variables — left |
| "1e-14" | `figure_2sfca_national_11yr.R:101` caption | a descriptive claim about achieved conservation (~machine precision), not a configured tolerance — left |

**The drift point:** `run_2sfca.R` recorded `allocator_conservation_tol = 1e-6` as a
literal, independently of the engine's `conservation_tol = 1e-6` default. Both should
be one value.

**HAZARD hit + course-correction (important):** the natural fix — promote the engine
tol to a named constant `E2SFCA_ALLOCATOR_CONSERVATION_TOL` and reference it — was
implemented, then REVERTED. `run_2sfca.R:114-123` computes the **whole-file sha256** of
`R/two_step_floating_catchment.R` and **hard `stop()`s** on mismatch (the
allocator-identity gate, pinned to `11abdec3…`). ANY edit to the engine file (even a
behavior-preserving one) changes that sha and would break the next production run. So
the engine file is effectively immutable without a deliberate re-pin (PI-level
decision).

**Fix actually applied:** engine left pristine; `run_2sfca.R` now records
`allocator_conservation_tol = eval(formals(allocate_pop_areaweighted)$conservation_tol)`
— it reads the engine's LIVE default, so the manifest can never disagree with the
engine, and no engine bytes change. Value recorded is identical (1e-6).

**Files changed:** `scripts/run_2sfca.R` (record from formals),
`tests/testthat/test-ssot-allocator-conservation-tol.R` (new). **Engine reverted to
pristine** (git checkout) — sha gate intact.

**Guards/tests:** 9-assertion guard — engine default is the single 1e-6 tol shared by
both allocator entry points; producer records it via `formals()` not a literal;
allocator tol stays DISTINCT from the national 0.005 tol (guards against a future
mistaken unification).

**Tests:** full suite **646 pass / 0 fail** (was 637; +9). 2 pre-existing lm warnings.

**Remaining risk:** the "1e-14" caption is a loose descriptive claim (not tied to any
tolerance); left as display. The engine file being sha-gated means future SSOT work
that would touch `R/two_step_floating_catchment.R` must either read-from (formals /
existing exported constants) or be deferred to a deliberate engine re-pin.

**Lesson for the loop:** `R/two_step_floating_catchment.R` is SHA-GATED by
`run_2sfca.R` — never edit it for an SSOT tidy; read from its exports/defaults instead.

## Iteration 11 — figure display em-dashes (standing style rule)

**Why high risk:** the project has a STANDING, emphatic rule banning em-dashes (—) and
en-dashes (–) in user-facing text; several figure titles/subtitles rendered into
PUBLISHED figures still used ` — `, so every regenerated figure reproduced the
violation. This is the one SSOT-style pattern that reaches the reader directly.

**Audit:** 25 files contain em-dashes (0 en-dashes), but almost all are code comments
(pre-existing, not user-facing figure text). Scoped tightly to FIGURE DISPLAY strings:

| File:line | Display string (before) | Fix |
|---|---|---|
| `map_allsubspec_allyears:142` | `"Access to %s — E2SFCA, 2013-2023"` (title) | ` - ` |
| `map_fpmrs_allyears:125` | `"Access to %s — E2SFCA, 2013-2023"` (title) | ` - ` |
| `map_go_2020:88` | `"Access to Gynecologic Oncologists — E2SFCA, 2020"` (title) | ` - ` |
| `stratify_go_2020:131` | `"...race/ethnicity — E2SFCA, 2020 (CONUS)"` (title) | ` - ` |
| `stratify_allyears:142` | `"...2013-2023 — E2SFCA (CONUS)"` (title) | ` - ` |
| `stratify_allyears:192` | `"Access deserts by subspecialty — E2SFCA..."` (title) | ` - ` |
| `stratify_go_allyears:114` | `"...2013-2023 — E2SFCA (CONUS)"` (title) | ` - ` |
| `figure_2sfca_national_11yr:67` | `"...per 100,000 women — a %.0f-fold spread..."` (subtitle) | `, a` |

**Adjudication / scope:** fixed the 8 figure TITLE/SUBTITLE display strings only.
Deliberately OUT of scope (documented, not bundled): console-log strings
(`say()/cat()/message()/stop()` with em-dashes, e.g. `map_allsubspec:123,157`,
`stratify_allyears:203`, `seam_test:99`, `ec2_install:38`) and the ~24 files' code
COMMENT em-dashes — both are large, lower-priority sweeps. The sha-gated engine
`R/two_step_floating_catchment.R` is never edited.

**Files changed:** 6 figure/map/stratify scripts (8 strings),
`tests/testthat/test-ssot-figure-dashes.R` (new).

**Guards/tests:** guard scans `scripts/**.R` display-function lines
(labs/ggtitle/title/subtitle/caption/annotate/plot_annotation/mk_map, non-comment) and
fails on any en/em-dash — covers exactly the figure surface, ignores logs + comments.

**Tests:** full suite **647 pass / 0 fail** (was 646; +1). 2 pre-existing lm warnings.

**Remaining risk:** console-log + code-comment em-dashes persist (separate candidate);
the manuscript Rmd prose is already dash-free (post-render HTML sweep in `render.R`).

## Iteration 12 — seam method vocabulary (`SEAM_METHODS`)

**Why high risk:** `seam_test_2sfca.R` is the relaunch-gate runner; it held the
four-method allocation vocabulary as TWO byte-identical vectors — `EXPECTED_METHODS`
(line 64, run-contract validation) and `METHOD_ORDER` (line 335, output row order). A
5th method added to one but not the other would validate against one list while
ordering output by another.

**Audit:** `EXPECTED_METHODS` == `METHOD_ORDER` ==
`c("raw","equal_total","mass_conserving","mass_conserving_eqtot")` (same set AND
order). `geometry_only` is only a REPORTING LABEL for `mass_conserving_eqtot`, not a
5th vector member. `by_method$<name>` accesses (357-360, 378-406) are keyed, so
order-independent. `ALL7` (line 56) is the subspecialty set (iter 6), not this
candidate.

**Adjudication:** the two vectors are a true duplicate → consolidated into one
`SEAM_METHODS`, defined once near the run contract; `EXPECTED_METHODS <- SEAM_METHODS`
and `METHOD_ORDER <- SEAM_METHODS`. Order preserved (reporting order); behavior
identical. mass_conserving (production, == E2SFCA_ALLOCATOR_METHOD_ID) and
mass_conserving_eqtot (total-fixed gate-basis diagnostic) kept as DISTINCT members.
The seam script is NOT sha-gated (only the engine is), so a within-file, behavior-
neutral edit is safe.

**Files changed:** `scripts/seam_test_2sfca.R` (SEAM_METHODS + 2 derivations),
`tests/testthat/test-ssot-seam-methods.R` (new),
`tests/testthat/test-ssot-allocator-method-id.R` (updated — see regression below).

**Regression caught + fixed:** the iter-5 test parsed `EXPECTED_METHODS`'s quoted
tokens for the method vocabulary; after consolidation that line is
`EXPECTED_METHODS <- SEAM_METHODS` (no literals), so the vocabulary parse returned
empty and the membership assertion failed. Fixed by repointing the parse at
`SEAM_METHODS` (the new canonical literal). Rionale: the vocabulary MOVED, so its
guard should read the new home.

**Guards/tests:** new 11-assertion guard (parses the file — the gate runner can't be
sourced) — SEAM_METHODS is the 4 methods in order; EXPECTED_METHODS + METHOD_ORDER
derive from it (no residual `<- c(` literal); production + gate-basis methods present
and distinct; production method == E2SFCA_ALLOCATOR_METHOD_ID (cross-tie to iter 5);
every `by_method$<name>` access is a canonical method.

**Tests:** full suite **658 pass / 0 fail** (was 647; +11 net: +11 new seam, iter-5
test repointed). 2 pre-existing lm warnings.

**Remaining risk:** `THRESHOLDS <- E2SFCA_DEFAULT_THRESHOLDS` (engine) is restated as a
literal `c(0,1,5,10,20,50)` in the seam run-contract assertion (line 75) — a small
future candidate (engine already SSOT; the assertion could read the constant).

## Iteration 13 — access thresholds `c(0,1,5,10,20,50)` (verified already-SSOT)

**Why examined:** the per-100k access cut points define the frozen summary's
`share_ge_<k>` columns; a drifted copy would mislabel access tiers.

**Audit — already fully SSOT (no refactor needed):**

| File:line | Value | Verdict |
|---|---|---|
| `R/two_step_floating_catchment.R:893` | `E2SFCA_DEFAULT_THRESHOLDS <- c(0,1,5,10,20,50)` | **CANONICAL** (engine, defined once) |
| engine fns 924/1005, `seam_test:62`, `map_go:53`, `map_fpmrs:84`, `map_allsubspec:107` | `= E2SFCA_DEFAULT_THRESHOLDS` | already reference the constant |
| `seam_test_2sfca.R:80` | `identical(THRESHOLDS, c(0,1,5,10,20,50))` | **deliberate prespecified LOCK** — preserved |
| frozen CSV `share_ge_0/1/5/10/20/50` | column names | derived from thresholds (no code literal) |

**Adjudication:** the sole literal restatement (`seam_test:80`) is an INTENTIONAL
prespecified-value lock (seam header: "fixed BEFORE any national result was examined;
DO NOT tune"). It cross-checks the engine default against an independent literal so an
engine-default change fails loudly. Collapsing it to reference the constant would make
it a tautology and destroy the guard — so it is preserved, not refactored. No code
change this iteration (the value is already single-sourced).

**Files changed:** `tests/testthat/test-ssot-access-thresholds.R` (new) only.

**Guards/tests:** 10-assertion guard — canonical value + monotonic + single engine
definition; all four consumers reference the constant; the seam prespecified-lock
literal still matches the constant (so divergence is caught at TEST time too, not only
at seam runtime); the frozen CSV `share_ge_<k>` suffixes exactly equal the thresholds
(ties the artifact to the constant).

**Tests:** full suite **668 pass / 0 fail** (was 658; +10). 2 pre-existing lm warnings.

**Remaining risk:** none for thresholds. Note the pattern: several "prespecified
locks" in `seam_test_2sfca.R` (thresholds, `TOL_MEAN_REL`, `TOL_SHARE_ABS`) are
intentional independent restatements and must NOT be SSOT-collapsed.

## Iteration 14 — subspecialty workforce sizes (7 counts)

**Why high risk:** these are HEADLINE manuscript numbers (Table 1 + the Results
"workforce comprised ..." sentence). The seven counts (MFM 1244, GO 890, REI 848,
FPMRS 783, MIGS 372, PAG 113, CFP 72) lived in a HAND-STAGED
`manuscript/data/workforce_counts_2020.csv` with the accessor only checking
`nrow==7, >0` — NO tie to the frozen run. A CSV staged from a different run or
hand-edited would silently mis-state the workforce.

**Audit / key finding:** the manuscript PROSE side is already SSOT (every count via
`spec_wk(<code>)`, total via `sum(workforce_tbl$n_providers)`; no hardcoded numbers).
The gap was the CSV<->run tie. Proved the counts are EXACTLY derivable from the frozen
national summary by the conservation property:
`n = round(mean_pop_weighted_per100k * acs_pop_source / 1e5)` — all 7 match (max
pre-round diff 0.21, post-round 0).

**Canonical / hardening:** added `e2sfca_workforce_from_run(national_tbl)` (independent
second-method derivation) and gave `e2sfca_workforce_counts()` an optional
`national_tbl=` arg that CROSS-CHECKS the staged CSV against the run-derived counts,
failing loudly on any |diff|>1. Wired the manuscript render to pass `national_tbl`, so
every knit now validates the CSV against the frozen run.

**Files changed:** `scripts/manuscript_e2sfca_values.R` (derivation + cross-check),
`manuscript/e2sfca_accessibility_manuscript.Rmd` (pass national_tbl),
`tests/testthat/test-ssot-workforce-sizes.R` (new).

**Guards/tests:** run-derived == staged CSV; the accessor cross-check passes on the
real CSV; **adversarial: a CSV perturbed by +100 makes the accessor stop**; the
manuscript reads every count via `spec_wk()` (no hardcoded literals). Full suite
**686 pass / 0 fail** (was 668; +18).

**Remaining risk:** the CSV is still a staged file (not regenerated live), but it can
no longer drift undetected from the run. A future step could drop the CSV entirely and
derive in-Rmd.

## Iteration 15 — CONUS state FIPS vector (`conus()` copy-pasted x12)

**Why high risk:** the `conus()`/`conus_states()` helper (49 FIPS = 48 states + DC) was
copy-pasted byte-identically in 12 analysis scripts; a one-file edit would silently
change the study's geographic scope.

**Audit:** all 12 identical: `sprintf("%02d", c(1,4:6,8:13,16:42,44:51,53:56))` — 49
codes; excludes AK(02), HI(15), territories(60,66,69,72,78); includes DC(11).

**Canonical:** `CONUS_STATE_FIPS` in the loader (49-element char vector).

**Refactor (safe subset wired):** `conus()` is a function (lazy-eval), so wiring is safe
only where the loader is sourced before the first `conus()` CALL. Verified 4 such
scripts (map_allsubspec, stratify_go_2020, map_go_2020, map_fpmrs) -> `conus <-
function() CONUS_STATE_FIPS`. The other 8 call conus() before their loader source
(map_2sfca_coverage) or don't source the loader (run_2sfca, seam_test, prefetch,
inferential, sensitivity, stratify_allyears, stratify_go_allyears) -> SSOT-anchor
comment, literal retained. Sha-gated engine untouched.

**Files changed:** `manuscript_e2sfca_values.R` (constant) + 12 scripts (4 wired, 8
anchored) + `tests/testthat/test-ssot-conus-fips.R` (new).

**Guards/tests:** 21-assertion guard — 49 codes, exact set, AK/HI/territories excluded,
DC included; the 4 wired scripts reference the constant; **every remaining
conus/conus_states literal parses to a set equal to the canonical** (drift guard on the
8 anchored copies). Full suite **707 pass / 0 fail** (was 686; +21).

**Remaining risk:** 8 anchored literals persist (guarded against drift). NEXT (item C):
derive the non-CONUS exclusion list as the COMPLEMENT of CONUS_STATE_FIPS.

## Iteration 16 — non-CONUS FIPS (B skipped: PFD not present)

**(B) PFD prevalence — NOT PRESENT in twostep.** No PFD/pelvic-floor prevalence rate
exists here; twostep's demand denominator is total female population (ACS B01001_026),
not a prevalence-adjusted at-risk population (that demand-side modeling lives in the
isochrones/URPS work). Recorded and skipped.

**(C) Non-CONUS FIPS — DONE.** Canonical `NON_CONUS_FIPS` in the loader, DERIVED as
`setdiff(US_STATE_TERRITORY_FIPS, CONUS_STATE_FIPS)` (AK, HI + 5 territories = 7 codes)
so it can never drift from the CONUS inclusion set. Anchored the 6 consumer literals
(parameter_stability NONCONUS + 5 catalog scripts + an R/ fallback, guarded).
Guard `test-ssot-nonconus-fips.R`: derivation == expected 7; CONUS/non-CONUS disjoint
and their union == the 56-code universe; every non-CONUS literal in the repo equals the
canonical. Full suite **723 pass / 0 fail**.

**COORDINATION INCIDENT (shared worktree):** a PARALLEL window did queue items F
(primary access band, `PRIMARY_ACCESS_BAND_MIN/SEC` in R/contour_bands.R), G
(`TRACT_REACHED_COVERAGE_PCT` in R/access_thresholds.R), and a denominator-category
SSOT (`DENOMINATOR_CATEGORY` in R/access_categories.R) + `test-ssot-access-constants.R`
— all as UNTRACKED files, intact. While fixing a parse error in my non-CONUS edit I ran
`git checkout` on the 5 manuscript_catalog scripts, which REVERTED that parallel
window's F/G catalog wiring (restored `BAND <- 3600L` / `range == 3600L` /
`category == "total_female"`). I re-applied the wiring to match the parallel test's
contract (`BAND <- PRIMARY_ACCESS_BAND_SEC`, `range == PRIMARY_ACCESS_BAND_SEC`,
`category == DENOMINATOR_CATEGORY`, sourcing the modules); suite green again. LESSON:
NEVER `git checkout` shared files in this tree — another window edits it (memory:
"commit-first, stage only own files"). F and G are therefore effectively DONE (by the
other window); do NOT re-audit them.

## twostep -> mufflyaccess package lane (2026-07-25)

The shared SSOTs now live in the `mufflyaccess` package (v0.1.2/0.1.3); twostep's
local F/G modules were migrated to depend on it:
- `R/access_categories.R`, `R/access_thresholds.R` -- already full shims (parallel window).
- `R/contour_bands.R` -- **migrated here**: shared band SSOTs (CANONICAL_BANDS,
  PRIMARY_ACCESS_BAND_MIN/SEC, get_canonical_bands, get_primary_access_band) now load
  from the package; the twostep-specific `ACTIVE_BANDS_FALLBACK` + `get_active_bands()`
  (read `config/isochrone_config.yaml`, NOT in the package) kept local. Partial shim.
- `DESCRIPTION`: recorded the dependency (`Imports: mufflyaccess`,
  `Remotes: mufflyt/mufflyaccess@v0.1.2`) so twostep stays reproducible.
- Full twostep suite: **726 pass / 0 fail**.

**Geography duplication RESOLVED (2026-07-25):** `scripts/manuscript_e2sfca_values.R`
now RE-EXPORTS geography from the package: `CONUS_STATE_FIPS <- mufflyaccess::CONUS_STATE_FIPS`,
`NON_CONUS_FIPS <- mufflyaccess::NON_CONTIGUOUS_FIPS`, and `US_STATE_TERRITORY_FIPS`
derived as their union. Values are identical, so the conus/nonconus guards pass
unchanged (21/0 + 7/0); full suite 726/0. There is now ONE geography source (the
package).

**ACS denominator duplication RESOLVED (2026-07-25):** `E2SFCA_ACS_FEMALE_POP_2020`
re-exports from `mufflyaccess::ACS2020_CONUS_FEMALE_POP` via `as.integer()` (strips the
package provenance attrs to keep the plain-integer form figures + the guard expect).
Value identical (164690617); the guard's static scan now asserts the literal appears in
NO twostep code file (it lives only in the package). Full suite 726/0. twostep now
sources ALL shared SSOTs from the package (bands, categories, thresholds, geography, ACS
denominator); only E2SFCA-manuscript-specific constants (run_id, allocator,
subspecialties, labels, resolution, workforce) remain twostep-local.

## Candidates queued (user priority, 2026-07-25)
1. **CONUS state FIPS vector** — **DONE iter 15** (`CONUS_STATE_FIPS`).
   - **DONE iter 16:** (B) PFD not present; (C) `NON_CONUS_FIPS` derived + guarded.
   - **(F) primary band + (G) 50% cut: DONE by a PARALLEL window** (R/contour_bands.R,
     R/access_thresholds.R, R/access_categories.R + test-ssot-access-constants.R).
   - **(D) other-year ACS female pop + (E) RUCA metro/rural breakpoint: still open.**
2. **PFD (pelvic floor disorder) prevalence** — clinical prevalence constant(s).
3. **Non-contiguous / non-CONUS FIPS** (02,15,72,78,66,69,60) — ~7 files; must stay the
   exact complement of the CONUS set.
4. **National ACS female population** — 2020 done (iter 4, `E2SFCA_ACS_FEMALE_POP_2020`);
   audit any other-year / non-2020 national female-pop literals.
5. **RUCA metro/rural breakpoint** (Metropolitan = RUCA 1-3).
6. **Primary access band 60 min / 3600 s** — the 60-minute primary catchment (and its
   seconds form 3600) used as the headline band.
7. **Tract-reached 50% cut** — the 50% coverage cut defining a tract as "reached".

## Other candidates noted for later
- **Console-log / message em-dashes** and code-comment em-dashes — a broader style sweep.
- Subspecialty code ORDERINGS (MFM-first vs GO-first vs alphabetical) — only unify if
  the audit proves a site's order is unintentional.
