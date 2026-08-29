# twostep (development version)

## Dropped supply: a silent defect in the age-matched sensitivity analysis

The age-matched runner was configured `unmatched_supply_policy = "drop"` and was
pointed at an isochrone directory that is **not** the frozen set the primary
analysis used. A provider whose catchment was missing therefore did not raise an
error -- that provider's supply left the numerator and the run completed, giving
a complete-looking result computed on less supply than the study population had.

- **12 of 14 cells were affected, 68 origins lost.** Every affected cell
  *understated* access, because supply was only ever removed. Worst was PAG at
  3.54%, from losing two origins out of ninety-five; small denominators make
  small losses loud. FPMRS lost fifteen of 580 for 2.17%.
- **It changed a claim, not just a level.** The C5 ordering read
  `MFM > REI > GO > FPMRS > MIGS > PAG > CFP` under the contaminated data and
  `MFM > REI > GO > FPMRS > PAG > MIGS > CFP` corrected -- MIGS and PAG exchange
  rank on a margin the loss manufactured. C2 (max rural:metropolitan 0.5329) and
  C3 (max AIAN:White 0.9567) were unaffected.
- The runner now sets `unmatched_supply_policy = "error"`. This one change would
  have prevented the entire episode and costs nothing when the inputs are right.
- New `tools/ci/check_supply_conservation.R` is the artifact-level backstop:
  every committed cell must satisfy `n_iso_origins == n_supply_origins`. It is
  independent of the hash gate by design, so it catches supply loss from causes a
  hash cannot see. On its first run it found the twelve failing cells.
- The contaminated 2020 artifact is preserved at
  `artifacts/multiverse/_precorrection/age_matched_results_CONTAMINATED_2020.csv`.
  The appendix paragraph describing the defect had been computing it from the
  *corrected* file and printing a 0.000% shortfall from 0 lost origins -- an
  account of the contamination written from data in which it had been repaired.

## Age-matched denominators: the full 2013-2023 panel

The age-matched sensitivity analysis covered 2020 only, which is why it could not
be promoted without deleting the paper's temporal arm.

- `artifacts/2sfca/agematched_panel/age_matched_panel.csv` now carries all
  **154 cells** (7 subspecialties x 11 years x 2 regimes), computed on the frozen
  environment with **0 dropped origins**, with its own `provenance.json` recording
  manifest, runner, engine and per-year input hashes.
- Two ACS tract vintages, not eleven: 2013-2019 share the 2010 tract set (72,538)
  and 2020-2023 the 2020 set (83,776), verified by querying GEOIDs year by year.
- **Connecticut breaks at exactly ACS 2022** (`09001...` to `09110...` planning
  regions). Unhandled, 2022-2023 lose all 884 CT tracts while the national join
  still reads 98.9% complete. `relabel_ct_geoids_safe()` runs fail-closed for
  `YEAR >= 2022`.
- The RUCA crosswalk was wrong, and was caught only by insisting the parameterised
  runner reproduce 2020 byte-for-byte. Two RUCA files share an **identical row
  count of 85,528** with different hashes. A row-count check would have passed the
  wrong one.
- New `tools/ci/check_panel_invariants.R` (10 invariants, each negative-tested) and
  `tools/ci/check_denominator_identity.R`, which reconstructs denominators from the
  ACS table definitions and the declared age window rather than from the manifest's
  own band lists -- 231 tract-vector identities exact across 11 vintages.
- New `tools/ci/check_agematched_ssot.R` fails if any live consumer reads the
  standalone 2020 file instead of the panel. The two are byte-identical today, so a
  consumer pointed at the wrong one produces correct numbers and no symptom.

## Frozen isochrones served by hash, not by path

Documented in full in
[`docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md`](docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md).

- `inst/multiverse/frozen_isochrones.sha256` pins the four bands of the set the
  primary analysis was computed against (run `e2sfca_20260712_190734`, 4,050
  origins). Nine isochrone directories exist across the author's machines and
  **none of the local ones matches**; the wrong one carries 3,909 origins and is
  missing 44 physician locations. Nothing about a path distinguishes them.
- `tools/ci/check_frozen_isochrones.sh` verifies by hash before any year runs, so
  the wrong set costs seconds rather than a twelve-hour run and a retraction.
- `mufflyaccess` (>= 0.10.0) serves the set and the ABOG refresh roster as an SSOT
  with canonical S3 and Dropbox copies. `E2SFCA_ISO_DIR` still works but is now
  **verified rather than trusted** -- the old contract was "tell me where it is and
  I will believe you," which is how the wrong set got used.

## One command for a freeze decision

- New `tools/ci/release_audit.sh` runs **every gate** in one pass and prints a
  single verdict (20 at the time of writing). The nightly and PR workflows each run a subset split across jobs
  for parallelism; correct for CI, insufficient for a freeze, which otherwise means
  reconciling four workflow runs by hand. It does not stop on first failure --
  learning nineteen failures one at a time is how a freeze slips a day.
