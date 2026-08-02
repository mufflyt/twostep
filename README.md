# twostep — E2SFCA accessibility to OB/GYN subspecialists

Standalone analysis and manuscript for **national travel-time accessibility to the
seven ABOG-certified obstetric and gynecologic subspecialties** across the
contiguous United States, 2013–2023, using an **Enhanced Two-Step Floating
Catchment Area (E2SFCA)** method on road-network isochrones with a mass-conserving
demand allocation and a Spatial Access Ratio (SPAR).

This repository was extracted from the larger **isochrones** pipeline
(<https://github.com/mufflyt/isochrones>, private) so the accessibility paper builds
and reproduces on its own, independent of the physician-distribution and
workforce-cliff work. isochrones is the **source of record** that generates the
road-network isochrones, the physician cohort, and the accessibility artifacts;
twostep vends the small frozen subset those produce, so the manuscript renders with
no network access — its only external code dependency is the
[`mufflyaccess`](https://github.com/mufflyt/mufflyaccess) package (data lineage in
[`docs/DATA_PROVENANCE.md`](docs/DATA_PROVENANCE.md)).

## Workforce counts, the URPS contract, and year handling

Table 1's provider counts and standardized supply are derived from the frozen
E2SFCA national summary (`e2sfca_national_summary.csv`) by the method's
conservation identity, `n = mean_per_100k × ACS_female_pop ÷ 100,000`; the loaders
in `scripts/manuscript_e2sfca_values.R` re-derive and cross-check them against that
frozen run (fail-closed on any disagreement > 1).

The urogynecology and reconstructive pelvic surgery (URPS) cross-reference footnote
reports the canonical board-certified-active workforce served by
[`mufflyaccess`](https://github.com/mufflyt/mufflyaccess) (≥ 0.10.0, contract
v3.0.0) via `mufflyaccess::urps_count()`: **1,306 nationally and 1,303 in the
contiguous United States for 2023**. twostep is a *consumer* of that contract, not
its owner.

Four distinct years appear in this paper and are not interchangeable — the README
and manuscript name the year explicitly rather than saying "current":

| Quantity | Year | Source |
|---|---|---|
| Headline active workforce + standardized supply (Table 1) | **2022** | frozen E2SFCA national summary |
| URPS board-certified-active workforce (footnote) | **2023** | `mufflyaccess::urps_count()` (1,306 national / 1,303 CONUS) |
| Spatial-distribution / disparity analysis (Table 2, Figures 3–6) and the Figure 1 image | **2020** | 2020-vintage frozen artifacts |
| ACS demand denominator for the 2022 headline | **2022 ACS 5-year** | ACS 2018–2022, Table B01001 |

## Status and open items

- **Figure 1 is still the 2020 access surface.** Table 1's headline moved to 2022,
  but Figure 1 (`manuscript/figures/fig0_level2020.jpg`) has **not** been
  regenerated: its per-panel means are 2020 values and will disagree with Table 1's
  2022 supply column until the production pipeline produces the validated 2022
  surface. It is not a 2022 figure yet and must not be described as one.
- **The detailed disparity analysis remains 2020.** Table 2 (% outside 60/120/180
  min; Gini), Figures 3–6, and their Results prose are computed on the 2020 spatial
  artifacts and are labeled 2020. They are unaffected by the Table 1 headline move
  and stay 2020 unless and until they are regenerated.

## Figures

These are the figures the manuscript renders (shipped in `manuscript/figures/` and
embedded by the render; the generating scripts `scripts/figure_*` and `scripts/map_*`
are included for provenance). The seven supplemental per-subspecialty access-change
maps (Figures S1 to S7) are shown under [Supplemental figures](#supplemental-figures-s1-to-s7)
below and in the rendered HTML.

**Figure 1. Potential accessibility to each of the seven OB/GYN subspecialties, 2020** (per 100,000 women). *Still the 2020 surface; pending regeneration to 2022 — see [Status and open items](#status-and-open-items).*

![Figure 1](manuscript/figures/fig0_level2020.jpg)

**Figure 2. National potential accessibility by subspecialty** (population-weighted mean and distribution).

![Figure 2](manuscript/figures/fig1_national.jpg)

**Figure 3. Gynecologic oncology accessibility in 2020, by (A) rurality and (B) race and ethnicity.**

![Figure 3](manuscript/figures/fig3_go2020.jpg)

**Figure 4. Access for disadvantaged groups relative to their reference group, across all seven subspecialties** (equity heatmap).

![Figure 4](manuscript/figures/fig_equity_heatmap.jpg)

**Figure 5. Trends in gynecologic oncology accessibility disparities, 2013 to 2023.**

![Figure 5](manuscript/figures/fig4_gotrends.jpg)

**Figure 6. Change in the share of (A) rural and (B) American Indian or Alaska Native residents with zero modeled access.**

![Figure 6](manuscript/figures/fig5_equity.jpg)

**Figure 7. Change in potential accessibility by subspecialty, 2013 to 2023.**

![Figure 7](manuscript/figures/fig5_change_faceted.jpg)

## Supplemental figures (S1 to S7)

Per-subspecialty access **change**, 2013 to 2023 (Figures S1 to S7). Both endpoints are
computed on a single 2020 grid and demand so the difference isolates the change in
the active workforce, not the demand denominator. These also render in the
manuscript HTML.

**Figure S1. Gynecologic oncology**, access change 2013 to 2023.

![Figure S1](manuscript/figures/figS_go.jpg)

**Figure S2. Maternal-fetal medicine**, access change 2013 to 2023.

![Figure S2](manuscript/figures/figS_mfm.jpg)

**Figure S3. Reproductive endocrinology and infertility**, access change 2013 to 2023.

![Figure S3](manuscript/figures/figS_rei.jpg)

**Figure S4. Urogynecology and reconstructive pelvic surgery (URPS)**, access change 2013 to 2023.

![Figure S4](manuscript/figures/figS_fpmrs.jpg)

**Figure S5. Minimally invasive gynecologic surgery**, access change 2013 to 2023.

![Figure S5](manuscript/figures/figS_migs.jpg)

**Figure S6. Pediatric and adolescent gynecology**, access change 2013 to 2023.

![Figure S6](manuscript/figures/figS_pag.jpg)

**Figure S7. Complex family planning**, access change 2013 to 2023.

![Figure S7](manuscript/figures/figS_cfp.jpg)

## Reproduce the manuscript

```r
# from the repo root — one time, to install the exact pinned package versions
Rscript -e 'renv::restore()'

# then render
Rscript render.R
# -> manuscript/e2sfca_accessibility_manuscript.html (self-contained)
```

Package versions are pinned in `renv.lock` (renv activates automatically via
`.Rprofile`), so the render and tests are hermetic down to the package version.
The render uses `rmarkdown`, `knitr`, `kableExtra`, `dplyr`, `tidyr`, `purrr`,
`tibble`, `readr`, `jsonlite`, `here`, and the shared single-source-of-truth
package **`mufflyaccess`** (public, pinned in `renv.lock`), which supplies the
shared band/geography/denominator constants and the 2023 URPS workforce
cross-reference; the tests add `testthat`, `sf`, `terra`, `exactextractr`,
`checkmate`, `rprojroot`, and the HAC trend producer uses `sandwich`/`lmtest`.
`renv::restore()` installs all of these, including `mufflyaccess` from GitHub, so
no manual setup is needed and no other network access is required at render time.
All manuscript inputs are the small CSV/RDS/JSON files under `artifacts/2sfca/**`,
`manuscript/data/`, and the figures under `manuscript/figures/`.

## Run the method tests

```r
Rscript tests/testthat.R
```

The 25 test files (765 checks) pin the engine's analytic behavior (E2SFCA vs
M2SFCA, the distance-decay weights, zero-demand NA semantics, SPAR, and the
population-weighted disparity estimators), the single-source-of-truth constants and
their agreement with the shared `mufflyaccess` package, the frozen-run provenance
guards, and the consumer-contract and non-normative-access-language guards. They use
inline fixtures only (no network or external data).

## Layout

```
manuscript/   e2sfca_accessibility_manuscript.Rmd + bibs + green-journal.csl + figures/ + data/
R/            two_step_floating_catchment.R (engine), accessibility_stratification.R (stats SSOT), utils/
scripts/      manuscript_e2sfca_values.R (canonical loaders used by the Rmd) + analysis/figure scripts
artifacts/    frozen E2SFCA run outputs the manuscript reads (run e2sfca_20260712_190734)
docs/         RUNBOOK_E2SFCA_ACCESSIBILITY.md
tests/        testthat suite for the engine + stratification SSOT
```

## Method sources

Every function in `R/two_step_floating_catchment.R` carries a `@references` tag; the
module header has the full citation sheet (Luo & Wang 2003; Luo & Qi 2009;
Delamater 2013 M2SFCA; Wan et al. 2012 SPAR; McGrail 2009/2012; Apparicio et al.
2017; and others) mapped to the function each grounds. `docs/RUNBOOK_E2SFCA_ACCESSIBILITY.md`
documents the production run, gates, and frozen facts.

## Provenance and scope

- **Frozen run:** `e2sfca_20260712_190734` (raster engine, 500 m EPSG:5070, 77/77
  subspecialty-year cells, conservation to 1e-14). Every frozen artifact used by the
  manuscript, its provenance, and what it feeds are documented in
  [`docs/DATA_PROVENANCE.md`](docs/DATA_PROVENANCE.md); their SHA-256 checksums are
  pinned in [`SHA256SUMS.txt`](SHA256SUMS.txt) (`shasum -a 256 -c SHA256SUMS.txt`).
- **Analysis scripts vs manuscript:** the manuscript reproduces from the frozen
  output artifacts here. The heavy generation scripts (`scripts/run_2sfca.R`,
  `sensitivity_e2sfca_2020.R`, the map/seam scripts) are included for provenance
  but consume upstream pipeline inputs (isochrones, the year-cohort panel, ACS
  bundle) that are **not** shipped in this repo; they document how the artifacts
  were produced rather than re-running end to end here.
- **Upstream pipeline (source of record):** the frozen artifacts, and the inputs the
  generation scripts consume, are created and maintained in the isochrones pipeline
  (<https://github.com/mufflyt/isochrones>, private; source commit `ff3aac4a`).
  twostep vends a frozen, checksummed subset of that pipeline's output; you do **not**
  need access to isochrones to reproduce the manuscript from this repo.
- **Regenerating the shipped outputs:** the scripts that produced twostep's
  committed artifacts/figures are now included, so outputs are regenerable rather
  than only frozen, e.g. `scripts/spatial_outcomes_2020.R` -> `spatial_outcomes_2020.csv`,
  `scripts/map_equity_heatmap.R`, and `scripts/map_allsubspec_allyears_access_surface.R`.
  The per-subspecialty E2SFCA access-surface maps are in
  `artifacts/2sfca_seam/figures/`, and `scripts/check_wordcount.R` audits the
  rendered main-text word count. Like the other generation scripts, most consume
  upstream inputs not shipped here (see the analysis-scripts note above).
- **Geographic scope:** contiguous U.S. (48 states + DC). Alaska and Hawaii are
  outside the road-network modeling framework; see the manuscript's limitations.
