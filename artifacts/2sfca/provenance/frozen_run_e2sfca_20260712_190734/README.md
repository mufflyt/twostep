# Provenance: frozen E2SFCA run `e2sfca_20260712_190734`

This is the input/output provenance record for **the** frozen run the manuscript
reads — the one named in the repository README (`e2sfca_20260712_190734`, raster
engine, 500 m EPSG:5070, 77/77 cells, isochrones source commit `ff3aac4a`).

## Why it is here

`SHA256SUMS.txt` pins what the study's artifacts **are**. Nothing recorded what
**produced** them. That gap was not theoretical: re-running
`scripts/sensitivity_e2sfca_2020.R` against inputs chosen by filesystem search
reproduced none of the frozen sensitivity artifact — the primary national
estimate came out 16.7% different — and there was no way to tell which input set
was correct.

These records were recovered from a run bundle that was otherwise about to be
deleted as stray output. They answer the question directly.

## Contents

| file | what it is |
|---|---|
| `_SUCCESS.json` | run id, git SHA, allocator SHA, full environment, and SHA-256 for all 8 inputs and 5 outputs |
| `e2sfca_inputs_SHA256SUMS.txt` | the 8 input checksums on their own |
| `e2sfca_code_SHA256SUMS.txt` | checksums of the code that ran |
| `outputs.sums` | output checksums |
| `e2sfca_index.csv` | the run's output index |
| `step_3_year_coord_map.rds` | the authentic year→coordinate map input, verified to hash `79f0080c…` as recorded |

## The one input that is here, and the ones that are not

`step_3_year_coord_map.rds` is kept (848 KB) because it is verified authentic and
because without it a reproduction attempt cannot even begin. A copy picked by
filesystem search hashed to `01094384…` — a **different file** — which is
precisely why the re-run failed.

Not kept, deliberately: `acs_bundle_2013_2022.rds` (105 MB) and
`e2sfca_outputs_…tar.gz` (97 MB). Their SHA-256s are recorded in
`_SUCCESS.json`, so they remain identifiable; the bytes do not belong in git.

**`step_2.5_final_cohort.rds` (recorded hash `154e67dd…`) is NOT present here and
was not located on this machine.** A full reproduction still needs it. That is a
real, open gap, and it is stated rather than papered over.

## What this does not yet establish

These records document the frozen **E2SFCA run**. `sensitivity_2020.csv` is
produced by a *separate* script invocation, and no manifest for it was ever
committed. It is highly likely the same ycm/cohort inputs were used, but that is
an inference, not a record. It is confirmed only when a re-run pinned to these
inputs reproduces `national = 0.5408` for the `base`/GO cell.

Until then `tools/ci/check_artifact_provenance.R` stays non-strict.
