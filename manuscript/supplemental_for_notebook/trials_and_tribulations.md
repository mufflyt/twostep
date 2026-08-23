# Twostep: Trials and Tribulations

Guiding notes on what actually went wrong while building this study, and what
each failure taught. Every episode below is documented in the repository with
commits, artifacts, and tests — none of it is reconstructed from memory.

The through-line: **the dangerous failures were never crashes. They were runs
that succeeded and produced confident, wrong numbers.**

---

## 1. Connecticut disappeared, and the national average said everything was fine

The single best story in this project.

In 2022 the Census Bureau replaced Connecticut's county-based census tracts with
new **planning-region** tracts. The GEOIDs changed. Our ACS population extract
picked up the new planning-style GEOIDs; the tract geometry we joined against
still used the legacy ones.

They matched on nothing.

| | CT tracts matched | female population |
|---|---:|---:|
| before repair | **0 of 879** | **0** |
| after repair | 879 of 879 | 1,842,121 |

**Connecticut's entire female population — 1.84 million women — silently became
zero.** No error. No warning. The pipeline ran green and produced a national
accessibility surface with a hole in New England.

Here is why nobody caught it for so long, and it is the lesson worth telling:

> 879 unmatched tracts out of 83,509 is **98.9% matched nationally** — a number
> that sails past any plausible data-quality threshold anyone would think to
> write. It was simultaneously **100% of Connecticut**.

A national completeness check cannot see a state-shaped hole. The fix was not
just relabeling the GEOIDs; it was adding a **per-state fail-closed guard** that
stops the run if any single state loses more than 5% of its tracts in the join.
The grain of the check has to match the grain of the failure.

The bug reproduces exactly in the frozen inputs, which proves it was there from
the beginning rather than introduced during cleanup.

---

## 2. Trying to reproduce our own published number, and failing by 0.786%

We attempted to regenerate the frozen national result from its own recorded
inputs. It came out **0.786% below** the published value.

The cause: **5 of 516 supply origins had no isochrone**. Those five carried 7 of
890 supply units — 0.787% of all supply. Their supply simply evaporated. The
engine reported success.

A provider who exists, is counted in the supply table, and has no catchment
contributes nothing to anyone's access, and nothing anywhere says so.

The engine now refuses: `compute_e2sfca_raster()` takes an
`unmatched_supply_policy` that defaults to `"error"`, names the offending
origins, and quantifies the share of supply they carry. Fail closed, loudly,
with the number you need to judge severity.

The most interesting part: the reproduction attempt was *supposed* to be a
formality. It found a real defect precisely because it was run honestly instead
of being assumed.

---

## 3. Age-ignored vs. age-specific denominators: the appendix that broke a claim

The primary analysis indexes every subspecialty to the same denominator — the
total female population of all ages. That is defensible as a *standardized*
measure of geographic reachability, and the paper says so. But a careful reader
notices immediately:

- **pediatric and adolescent gynecology** is measured against a population that
  includes 80-year-old women;
- **gynecologic oncology** and **urogynecology** are measured against a
  population that includes 6-year-old girls.

So we rebuilt the denominators to match who each subspecialty actually serves,
and re-ran the entire engine. Fourteen cells, both regimes, identical in every
respect except the denominator.

### The mathematics says most of this should cancel

Where the denominator enters is exactly one place — step 1 of E2SFCA:

    R_j = S_j / Σ_i w_ij P_i        A_i = Σ_j w_ij R_j

Replace `P_i` with `α_i · P_i`, where α is the age-eligible share. **If α were
spatially uniform**, then `R_j → R_j/α` and `A_i → A_i/α`, every level inflates
by 1/α, and **every contrast ratio is exactly unchanged** — the factor cancels.

Verified empirically: gynecologic oncology's national mean moves by an observed
factor of **2.3044** against a predicted 1/α = **2.3043**.

That has a sharp consequence. Because the uniform case changes nothing, **any**
movement in a disparity is attributable entirely to *spatial and between-group
variation in age composition*. The analysis is not a test of whether access
differs. It is a test of whether age structure covaries with the geography of
access strongly enough to move a disparity.

### The falsifiable prediction, and 7 of 7

The American Indian and Alaska Native female population is younger:

| Age window | White NH | AIAN | ratio ρ |
|---|---:|---:|---:|
| under 20 | 0.2012 | 0.2867 | **1.425** |
| 45 and over | 0.5018 | 0.3665 | **0.730** |

So the contrast must move in the direction of −sign(ρ − 1): age-matching should
*widen* the disparity wherever the window favours younger women and *narrow* it
wherever it favours older women.

**The direction was predicted correctly in 7 of 7 subspecialties.** The shifts
are not noise; they are the mechanical consequence of a younger age structure
meeting a narrower age window. And the disparity persists under every window.

### What it cost

