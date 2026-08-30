# Appendix: temporal integrity of the subspecialist cohort

**Status:** verified against the frozen panel on 2026-08-30, at `b4f6d23`.
Every number below was computed from
`artifacts/2sfca/provenance/frozen_run_e2sfca_20260712_190734/step_3_year_coord_map.rds`
(59,272 rows, 7,141 NPIs, 2013–2023) or from the code named. Nothing here is
taken from a report.

Related: [`docs/APPENDIX_FROZEN_ISOCHRONE_SSOT.md`](APPENDIX_FROZEN_ISOCHRONE_SSOT.md),
[`docs/DATA_PROVENANCE.md`](DATA_PROVENANCE.md).

---

## Why this exists

A longitudinal accessibility study has one failure mode that no checksum catches:
the workforce panel can be temporally wrong. If a physician's *current*
certification is projected back onto years before they held it, early years gain
supply they never had; if retirement is ignored, late years keep supply that had
left. Both distort the trend rather than the level, and both are invisible in an
artifact hash because the artifact faithfully records the wrong cohort.

Three separate audits raised claims about this. Two of the three specific claims
were wrong, and the one real defect was found by testing them rather than by
reading them.

## What the panel actually enforces

`year_coord_map` is a per-(NPI, year) panel carrying `certification_year`,
`retirement_year`, `match_source`, and `selection_policy_version`. Physicians
enter it in staggered years as they certify:

| first year in panel | 2013 | 2014 | 2015 | 2016 | 2017 | 2018 | 2019 | 2020 | 2021 | 2022 | 2023 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| NPIs | 5,264 | 332 | 325 | 276 | 271 | 183 | 203 | 76 | 162 | 48 | 1 |

That staggering is the temporal cohort design of Paul & Edwards (2019) working as
intended, and it is done upstream of `compute_provider_supply()`.

## Finding 1 — certification back-projection: real, and negligible

`compute_provider_supply()` semi-joins the cohort by `npi` and does **not** test
`certification_year <= analysis_year`. That is a genuine absence.

Measured consequence:

```
rows with analysis_year < certification_year :  3  of 59,272   (0.005%)
worst case                                   :  2 years early
rows with NA certification_year               :  0
```

The guard is missing from the function and supplied by the panel. Three
provider-years cannot move a national estimate, and adding the filter would
require re-running the frozen pipeline against `v0.2.0`. Recorded, not fixed.

## Finding 2 — multi-location supply expansion: **false**

The claim was that grouping by `coord_id` and counting `n_distinct(npi)` lets a
physician with *k* practice addresses contribute *k* units of supply.

```
(npi, year) cells with more than one coordinate :  0  of 59,272
GO 2020: unique NPIs 969, coordinates 503
sum of per-coordinate supply                    :  969   == headcount
```

`selection_policy_version = v1.0` selects one coordinate per NPI per year
upstream, so the expansion is unreachable. The claim's own evidence pointed the
other way: **fewer** coordinates than NPIs means physicians sharing locations,
which is aggregation, not duplication.

## Finding 3 — retirement is never applied

Not raised by any audit; found while testing Finding 1.

`retirement_year` is populated for 1,567 NPIs and appears **nowhere** in `R/`,
`scripts/`, or `tools/`. Exit nonetheless happens for most physicians, because
they leave the practice-location panel independently:

```
retiring within 2013-2022 (exit testable) : 1,521
exit correctly reflected                  : 1,429   (94.0%)
still present after retirement            :    92
```

Those 92 accumulate, so the residue is monotone in time:

| year | 2013 | 2016 | 2019 | 2022 | 2023 |
|---|---:|---:|---:|---:|---:|
| provider-years past retirement | 0 | 12 | 30 | 74 | 85 |
| share of that year's panel | 0.00% | 0.21% | 0.57% | 1.39% | 1.61% |

**Direction matters more than magnitude.** It inflates supply preferentially in
later years, so it biases the temporal trend toward *overstating* growth — the
same direction as the paper's headline growth claims. That is why it is stated in
the manuscript's Strengths paragraph rather than left here.

The Strengths sentence claims cohorts reflect "workforce entry, exit, and
relocation". At 94% that is substantially true, so it is qualified rather than
retracted.

## Finding 4 — RUCA vintage in auxiliary scripts

The production engine branches RUCA by tract vintage
([`inst/multiverse/ruca_inputs.json`](../inst/multiverse/ruca_inputs.json)).
Two auxiliary scripts hardcode the 2020 file, and they differ in whether that
matters:

- `scripts/inferential_stats_access.R:55-57` hardcodes 2020 RUCA but joins with
  **`inner_join`**, so unmatched tracts are dropped rather than defaulted. It
  produces the 2020 cross-section, where 2020 RUCA is the correct vintage.
- `scripts/desjardins7/09_surface_recovery.R:32` does
  `left_join(...)` then `den$rurality[is.na(den$rurality)] <- "Rural"`. Unmatched
  tracts silently become rural. Its only output, `surface_recovery_2020.csv`,
  appears **zero times** in `SHA256SUMS.txt` and feeds nothing the manuscript
  reports. Harmless today; a trap if the script is ever reused on 2010-vintage
  tracts.

## Finding 5 — the 2023 level shift is a coordinate artifact, not a rebound

Found while testing an exploratory claim that 2023 showed a workforce rebound.

In 2023 every subspecialty **lost** physicians and **gained** recorded practice
coordinates:

| 2022 → 2023 | NPIs | coordinates |
|---|---:|---:|
| MFM | −1.3% | **+23.3%** |
| REI | −0.5% | +21.6% |
| PAG | −2.1% | +15.6% |
| CFP | −1.0% | +9.8% |
| FPMRS | −1.0% | +9.3% |
| GO | −1.0% | +7.9% |
| MIGS | −4.5% | +5.4% |

Pooled coordinates per physician step from **0.348 to 0.410**, a break on a decade
of gradual drift (0.305 → 0.311 → 0.335 → 0.354 → 0.348 across 2013–2022 — the
drift is real; the step is not part of it). E2SFCA builds a catchment around every
coordinate, so spreading the same physicians over more origins raises modeled
access without adding supply. Across the seven groups the correlation between each
subspecialty's coordinate change and its access change is **r = 0.961**.

**What this does and does not affect.**

It contaminates the 2023 *level*, and therefore any 2013→2023 endpoint
comparison. It does **not** manufacture the decade-long growth story. Over
2013→2023 five of seven groups grew genuinely in headcount, and MFM's decline is
real workforce loss, not an artifact:

| | NPIs 2013 → 2023 | change | access change |
|---|---|---:|---:|
| MFM | 1,873 → 1,420 | −24.2% | −19.4% |
| REI | 1,037 → 1,019 | −1.7% | +10.2% |
| PAG | 129 → 139 | +7.8% | +13.2% |
| FPMRS | 892 → 1,021 | +14.5% | +19.3% |
| GO | 896 → 1,041 | +16.2% | +20.1% |
| CFP | 67 → 95 | +41.8% | +39.2% |
| MIGS | 344 → 505 | +46.8% | +58.5% |

A claim that other subspecialties' coordinate surges "masked underlying headcount
contractions" was tested and is false: only MFM and REI lost physicians over the
decade, and only REI gained access while doing so.

The manuscript's design already handled this correctly — the primary window ends
at 2022 and 2023 is provisional. What was wrong was the stated *reason*: the
Methods attributed it to right-censoring alone, an under-recording bias, when the
measurable 2023 anomaly is over-recording of coordinates and points upward. That
sentence now names both directions.

## What is guarded, and by what

| vector | mechanism |
|---|---|
| 2023 leaking into 2013–2022 trends | trend scripts filter `year <= 2022`; `trend_hac.rds` holds exactly 10 annual observations |
| 2010 vs 2020 tract epochs | vintage split at 2020; change surfaces held on one grid and denominator |
| Connecticut GEOID break at ACS 2022 | `relabel_ct_geoids_safe()`, fail-closed for `YEAR >= 2022` |
| age-matched denominators reaching the primary analysis | `tools/ci/check_agematched_ssot.R` |
| supply silently lost to a missing catchment | `unmatched_supply_policy = "error"`; `tools/ci/check_supply_conservation.R` |
| wrong isochrone set | hash pin, `tools/ci/check_frozen_isochrones.sh` |
| artifact substitution after release | `SHA256SUMS.txt`, verified by `render.R` before rendering |

## Claims received but not verified here

Several exploratory reports produced longer lists of findings than are recorded
above. They are deliberately excluded until each is reproduced from the
artifacts, for the same reason the two refuted claims above are named: acting on
an unverified report is how a correct figure gets replaced with a wrong one. Two
such corrections have already been avoided in this repository — a reference
value the source does not contain, and a "conservation theorem" the sensitivity
artifacts disprove.
