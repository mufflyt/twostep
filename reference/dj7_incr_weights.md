# Incremental band weights for the E2SFCA demand step.

\\w'\_b = W_b - W\_{b+1}\\ for every band except the outermost, where
\\w'\_{last} = W\_{last}\\. The demand assigned to an origin is \\D_j =
\sum_b w'\_b \cdot \mathrm{cumpop}\_b(j)\\ over the NESTED cumulative
isochrone populations, which telescopes back to the cumulative weights
used for the access step. Guards the historical "mangled name" bug:
writing \`c(\\30\\ = Wc\["30"\] - Wc\["60"\])\` inherited the name "30"
from the RHS and produced the label "30.30", so \`Wi\[\["30"\]\]\`
failed. Here the values are stripped of names before relabelling.

## Usage

``` r
dj7_incr_weights(Wc)
```

## Arguments

- Wc:

  length-4 cumulative band weights (names are the band minutes).

## Value

length-4 numeric, names = \`names(Wc)\`, values un-mangled.
