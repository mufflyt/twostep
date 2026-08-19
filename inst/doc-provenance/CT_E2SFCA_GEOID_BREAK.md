
---

# Part 2: repair, and how much the results actually change

## The repair (verified on real data)

`relabel_ct_geoids_safe()` — the existing PI-approved, idempotent, fail-closed
helper already used by Steps 8/9/11 — is now applied to the ACS population
before it is joined to tract geometry in `scripts/run_2sfca.R`. Verified against
the frozen run's own ACS bundle (SHA `b2a66353…`, matching the manifest exactly):

| | CT tracts matched | female population |
|---|---:|---:|
| before relabel | **0 / 879** | 0 |
| after relabel | **879 / 879** | **1,842,121** |

The two GEOIDs left unrelabeled are the documented no-legacy-counterpart water
tracts (`09180990100`, `09190990000`).

The defect is reproduced exactly in the frozen inputs, which rules out any
possibility that it was introduced later:

| bundle year | CT tracts | planning-style | legacy-style |
|---|---:|---:|---:|
| 2021 | 883 | 0 | **883** (matches geometry) |
| 2022 | 884 | **884** | 0 (matches nothing) |

A per-state fail-closed guard now stops the run if any state loses >5% of its
tracts in the population join. The grain matters: 879 unmatched of 83,509 is
98.9% matched nationally — passing any plausible national threshold — while
being 100% of Connecticut.

## The rebuild lineage: found, after a wrong first answer

**Correction.** This appendix originally recorded the frozen run's provider
inputs as "not identifiable from local artifacts". That was **wrong**. The
frozen SSOT was produced from `artifacts/20260702_120134_90bf52ef/` -- BOTH
`step_3_year_coord_map.rds` and `step_2.5_final_cohort.rds` from that single
directory. All 14 (2022, 2023) x 7-subspecialty provider counts reproduce the
frozen `e2sfca_index.csv` **exactly**:

| | CFP | FPMRS | GO | MFM | MIGS | PAG | REI |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2022 | 60 | 624 | 532 | 584 | 367 | 95 | 500 |
| 2023 | 66 | 682 | 573 | 720 | 387 | 110 | 608 |

The earlier search failed because it paired that directory's year-coord map with
cohorts from *other* run directories and never tested the two files from the
*same* run. Its closest result, 612/516/63 against 624/532/66, read like a
near-miss but was simply the wrong pairing. Provider counts in
`e2sfca_index.csv` are an exact and cheap lineage fingerprint; same-directory
pairings should be tried first.

The underlying provenance weakness is real and unchanged:
`e2sfca_run_manifest.json` records the ACS-bundle and seam-gate SHAs but **not**
the year-coord-map / cohort paths, and `run_2sfca.R` resolves both by
`newest(...)` -- recency rather than canonical name, which CLAUDE.md #20 forbids.
Recording them in the manifest is the class fix.

## The allocator identity gate, and what it caught

The first rebuild attempt was stopped by the fail-closed allocator-identity
gate: the whole-file sha256 of `two_step_floating_catchment.R` had moved from
the pinned `11abdec3` to `674f7113`. The gate was not bypassed.

Comparing the working tree against the seam-validated ancestor `ff3aac4a`
(`2b78718b`) by parsing both versions and hashing deparsed definitions -- not by
line ranges, which shift under unrelated edits:

| function | identical to frozen |
|---|---|
| `allocate_pop_areaweighted` | yes |
| `build_e2sfca_raster_grid` | yes |
| `build_e2sfca_grid_geometry` | yes |
| `attach_e2sfca_population` | yes |
| `e2sfca_cell_summaries` | yes |
| `compute_provider_supply` | yes |
| **`e2sfca_incremental_weights`** | **no** |
| **`compute_e2sfca_raster`** | **no** |

The allocator is unchanged, but the drift reached the **engine**, so "the
allocator is unchanged" was not sufficient grounds to re-pin. The two changes
are a `step2_power` argument for M2SFCA (a no-op at `p = 1`), and a step-1 join
flipped from the cumpop side to the supply side with a zero-demand provider's
reported `ratio` becoming `NA` instead of `0` while the surface reads
`ratio_for_surface = 0`.