- New `tools/ci/check_workflow_syntax.R` parses the 114 bash blocks in the
  workflows; an unterminated quote in an `echo` had shipped and failed at run time.
- New `tools/ci/check_launcher_heredoc.R` catches `$VAR` interpolation inside
  unquoted heredocs, which `bash -n` cannot see. An R accessor `ref$variant` had
  been eaten by the shell and surfaced as `variant: unbound variable` on EC2.
- New `tools/ci/check_documented_shortfalls.R` recomputes every supply-loss figure
  quoted in prose from `age_matched_correction_diff.csv`. Written because three
  hand-typed numbers were wrong at once, none of them catchable by rereading the
  text: each sentence was internally plausible. It keeps proportional origin loss
  and effect-on-the-mean as separate vectors, because conflating them is the error
  it exists to catch -- FPMRS lost the largest share of origins (2.59%), PAG had
  the largest effect on a reported mean (3.54%), and NEWS had named PAG for both.
  It also refuses the alternative convention (dividing by the contaminated value,
  which gives 3.67%) anywhere it appears without naming its denominator.
- `tools/ci/check_readme.R` now pins the release audit's gate count against
  `release_audit.sh` itself. "all 19 gates" appeared in three places and survived
  the twentieth gate being added.

## The mirrors were real; the check that said so could not have known

The frozen isochrones and the ABOG registry are mirrored to S3 and Dropbox, both
recorded in `mufflyaccess`'s `ssot_sources.json`. The script that uploaded them
verified with `rclone hashsum sha256 dropbox:...`.

**Dropbox does not expose SHA-256.** It supports exactly one algorithm, its own
content hash, so every hashsum came back empty, every comparison failed, and the
run's own log ends in five consecutive `MISMATCH` lines -- while `ssot_sources.json`
recorded Dropbox as canonical anyway.

- The mirrors are in fact correct, confirmed 2026-08-29: **4 matching files, 0
  differences** on the frozen isochrones by content hash, and the S3 copy of
  `refresh_merged.csv` matches its recorded sha256 (79,398 rows).
- The verification was **structurally incapable of passing**. That is worse than
  no check, because it trains the reader to treat the output as noise -- the same
  shape as `unmatched_supply_policy = "drop"` reporting success on a run that had
  lost supply. One check lied by staying silent, the other by crying wolf.
- `scripts/dbx_upload_ssot.sh` recovers that script from `/tmp`, where it lived
  and would have been lost, and replaces the verification with `rclone check`,
  which negotiates a hash both ends support. It refuses to mirror a local
  directory that does not pass the hash gate first, and it distinguishes "the
  mirror disagrees" from "I could not read the local file" -- a distinction its
  predecessor collapsed.


## Geography is identified by hash, not by path

The age-matched panel ran against an isochrone set carrying **3,909** provider origins
where the frozen set carries **4,050**. `run_age_matched.R` was passing
`unmatched_supply_policy = "drop"`, so a provider whose catchment was missing had their
supply discarded rather than raising an error. Which of the 141 missing origins mattered
depended on the cell, because each subspecialty has its own provider set: five of them
were ones the gynecologic-oncology cell needed -- 7 of its 890 supply units, 0.787% --
which put that cell 0.786% below the frozen value while the run reported success.

The committed 2020 artifact had dropped supply in **12 of 14 cells** — 68 origins.
The largest proportional loss of origins was FPMRS, 15 of 580 (2.59%); the largest
effect on a reported mean was PAG, 3.54%, from losing only 2 of 95. Those are different
quantities and they rank differently — a small provider set converts a small loss into a
large shortfall, which is why PAG moves most while FPMRS loses most. The loss was
recorded the entire time in `n_supply_origins` and `n_iso_origins`.
Nothing compared them.

Three defences, because any one of them alone leaves the others open:

- `run_age_matched.R` now passes `unmatched_supply_policy = "error"`. The engine names
  the offending `coord_id`s and the supply share they carry, rather than returning a
  plausible number.
- `tools/ci/check_frozen_isochrones.sh` verifies the four band files against
  `inst/multiverse/frozen_isochrones.sha256` and refuses to proceed otherwise.
  `run_panel.sh` runs it **before the first year**, since ten years by fourteen cells
  against a wrong set would reproduce the defect silently, year after year.
- `tools/ci/check_supply_conservation.R` requires `n_supply_origins == n_iso_origins`
  in any results table that records them, whatever produced it.

Nine isochrone directories existed across this machine and an attached drive. **None**
matched the frozen hashes — two were byte-identical to each other and both were the
3,909-origin set. The frozen set was recovered from
`s3://tyler-valhalla-tiles/seam_run/inputs/isochrones/`. This is why the pin is a hash
and not a path: repointing `run_panel.sh` at a different directory would have fixed
that day's wrong path and left the failure mode intact.

