# Port of the E2SFCA study-layer corrections from `isochrones`, 2026-08-18

## Why this port exists

`isochrones` commit `1c8e46b30` (2026-07-24) removed the E2SFCA analysis from
`feature/seven-subspecialty-expansion` on the grounds that it was "now standalone
at mufflyt/twostep". That was true of the *code layout* and false of the
*science*: between 2026-08-13 and 2026-08-17, four substantive corrections landed
on `isochrones/main` and never reached this repo. Deleting the files without
porting them would have discarded measured, published-number-moving work.

This document records the port, so the next person can tell what moved, what was
already here, and what is still outstanding.

## Ownership model this port establishes

| Layer | Owner |
|---|---|
| Isochrone generation, routing, geometry, provenance, warehouse | `isochrones` |
| E2SFCA/M2SFCA equations and study analysis | **`twostep`** (this repo) |
| Shared accessibility/statistical primitives | `mufflyaccess` |

## What was ported

| # | Correction | Source commit (`isochrones`) | Landed here as |
|---|---|---|---|
| 1 | Connecticut planning-region GEOID repair | `fe25f0ed3` (+ helper from `R/census_data_fetcher.R`) | `R/ct_geoid_relabel.R`, `inst/extdata/ct_tract_geoid_equivalency_acs2022.csv`, wired into `scripts/stratify_allyears_access.R` |
| 2 | Accounted denominator joins + per-state fail-closed >5% gate | `fe25f0ed3` | `R/study_join_accounting.R::assert_state_join_loss()` |
| 3 | Missing access preserved, not coerced to zero | `fe25f0ed3` | `R/study_join_accounting.R::partition_unknown_access()` |
| 4 | Allocator lineage / M2SFCA provenance | `5dac5011b` | `scripts/run_2sfca.R` gate re-pin (see caveat below) |
| - | Connecticut correction appendix | `c30d5088f`, `a631aa226`, `5dac5011b`, `fe25f0ed3` | `inst/doc-provenance/CT_E2SFCA_GEOID_BREAK.md` |
| - | Pre-specified correction analysis | `0dc556e37`, `0512dcb73` | `scripts/analyze_ct_correction.R` |

Gaps 2 and 3 were **inline script code** in `isochrones`. They were promoted to
tested exports here, because this repo now owns the study layer and an untestable
inline gate is not an owned one.

## Two things the port did NOT need to do

**`step2_power` was already here.** `e2sfca_incremental_weights()` is
byte-identical between the two repos (deparsed hash `f5bc77a8138a`), so the
M2SFCA argument described in `5dac5011b` was already present in this engine. The
earlier claim that it was missing came from grepping `scripts/run_2sfca.R`, where
it appears only in prose.

**The invariant test suite was not copied.** `isochrones` `c7695791d` asserts
E2SFCA invariants with negative controls; this repo already has strictly stronger
coverage - Luo & Qi (2009) and Delamater (2013) published fixtures (`24dd4b3`,
`cdb02c5`), a persistent mutation corpus (`0e620c4`), Monte Carlo null and
known-signal recovery (`47d5392`), and an end-to-end study oracle (`38f9448`).

## Caveat on gap 4, stated plainly

The gate constant was **stale, not merely different**. It pinned `11abdec3`,
while this repo's `R/two_step_floating_catchment.R` hashes to `e162507c` after
the 2026-08-16 engine work. The gate was failing closed against its own engine.

Copying `isochrones`' constant `674f7113` would have been wrong - that is the
hash of *their* engine file. The pin was therefore re-pinned to **this repo's**
engine hash, with evidence gathered by parsing both files and hashing the
deparsed definitions:

- **Byte-identical** to `isochrones@origin/main` (itself certified identical to
  the seam-validated ancestor `ff3aac4a`): `allocate_pop_areaweighted`,
  `build_e2sfca_raster_grid`, `build_e2sfca_grid_geometry`,
  `e2sfca_cell_summaries`, `compute_provider_supply`,
  `e2sfca_incremental_weights`.
- **Different, deliberately**: `attach_e2sfca_population`,
  `compute_e2sfca_raster`. These are this repo's own reviewed changes -
  "missing population is not zero population" (`998ad40`) and "stop reporting
  unreached tracts as measured zeros" (`53cfd45`).

Those two deltas are **intentionally not numerically neutral**: an unreached
tract now reports `NA` rather than a measured `0`. So, unlike the `isochrones`
re-pin of 2026-08-16, **no claim of `0.000e+00` equivalence is made here**. The
re-pin re-certifies the *allocation* (mass conservation, area overlap), not the
full surface numerics.

**Outstanding:** re-run the seam test against this engine to re-certify the
surface numerics, and re-pin `SEAM_ALLOCATOR_SHA256` from that run.

## Verification performed

- New tests: `tests/testthat/test-ct-geoid-relabel-ported.R` (18 assertions),
  `tests/testthat/test-study-join-accounting.R` (33 assertions), each including
  negative controls.
- Full suite after the port: **340 files, 1573 passing, 0 failures, 0 errors,
  10 skipped** (up from 1527 passing before).
- Equivalency table copied byte-identically
  (sha256 `5f137e24e860eca651fb5229e8ee9af23042aba3b19fee471677883c16ec42bb`).
- `NAMESPACE` regenerated and cross-checked by `tools/sync_namespace.R`
  (61 exports, in sync).

## Not verified here, and why

The corrected Connecticut and disparity analyses were **not re-run**. Those need
the production access surfaces (`step_4_2sfca_<SUB>_<YEAR>.rds` for 7
subspecialties x 11 years) and the ACS bundle, which are not present on this
machine. The measured effects quoted throughout - metropolitan-rural gap
overstated by 2.1-2.5%, Asian mean access -1.8 to -1.9%, Asian-vs-White gap
narrowing 4.6% (GO 2023), 0 of 14 metro>rural reversals, 0 of 28 trend sign
flips - are **carried over from the `isochrones` rerun**, not independently
reproduced here.
