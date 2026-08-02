# Figure provenance (twostep manuscript)

Authoritative record of **where each manuscript figure came from**: which script
produced it, in which repository, from which data, and on what day. Companion to
[`DATA_PROVENANCE.md`](DATA_PROVENANCE.md) (which covers the tabular/RDS data
artifacts) and the machine-readable
[`../manuscript/figures/FIGURE_PROVENANCE.csv`](../manuscript/figures/FIGURE_PROVENANCE.csv).

**Last verified:** 2026-08-02.

## How to read this

Every figure in `manuscript/figures/` was **generated in the upstream isochrones
pipeline** (`github.com/mufflyt/isochrones`, private, source of record), then
**staged into twostep**: the isochrones script writes a PNG (or JPG) under
`artifacts/2sfca_seam/figures/` or `artifacts/2sfca/figures/`, which was converted to
JPG and renamed to the `figNN_*.jpg` name the manuscript embeds, and committed to
twostep at its initial commit (`37337d7`, 2026-07-24).

> **Provenance gap this file closes:** the PNG-to-JPG conversion and the rename to the
> `figNN` scheme were done by hand (not a committed script), so the figure filename
> alone does not reveal its generator. The mapping below is the source of truth for
> that step. The manuscript figure *number* and the file *name* do not match (e.g.
> Figure 5 is `fig4_gotrends.jpg`); always resolve by this table, not by the digits in
> the filename.

The underlying data are the frozen production run **`e2sfca_20260712_190734`**
(`E2SFCA_FROZEN_RUN_ID`), 500 m EPSG:5070 grid, contiguous United States.

## Master map

| Manuscript | twostep file | Generated (file date) | Generator script (isochrones `scripts/`) | Intermediate output | Data input |
|---|---|---|---|---|---|
| Figure 1 | `fig0_level2020.jpg` | 2026-07-15; **regenerated 2026-08-02** | `map_allsubspec_level_2020_faceted.R` | `artifacts/2sfca_seam/figures/map_allsubspec_level_2020_faceted.png` | `level_2020_faceted_df.rds` cache + `e2sfca_national_summary.csv` |
| Figure 2 | `fig1_national.jpg` | 2026-07-15 | `figure_2sfca_national_11yr.R` | `artifacts/2sfca/figures/fig_2sfca_national_11yr_<run>.png` | `e2sfca_national_summary.csv` (11-year) |
| Figure 3 | `fig3_go2020.jpg` | 2026-07-15 | `stratify_go_2020_access.R` | `artifacts/2sfca/figures/fig_go_2020_access_stratified.png` | `step_4_2sfca_GO_2020.rds` + `ruca_tract_mapping.csv` |
| Figure 4 | `fig_equity_heatmap.jpg` | 2026-07-18 | `map_equity_heatmap.R` | writes `.jpg` directly | `allsubspec_allyears_stratified_LONG.csv` |
| Figure 5 | `fig4_gotrends.jpg` | 2026-07-18 | `manuscript_figures_redesign.R` | writes `.jpg` directly | `allsubspec_allyears_stratified_LONG.csv` |
| Figure 6 | `fig5_equity.jpg` | 2026-07-18 | `manuscript_figures_redesign.R` | writes `.jpg` directly | `allsubspec_allyears_stratified_LONG.csv` |
| Figure 7 | `fig5_change_faceted.jpg` | 2026-07-15 | `map_allsubspec_change_faceted.R` | `artifacts/2sfca_seam/figures/map_allsubspec_change_faceted_2013_2023.png` | `change_faceted_df.rds` |
| Figures S1 to S7 | `figS_{go,mfm,rei,fpmrs,migs,pag,cfp}.jpg` | 2026-07-15 | `map_allsubspec_change_2013_2023.R` | `artifacts/2sfca_seam/figures/map_<sub>_change_2013_2023.png` | `step_3_year_coord_map.rds` + `step_2.5_final_cohort.rds` + `isochrones_{30,60,120,180}min_consolidated.rds` |

**Generator location.** All seven generators are canonical in isochrones (source of
record). Three are also vendored into `twostep/scripts/` as convenience copies:
`figure_2sfca_national_11yr.R` (Figure 2), `stratify_go_2020_access.R` (Figure 3), and
`map_equity_heatmap.R` (Figure 4). The other four are **isochrones-only**:
`map_allsubspec_level_2020_faceted.R` (Figure 1), `manuscript_figures_redesign.R`
(Figures 5 and 6), `map_allsubspec_change_faceted.R` (Figure 7), and
`map_allsubspec_change_2013_2023.R` (Figures S1 to S7). Even the vendored copies
consume upstream pipeline inputs not shipped in twostep, so none regenerate end to end
from this repo alone.