Scientific effect: C2 (rural/metro) and C3 (AIAN/White) hold. The subspecialty ordering
does not — PAG and MIGS exchange rank, because the pre-correction margin of +0.000613
was manufactured by the dropped supply; corrected it is −0.008705 in the opposite
direction. CFP, which lost no origins, is unchanged. Full comparison of all 136
manuscript-facing quantities in `artifacts/multiverse/age_matched_correction_diff.csv`;
background in `docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md`.

## The results path is an output, not an input

`scripts/ec2_run_age_matched.sh` required `artifacts/multiverse/age_matched_results.csv`
in its preflight, shipped it in the uploaded input bundle, and required it again on the
instance. `run_year 2020` writes that same path, so the shipped copy was only ever a
placeholder waiting to be overwritten — and a corrected local artifact was silently
reverted by the input bundle at one point. Removed from all three input sites. The gate
still reads the path, but reads what the instance just computed, and compares against
frozen `sensitivity_2020.csv`.

## Scientific validity: fail closed on ambiguous data

A scientific join doctrine now governs every path that consumes scientific keys:
**no silent loss, no silent multiplication, no silent zeroing.** An unmatched
tract, provider, or year is an error naming what joined to what, how many keys
failed, and representative offending IDs -- not a quietly dropped row.

- `compute_e2sfca()` gains `na_pop_policy = c("error", "zero")`. `NA` population
  is UNKNOWN, not zero; coercing it drops real people from the Step 1
  denominator and **inflates** accessibility. The historical zero-fill is still
  available but must be named.
- `attach_e2sfca_population()` gains the same parameter. It previously
  zero-filled every grid tract missing from `pop_vals`, so a tract set and a
  population table that disagreed produced a complete-looking raster surface
  with a hole in the demand denominator.
- `dj7_no_access_share()` previously dropped tracts that had a measured access
  value but no demand weight, silently changing the population denominator of
  the reported no-access share.
- `dj7_tract_access()` fails closed on tracts missing from `dvec` and origins
  missing from `Rj`.
- Duplicate scientific keys are refused wherever a lookup would otherwise keep
  one row and discard the rest, which made results depend on row order.

Two real defects were found this way: a duplicate tract row inflated demand
(understating access) and a duplicate supply row **doubled** access. Neither was
reachable from the frozen run, which reports `pop_excluded_missing_pop = 0`
across all 77 rows.

## Scientific-core coverage

- New `tools/ci/scientific_coverage.R` asks a yes/no question per export -- does
  any test call this? -- rather than reporting a percentage. A headline coverage
  number stays high while an individual exported function is called by nothing.
- It found **ten scientific-core exports with zero test contact**: seven `dj7_`
  helpers and three raster-grid builders (`build_e2sfca_grid_geometry()`,
  `prepare_e2sfca_iso()`, `attach_e2sfca_population()`), confirmed independently
  by `covr` at 0% executed lines. Core coverage went 23/33 to 33/33 exercised.
  Both `dj7_no_access_share()` and `attach_e2sfca_population()` defects above
  were hiding behind that gap.
- Exports are tiered CORE / SUPPORT / OTHER by hand, because what counts as
  scientific core is a judgement about the study rather than a naming
  convention. Only CORE is fatal.

## Manuscript integrity

- Verbal quantifiers in the paper are now asserted at render time. Numbers are
  inline R against the frozen run and cannot go stale; the words around them
  could. "About one in five", "more than twice", "about six times" are checked
  against the values they describe, and a contradiction **fails the render**.
  All four claims are currently true; this pins them rather than fixing them.


## Manuscript and data
- Table 1 headline moved from 2020 to **2022** (the most recent non-right-censored
  year). 2022 provider counts and standardized supply are re-derived from the frozen
  E2SFCA national summary via the conservation identity and staged in
  `manuscript/data/workforce_counts_2022.csv` (cross-checked against the frozen run,
  0/7 disagreement; `SHA256SUMS.txt` and `docs/DATA_PROVENANCE.md` updated). Supply
  header is now "Supply per 100,000 women (all ages)".
- Subspecialty terminology changed from "female pelvic medicine and reconstructive
  surgery (FPMRS)" to **"urogynecology and reconstructive pelvic surgery (URPS)"**
  in all display text and table/figure labels; the internal `FPMRS` code key (SSOT
  set) is unchanged, so no data joins move.
- Added the true **2022 ACS 5-year** citation (`@Census2023ACS`, ACS 2018-2022,
  Table B01001) and repointed the "2022 American Community Survey" data statement to
  it (the general ACS methods reference stays `@Census2021ACS`).
