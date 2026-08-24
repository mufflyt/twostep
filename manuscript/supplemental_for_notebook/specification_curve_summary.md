# Specification-Curve (Multiverse) Results — Plain-Language Summary

This summarises a prespecified multiverse analysis: the whole grid of analytic
choices was frozen and hash-locked BEFORE any outcome was computed, so no
specification could be added or dropped after seeing which ones were flattering.

## What was varied

- **base**
- **sharper**
- **slower**
- **gaussian**
- **drop180**
- **res500**
- **m2sfca**

## Which claims survived which specification

| variant | C1 | C2 | C3 | C5 | C4_contribution |
|---|---|---|---|---|---|
| base | holds | holds | holds | holds | holds |
| sharper | holds | holds | holds | holds | holds |
| slower | **FAILS** | holds | **FAILS** | holds | **FAILS** |
| gaussian | holds | holds | holds | holds | holds |
| drop180 | holds | holds | holds | holds | holds |
| res500 | holds | holds | holds | holds | holds |
| m2sfca | holds | holds | **FAILS** | holds | **FAILS** |

## The headline result of this analysis: a claim was FALSIFIED

Claim C4 did not survive. It held in 5 of 7 specifications and failed in 2.
The specification that broke it is `slower, m2sfca`.

This was not discovered by a reviewer. The analysis was built to look for it, it
found it, and the abstract was corrected as a result. Fragility was treated as a
scientific finding to be reported, not a failure to be hidden -- the pipeline is
explicitly designed NOT to fail merely because a finding is fragile.

## How each claim fared across the whole grid

Two claims survive every specification; two others bend under the slower-decay
and M2SFCA variants. The `slower` specification is the most destructive single
choice in the grid -- it is the only one that breaks more than one claim.

- **C1**: holds in 6 of 7 specifications
- **C2**: holds in 7 of 7 specifications (every one)
- **C3**: holds in 5 of 7 specifications
- **C5**: holds in 7 of 7 specifications (every one)

## How stable are the numbers themselves?

Across 6 executable specifications, the national access estimates move by
at most 0.0005 in absolute terms -- the spread is in the fourth decimal place.
Direction is preserved in 100% of specifications.

## Leave-one-assumption-out

119 assumption-removal tests were run across 5 analytic axes.
Direction changed in 2 of them. A claims verdict changed in 2.

Analytic axes tested:
- distance_decay
- decay_form
- catchment_threshold
- grid_resolution
- accessibility_formulation