Rather than reason about neutrality, it was measured. Frozen engine vs working
tree on the synthetic raster fixture at `step2_power = 1`:

```
access_mean_area        max abs diff = 0.000e+00
access_mean_population  max abs diff = 0.000e+00
weighted_demand         max abs diff = 0.000e+00
GEOID sets identical    TRUE
zero-demand ratio       frozen = 0   HEAD = NA   (never enters the surface)
```

The certified computation is unchanged, so the gate was re-pinned with that
evidence recorded at the constant. The rebuild's only substantive difference
from the frozen run is the Connecticut fix.

## How much the results change: a bound computed from the frozen outputs

Instead of an uninterpretable rebuild, the effect is bounded directly. Each CT
tract's 2022 and 2023 access is imputed from its **2021** value — the last year
the population join worked — and the national population-weighted mean is
recomputed over the complete eligible population.

| subspecialty | year | published | corrected | change | YoY published | YoY corrected |
|---|---:|---:|---:|---:|---:|---:|
| CFP | 2022 | 0.0507 | 0.0512 | +0.82% | +0.95% | +1.78% |
| CFP | 2023 | 0.0550 | 0.0554 | +0.67% | +8.43% | +8.28% |
| FPMRS | 2022 | 0.5352 | 0.5373 | +0.38% | +5.62% | +6.02% |
| FPMRS | 2023 | 0.5786 | 0.5802 | +0.27% | +8.10% | +7.99% |
| GO | 2022 | 0.5884 | 0.5908 | +0.41% | +3.06% | +3.48% |
| GO | 2023 | 0.6238 | 0.6258 | +0.32% | +6.02% | +5.93% |
| MFM | 2022 | 0.7083 | 0.7133 | +0.70% | **-2.52%** | **-1.83%** |
| MFM | 2023 | 0.8177 | 0.8216 | +0.47% | +15.44% | +15.17% |
| MIGS | 2022 | 0.2621 | 0.2625 | +0.13% | +2.82% | +2.96% |
| MIGS | 2023 | 0.2768 | 0.2770 | +0.07% | +5.59% | +5.52% |
| PAG | 2022 | 0.0666 | 0.0672 | +0.82% | **-6.76%** | **-5.99%** |
| PAG | 2023 | 0.0758 | 0.0762 | +0.60% | +13.76% | +13.50% |
| REI | 2022 | 0.4968 | 0.5014 | +0.92% | **-2.18%** | **-1.28%** |
| REI | 2023 | 0.5885 | 0.5921 | +0.62% | +18.45% | +18.09% |

### The answer

**The manuscript's conclusion about temporal access does not change.**

- Every correction is **positive** — as predicted, since Connecticut is dense and
  high-access — and every one is **under 1%** (+0.07% to +0.92%).
- **No year-over-year direction flips.** The three 2022 declines (MFM, PAG, REI)
  remain declines after correction; every 2023 increase remains an increase.
- The largest single shift in a YoY figure is REI 2022, from -2.18% to -1.28%.

### Limits of this bound, stated plainly

1. It is an **imputation, not a rebuild**. CT tracts are assigned their 2021
   access. This is a good estimate only insofar as CT provider supply and
   catchments changed little across 2021-2023.
2. It does **not** capture the second-order effect. A zero-population
   Connecticut also removed CT women from the Step-1 demand denominator of every
   provider whose catchment reaches the state, inflating supply-to-demand ratios
   for providers in NY, MA and RI. Correcting that would **lower** access
   slightly in those neighbouring states, partially offsetting the CT gain. The
   true net correction is therefore likely **smaller** than the table shows,
   which strengthens rather than weakens the conclusion above.
3. The bound uses national population-weighted means. **State-level** results for
   Connecticut itself change from "absent" to "present" and are not bounded by
   this analysis at all — any CT-specific claim must wait for the rebuild.

---

# Part 3: the rebuilt result