- README now names the four analysis years explicitly and documents the
  `mufflyaccess` URPS contract (1,306 national / 1,303 CONUS, 2023).
- Main text trimmed to under 3,000 words and the Methods rewritten in plain language
  for a clinical audience: E2SFCA is explained conceptually first, and the technical
  parameterization (distance-decay weights, Gaussian variant, conservation algebra,
  grid CRS) moved to eMethods S4. No analytical numbers, tables, or figures changed.
- **Figure 1 (`fig0_level2020.jpg`) regenerated (2026-08-02)** to remove the in-image
  title, subtitle, and footnote caption and to simplify the colorbar label; content
  unchanged (still the 2020 surface; panel numbers remain the national
  population-weighted means).
- **Figure 3 replaced (2026-08-02):** the GO-only `fig3_go2020.jpg` gave way to
  `fig3_allsubspec_stratified_2020.jpg`, which shows 2020 accessibility by rurality
  (A) and race/ethnicity (B) for **all seven subspecialties**. New twostep-native
  generator `scripts/figure3_allsubspec_stratified_2020.R` reads the vendored
  `allsubspec_allyears_stratified_LONG.csv` (the series behind Figures 4 to 6), so it
  regenerates from twostep alone. Verified from the data: rural < metropolitan and
  American Indian or Alaska Native lowest in every subspecialty.

## Figure provenance
- Added [`docs/FIGURE_PROVENANCE.md`](docs/FIGURE_PROVENANCE.md) and
  [`manuscript/figures/FIGURE_PROVENANCE.csv`](manuscript/figures/FIGURE_PROVENANCE.csv):
  for every figure, the generator script (isochrones, with the three vendored copies
  flagged), the intermediate output, the data input, the build date, and a sha256.
  Cross-linked from the README, `docs/DATA_PROVENANCE.md`, and a comment above each
  figure chunk plus the Rmd reproducibility record. Documents that filenames do not
  track figure numbers (e.g. Figure 5 is `fig4_gotrends.jpg`).

## Not yet done, require the production spatial pipeline, not documentation
- **Figure 1 is still the 2020 access surface**; its validated 2022 regeneration is
  pending a production-pipeline run and it is not described as 2022.
- Table 2 and Figures 3-6 (detailed disparity analysis) remain 2020 and are labeled
  as such.

# twostep 0.1.0

Standalone analysis and manuscript for national travel-time accessibility to the
seven ABOG-certified obstetric and gynecologic subspecialties (E2SFCA on
road-network isochrones, 2013-2023), extracted from the isochrones pipeline so the
paper builds and reproduces on its own.

## Analysis and manuscript
- Enhanced two-step floating catchment area (E2SFCA) engine
  (`R/two_step_floating_catchment.R`, SHA-gated), mass-conserving area-weighted
  demand allocation on a 500 m EPSG:5070 grid, and a Spatial Access Ratio (SPAR).
- Fully reproducible manuscript (`render.R` -> self-contained HTML/DOCX) reading a
  frozen, checksummed subset of the production run `e2sfca_20260712_190734`.
- Live-computed values via `scripts/manuscript_e2sfca_values.R`; primary temporal
  change reported for 2013-2022 (2023 is right-censored and reported provisionally).

## Single source of truth (mufflyaccess)
- Shared band/geography/denominator constants and the disparity statistics are
  sourced live from the public, pinned `mufflyaccess` package (Imports; `renv.lock`
  pins `mufflyt/mufflyaccess@0.10.0`); the 2023 URPS workforce cross-reference in
  the manuscript is pulled via `mufflyaccess::urps_count()`, never hardcoded.

## Reproducibility and integrity guards
- `render.R` verifies `SHA256SUMS.txt` for all consumed artifacts before rendering.
- `e2sfca_reconcile_disparity_artifacts()` reconciles the disparity/coverage
  artifacts against the frozen national summary (wrong-source tripwire).
- `scripts/manuscript_trend_hac.R` is the in-repo producer for the frozen HAC trend
  artifact (verified to reproduce it exactly; adds `sandwich`/`lmtest`).
- Non-normative-access-language guard (`R/access_language.R`) forbids
  shortage/adequacy labels on the modeled accessibility index.
- 25 test files (765 checks), inline fixtures only.

## E2SFCA Access Explorer (Shiny)
- `inst/shiny/access_explorer/` (`twostep::run_access_explorer()`): a separate app
  from the isochrones coverage maps, disparities, sensitivity, temporal, and a
  provenance tab reading the frozen artifacts; verifiable provenance emitted as
  `PROVENANCE.md` / `provenance.json` / `provenance.txt` (SHA256SUMS format).

## Governance
- One-direction cross-repo dependency contract (`docs/REPO_CHARTERS.md`,
  `docs/data-ownership.md`): isochrones builds the roster, mufflyaccess certifies
  the number, twostep measures access, cliff projects the future.
