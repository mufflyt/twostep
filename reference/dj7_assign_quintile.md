# Assign a tract to a Desjardins accessibility category.

Category 1 = zero-access tracts (\`access \<= 0\`); categories 2-5 =
quartiles of the strictly-positive access distribution. Reproduces the
\`case_when\` in script 00. NA access is treated as zero (category 1).

## Usage

``` r
dj7_assign_quintile(access, brk = NULL)
```

## Arguments

- access:

  numeric per-tract accessibility. Use the algebraic (zero-filled) form;
  see the section above.

- brk:

  optional length-3 quartile cut points of the positive distribution;
  computed from \`access\` when NULL.

## Value

integer vector in 1:5.

## Which column to pass

Pass \`compute_e2sfca()\$access\$access_math\`, not \`\$access\`. Since
that function began distinguishing a measured zero from a tract outside
every modelled catchment, its public \`access\` column is \`NA\` for the
latter – 190 of 1,447 Colorado tracts on a rare-subspecialty surface.
Feeding those \`NA\`s here silently files them under category 1,
"zero-access", which reintroduces exactly the conflation upstream now
avoids.

The \`NA -\> 0\` rule below is retained deliberately because this
function reproduces the published Desjardins categorisation, in which
the input is already a complete zero-filled vector. It is not a
judgement that unmeasured and zero are the same thing.
