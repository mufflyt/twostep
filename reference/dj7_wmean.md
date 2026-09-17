# Population-weighted mean over positive weights.

Reproduces the \`wm()\` helper in scripts 06/09/13: it sums over
elements with strictly-positive, non-NA weight. For non-negative finite
weights this equals \[accessibility_stratification::weighted_mean_all\]
(zero-weight elements contribute nothing to either numerator or
denominator); the suite asserts that equivalence so the two libraries
cannot silently diverge.

## Usage

``` r
dj7_wmean(x, w)
```

## Arguments

- x:

  numeric values.

- w:

  numeric weights (same length).

## Value

weighted mean, or NA if no positive weight remains.