"Generated (file date)" is the modification date of the vendored JPG (when it was
staged into twostep), which is the best record of when the figure the paper shows was
produced. The generator scripts were last committed to isochrones on 2026-07-18
(`map_equity_heatmap.R` `f7d29f129`; `manuscript_figures_redesign.R` `a7839f407`),
2026-07-21 (`map_allsubspec_change_2013_2023.R` `c9638a38b`), and 2026-07-25
(`9c9594f8b`, the level/national/GO/change-faceted scripts).

## Per-figure detail

### Figure 1, `fig0_level2020.jpg` (2020 access-level surface, 7 panels)
- **Generator:** isochrones `scripts/map_allsubspec_level_2020_faceted.R`.
- **Data:** per-cell 2020 surfaces cached in `artifacts/2sfca_seam/level_2020_faceted_df.rds`; facet-label means from `artifacts/2sfca/ec2/e2sfca_20260712_190734/e2sfca_national_summary.csv`.
- **First built:** 2026-07-15. **Regenerated 2026-08-02** to remove the baked-in title, subtitle, and bottom "Mass-conserving..." caption, and to simplify the colorbar label to "Access per 100,000 female residents" (title/subtitle/caption stripped from `labs()`, `scale_fill_viridis_c(name=...)` shortened). Re-rendered from the cache, then `sips`-converted PNG to JPG.
- **Panel numbers** (e.g. MFM 0.76) are each subspecialty's national population-weighted mean access; the manuscript Figure 1 legend states this.

### Figure 2, `fig1_national.jpg` (national accessibility, panels A and B)
- **Generator:** isochrones `scripts/figure_2sfca_national_11yr.R`. **Data:** `e2sfca_national_summary.csv` (all 11 years). **Built:** 2026-07-15. The current isochrones artifact PNG was later rebuilt (2026-07-19); the vendored JPG is the 2026-07-15 snapshot.

### Figure 3, `fig3_go2020.jpg` (GO 2020 by rurality and race)
- **Generator:** isochrones `scripts/stratify_go_2020_access.R`. **Data:** `step_4_2sfca_GO_2020.rds` (frozen run) plus `data/external/ruca_tract_mapping.csv`. **Built:** 2026-07-15.

### Figure 4, `fig_equity_heatmap.jpg` (cross-subspecialty equity heatmap)
- **Generator:** isochrones `scripts/map_equity_heatmap.R` (writes the JPG directly under the same name). **Data:** `allsubspec_allyears_stratified_LONG.csv`. **Built:** 2026-07-18.

### Figure 5, `fig4_gotrends.jpg` (GO disparity trends, 2013 to 2023)
- **Generator:** isochrones `scripts/manuscript_figures_redesign.R` (the "Figure 3" object in that script). **Data:** `allsubspec_allyears_stratified_LONG.csv`. **Built:** 2026-07-18.

### Figure 6, `fig5_equity.jpg` (zero-access change, rural and AIAN)
- **Generator:** isochrones `scripts/manuscript_figures_redesign.R` (the "Figure 4" object; 2020 dumbbell with 2013 to 2022 change indicator). **Data:** `allsubspec_allyears_stratified_LONG.csv`. **Built:** 2026-07-18.

### Figure 7, `fig5_change_faceted.jpg` (change by subspecialty, 2013 to 2023)
- **Generator:** isochrones `scripts/map_allsubspec_change_faceted.R`. **Data:** `artifacts/2sfca_seam/change_faceted_df.rds`. **Built:** 2026-07-15.

### Figures S1 to S7, `figS_{go,mfm,rei,fpmrs,migs,pag,cfp}.jpg`
- **Generator:** isochrones `scripts/map_allsubspec_change_2013_2023.R` (one panel-3 map per subspecialty). **Data:** `step_3_year_coord_map.rds` + `step_2.5_final_cohort.rds` + `isochrones_{30,60,120,180}min_consolidated.rds`. **Built:** 2026-07-15. Order in the manuscript: go, mfm, rei, fpmrs, migs, pag, cfp.

## Regenerating a figure

These generators live in the **isochrones** repo and consume upstream pipeline data
not shipped in twostep. To rebuild (from the isochrones checkout):

```bash
# Figure 1 (re-renders from the cached surface, seconds):
Rscript scripts/map_allsubspec_level_2020_faceted.R
sips -s format jpeg -s formatOptions 90 \
  artifacts/2sfca_seam/figures/map_allsubspec_level_2020_faceted.png \
  --out /path/to/twostep/manuscript/figures/fig0_level2020.jpg

# Figures 5 and 6 (both from the redesign script):
Rscript scripts/manuscript_figures_redesign.R   # writes fig4_gotrends.jpg + fig5_equity.jpg directly
```

After restaging any figure, update `manuscript/figures/FIGURE_PROVENANCE.csv` (date +
sha256) and re-run `Rscript render.R`.