14 cells (2022, 2023 x 7 subspecialties), rebuilt with every input pinned to the
frozen lineage — same cohort and year-coord map (`20260702_120134_90bf52ef`,
provider counts reproducing `e2sfca_index.csv` exactly in all 14 cells), same
ACS bundle (SHA `b2a66353`), same raster engine, 500 m, `mass_conserving`. The
Connecticut GEOID fix is the only substantive difference. Exit 0, no errors.

Analysis pre-specified and committed before the cells finished
(`scripts/analyze_ct_correction.R`).

## Headline

| subspecialty | frozen 2022 | corrected 2022 | Δ | frozen 2023 | corrected 2023 | Δ |
|---|---:|---:|---:|---:|---:|---:|
| MFM | 0.7083 | 0.7002 | −1.15% | 0.8177 | 0.8083 | −1.15% |
| GO | 0.5884 | 0.5817 | −1.14% | 0.6238 | 0.6167 | −1.14% |
| FPMRS | 0.5352 | 0.5291 | −1.14% | 0.5786 | 0.5720 | −1.14% |
| REI | 0.4968 | 0.4911 | −1.16% | 0.5885 | 0.5816 | −1.16% |
| MIGS | 0.2621 | 0.2592 | −1.12% | 0.2768 | 0.2737 | −1.12% |
| PAG | 0.0666 | 0.0658 | −1.15% | 0.0758 | 0.0749 | −1.15% |
| CFP | 0.0507 | 0.0501 | −1.17% | 0.0550 | 0.0544 | −1.17% |

Every estimate falls, by a strikingly uniform **−1.12% to −1.17%**.

## The decomposition, measured rather than inferred

| subspecialty | second-order (Step-1 demand) | direct (outcome denominator) | net |
|---|---:|---:|---:|
| CFP | −2.13% | +1.03% | −1.17% |
| REI | −2.08% | +0.97% | −1.16% |
| PAG | −2.02% | +0.91% | −1.15% |
| MFM | −1.78% | +0.68% | −1.15% |
| FPMRS | −1.62% | +0.51% | −1.14% |
| GO | −1.60% | +0.49% | −1.14% |
| MIGS | −1.25% | +0.14% | −1.12% |

**The earlier claim that the second-order effect "should partially offset" the
direct effect was wrong.** It does not offset — it dominates, by a factor of two
to nine, and reverses the net sign. Restoring 1,842,121 Connecticut women to
Step-1 weighted demand lowers supply-to-demand ratios for every provider whose
catchment reaches the state by more than Connecticut's own high access adds back
to the outcome denominator. The 2021-value imputation used earlier predicted
**+0.4%**; the measured answer is **−1.14%**. An imputation that never re-runs
Step 1 cannot see this mechanism, which is precisely why the rebuild was needed.

## Repair confirmed, and an independent validation signal

`NA` tracts fall from **838 to 9** and `NA` population from **1.051% to 0.000%**
in every cell.

The supply-conservation residual **improves in all 14 cells**:

| | frozen | corrected |
|---|---:|---:|
| range | +2.52e-03 … +3.11e-03 | +1.61e-03 … +1.89e-03 |

This was not targeted by the fix. Restoring the missing population moved the
population-weighted surface integral closer to total included supply, which is
what should happen if the missing denominator was the cause. The residual is not
zero in either arm (~0.2%) because a tract zonal mean over 500 m cells does not
exactly reproduce the cell-level surface integral — an estimator property, not
an error — but the direction and uniformity of the improvement are corroborating.

## Does any inference change?

| check | answer |
|---|---|
| sign flip, 2021→2022 | **1 — CFP, +0.95% → −0.23%** |
| sign flip, 2022→2023 | 0 |
| sign flip, 2013→2023 | 0 |
| subspecialty ranking, 2022 | unchanged (MFM > GO > FPMRS > REI > MIGS > PAG > CFP) |
| subspecialty ranking, 2023 | unchanged (MFM > GO > REI > FPMRS > MIGS > PAG > CFP) |
| trend significance crossing | **0 of 7** |
| trend sign flip | 0 of 7 |
| max \|Δ\| on any cell | 1.174% |