- **C2 held.** **C3 held.**
- **C5 failed.** The subspecialty ordering `MFM > GO > REI` becomes
  `MFM > REI > GO` once denominators are age-matched.

A robustness claim in the paper did not survive an analysis we chose to run on
ourselves.

---

## 4. A prespecified multiverse falsified one of our own claims

Before computing any outcome, the entire grid of analytic choices was frozen and
hash-locked, so no specification could be quietly added or dropped after seeing
which ones were flattering.

**Claim C4 failed** — it held in 5 of 7 specifications and broke under the
slower-decay and M2SFCA variants. The abstract was corrected.

The design principle worth narrating: the pipeline is explicitly built **not**
to fail merely because a finding is fragile. Fragility is reported as a
scientific result, not hidden as a defect. The only thing that fails the build
is claiming robustness you do not have.

---

## 5. The mutation corpus that silently reverted a real fix

A mutation-testing harness rewrites source files, runs the tests, and restores
the originals. Ours restored a **stale** copy over a genuine bug fix that had
landed while the corpus was mid-run. The repository ended up with the fix
reverted and every test still green, because the tests were passing against the
old file.

Commit `f96a7a1` is literally titled *"restore #10, which my mutation corpus
silently reverted."*

The corpus now verifies that every mutated source is restored **byte-identical**,
and CI fails if the working tree is dirty after the corpus runs.

---

## 6. Gates that existed and protected nothing

An audit mapped every check script in the repository against what actually
invoked it. Several were theatre:

- **`scientific_diff.R`** — the strongest gate in the repo, guarding all 47
  reported headline numbers against a committed baseline. **No workflow ran it.
  Ever.**
- **`check_wordcount.R`** — documented in the README as quality assurance,
  wired into nothing, and incapable of failing: it printed the count and exited
  zero regardless. Once wired, it immediately caught the abstract at **309 words
  against a 300-word journal limit** — it had grown back past the cap after an
  earlier trim and nobody noticed.
- **`check_cross_references.R`** — could not fail on its own subject, had a
  broken shebang (`#!/usr/env/bin`), silently did nothing when run without an
  argument, and misread the phrase "**Figure provenance.**" as a numbered figure.
- **`render_appendix.sh`** — every chunk was `file.exists()`-guarded, so
  rendering without the (deliberately uncommitted) caches **succeeded** and
  emitted a supplement with its results tables, invariance check and prediction
  table silently missing.

The unifying lesson, and the reason this section exists:

> **A successful run that produces scientifically incomplete output is more
> dangerous than an obvious crash.** A crash gets fixed. A green check that
> verified nothing gets trusted.

---

## 7. The file the paper actually reads had no invariants

The manuscript does not read the engine. It reads
`e2sfca_national_summary.csv`. That file's only protection was a SHA-256 hash.

A hash answers *"was this edited?"*. It cannot answer the question that actually
threatens a paper: *when the artifact is legitimately regenerated — new run, new
hash, honest intent — does anything notice the numbers are impossible?*

So we wrote ten corruptions that each tell a plausible scientific lie: a
fabricated 25% improvement, non-monotone threshold shares, unconserved
population, a swapped subspecialty label that reverses which specialty is worst,
a shifted year that turns a decline into an increase. Then we required the
invariants — **not** the hash — to catch every one.

They do: 10 of 10.

Two of those lies keep the table perfectly valid on its face; nothing internal
can see them. What catches those is agreement with an *independently produced*
artifact.

---

## 8. Provenance rescued from a deletion

A 205 MB directory was slated for deletion as stray output. It was not stray. It
held the input and output provenance for the exact frozen run the manuscript
reads — including checksums for all inputs and outputs, and the authentic
`step_3_year_coord_map.rds`.

There is a sharp footnote. An earlier search had picked a
`step_3_year_coord_map.rds` by filesystem search; it hashed to a **different
file**. The lineage was eventually recovered by pairing the year-coord map and
the cohort file **from the same run directory** — the earlier attempt had mixed
files across directories and produced a plausible near-miss (612/516/63 against
the true 624/532/66) that looked like evidence and was not.

Provider counts turned out to be an exact and cheap lineage fingerprint.

---

## Themes worth building the story around

1. **Aggregate checks cannot see localized failures.** 98.9% national coverage,
   0% Connecticut coverage.
2. **Silence is the enemy.** Missing data became zero; supply with no catchment
   evaporated; a hollow appendix rendered cleanly.
3. **The tools that check the work need checking too.** Gates that never ran,
   gates that could not fail, and a mutation harness that corrupted the thing it
   was testing.
4. **Run the analysis you are afraid of.** The reproduction attempt found a real
   bug. The multiverse falsified a claim. The age-matched denominators broke an
   ordering. Every one of those was self-inflicted, on purpose.
5. **A near-miss is not a hit.** 612/516/63 looked close enough to believe.