### The one real inference change

**Complex Family Planning, 2021→2022, reverses direction**: reported as a
**+0.95% increase**, it is a **−0.23% decrease** once Connecticut is restored.
CFP is the smallest subspecialty (60 providers in 2022), so it has both the
largest second-order sensitivity (−2.13%) and the smallest baseline, and a
year-over-year change of under 1% is not robust to a 1.2% correction. Any
sentence asserting that CFP access rose in 2022 must be revised.

### Trend test (OLS on annual national estimates, 2013–2022, excluding 2023)

| subspecialty | frozen slope/yr (P) | corrected slope/yr (P) |
|---|---:|---:|
| CFP | +0.00082 (P=0.0316) | +0.00078 (P=0.0350) |
| FPMRS | −0.00041 (P=0.9054) | −0.00073 (P=0.8263) |
| GO | +0.00343 (P=0.1146) | +0.00308 (P=0.1393) |
| MFM | −0.04225 (P<0.0001) | −0.04268 (P<0.0001) |
| MIGS | +0.00823 (P=0.0001) | +0.00807 (P=0.0001) |
| PAG | −0.00043 (P=0.4496) | −0.00047 (P=0.4167) |
| REI | −0.00525 (P=0.0086) | −0.00555 (P=0.0084) |

No slope changes sign and no P value crosses 0.05. CFP comes closest
(0.0316 → 0.0350) and remains significant. Only the 2022 endpoint moves, since
ACS years before 2022 carry no planning-region GEOIDs.

## Connecticut itself

Reported for completeness, but the frozen column is **not a Connecticut
estimate**: 829 of 879 CT tracts were `NA`, so it is a weighted mean over the
~50 surviving border tracts, precisely those adjacent to the inflated New York
and Massachusetts providers. The corrected column is the first estimable value.

| | frozen (50-tract sliver) | corrected (879 tracts) |
|---|---:|---:|
| MFM 2023 | 1.3289 | 1.2422 |
| REI 2023 | 1.1276 | 1.0843 |
| GO 2023 | 0.8990 | 0.8649 |
| FPMRS 2023 | 0.8648 | 0.8158 |
| MIGS 2023 | 0.3070 | 0.2854 |
| PAG 2023 | 0.1233 | 0.1259 |
| CFP 2023 | 0.1144 | 0.1029 |

## Not evaluated

- **SPAR.** `compute_e2sfca_raster()` never materialises it, so
  `mean(SPAR) == 1` cannot be checked on real outputs.
- **Rural/urban and race disparities.** These are produced by
  `stratify_allyears_access.R`, which still uses two `inner_join`s and coerces
  `NA` access to 0. Rerunning that path on the corrected cells is the remaining
  work; the national results above do not settle it.
- **2013–2021.** Unaffected by construction and not rebuilt.

---

# Part 4: rural/urban and race disparities on the corrected cells

Three defects had to be repaired in `scripts/stratify_allyears_access.R` before
rerunning, because the corrected cells alone would have changed nothing:

1. **CT relabel applied to the ACS denominators.** Without it the denominator
   join still matches zero Connecticut tracts for 2022+, so the restored CT
   values would have been dropped again at the next step. Confirmed by the run
   log: 2022/2023 now report `0 no-denominator`, where 879 CT tracts were lost.
2. **Both `inner_join`s replaced with accounted `left_join`s**, plus a
   per-state fail-closed check (>5% loss stops the run and names the state).
3. **`NA` access no longer coerced to 0.** That turned a provenance gap into a
   *measured* observation of no access, biasing the mean down and the zero-share
   up. It is now partitioned, excluded from weights, and counted.

Run over a merged 77-cell series: frozen 2013-2021 plus corrected 2022-2023.

## Rural/urban

| subspecialty | year | published gap | corrected gap | change |
|---|---:|---:|---:|---:|
| CFP | 2022 | 0.0435 | 0.0425 | −2.27% |
| CFP | 2023 | 0.0480 | 0.0469 | −2.20% |
| FPMRS | 2022 | 0.3157 | 0.3080 | −2.45% |
| FPMRS | 2023 | 0.3442 | 0.3359 | −2.43% |
| GO | 2022 | 0.3645 | 0.3560 | −2.32% |
| GO | 2023 | 0.3712 | 0.3623 | −2.39% |
| MFM | 2022 | 0.5146 | 0.5033 | −2.19% |
| MFM | 2023 | 0.5716 | 0.5590 | −2.21% |
| MIGS | 2022 | 0.1530 | 0.1495 | −2.29% |
| MIGS | 2023 | 0.1589 | 0.1553 | −2.26% |
| PAG | 2022 | 0.0373 | 0.0364 | −2.52% |
| PAG | 2023 | 0.0425 | 0.0415 | −2.44% |
| REI | 2022 | 0.3560 | 0.3483 | −2.15% |
| REI | 2023 | 0.4266 | 0.4175 | −2.14% |

**The metropolitan–rural gap was overstated by 2.1–2.5% in 2022–2023.** The
mechanism is direct: metropolitan access falls (~−1.2%) while rural access is
essentially unchanged or rises slightly, because Connecticut is dense and
metropolitan, so restoring its women to Step-1 demand depresses ratios for
metropolitan Northeastern providers and barely touches rural ones.

**No reversals.** Rural access remains far below metropolitan in every
subspecialty and year (FPMRS 2023: 0.6267 metro vs 0.2908 rural). The
urban–rural disparity finding stands; only its magnitude is slightly smaller.

## Race groups

Every group falls, but **unevenly**, which is what shifts the comparisons:

| group (GO 2023) | published | corrected | change |
|---|---:|---:|---:|
| Asian alone | 0.7837 | 0.7691 | −1.86% |
| Black alone | 0.7087 | 0.7002 | −1.20% |
| Hispanic (any race) | 0.6347 | 0.6268 | −1.24% |
| Nat. Hawaiian/Pac. Isl. | 0.6282 | 0.6260 | −0.35% |
| White, non-Hispanic | 0.5871 | 0.5815 | −0.95% |
| Am. Indian/Alaska Native | 0.4856 | 0.4826 | −0.61% |

Groups concentrated in the metropolitan Northeast (Asian, −1.8 to −1.9%) absorb
the largest correction; AIAN and NHPI (−0.3 to −0.7%) the smallest. The
White-vs-AIAN gap therefore narrows slightly, and the Asian-vs-White gap narrows
more (GO 2023: 0.1966 → 0.1876, −4.6%).

**One ordering change, in one cell.** Gynecologic Oncology 2022: Hispanic and
Native Hawaiian/Pacific Islander swap third and fourth place. They were nearly
tied to begin with and the correction is enough to cross them. No other
subspecialty or year reorders.

## Zero-access shares

All fall very slightly, by 0.001 to 0.22 percentage points, with rural falling
marginally more than metropolitan in most cells (CFP 2023 rural 36.926% →
36.737%). No material change to any zero-access claim.

## Inference: does any disparity conclusion change?

| check | answer |
|---|---|
| metropolitan > rural reversal | **0 of 14** |
| race-group ordering change | **1 of 14** (GO 2022, Hispanic/NHPI near-tie) |
| stratified trend sign flips | **0 of 28 series** |
| stratified trend significance crossings | **0 of 28 series** |

The 28 series are Rural %zero, Metro %zero, Rural mean access and AIAN mean
access, for each of the 7 subspecialties, fitted as the manuscript fits them
(OLS on annual estimates, 2013–2022, excluding 2023). Not one slope changes sign
and not one P value crosses 0.05. The closest movements are FPMRS Metro %zero
(P 0.0643 → 0.0564) and GO Rural %zero (P 0.0851 → 0.0779), both of which stay
on the same side of the threshold.

## Summary

The disparity conclusions hold. What changes is magnitude, in one consistent
direction: **the urban–rural gap was overstated by roughly 2.3%**, and racial
gaps involving metropolitan-concentrated groups were overstated by up to ~4.6%.
Both should be restated with corrected values, but neither reverses, and no
trend inference moves.
