# Provider supply per origin for one (subspecialty, year) cell.

Supply S_j = the count of active subspecialists located at origin
\`coord_id\` in the given year. Reads the per-(npi, year) temporal panel
(\`step_3_year_coord_map.rds\`), which already carries \`coord_id\`, and
joins the cohort to resolve the canonical subspecialty code.

## Usage

``` r
compute_provider_supply(
  year_coord_map,
  cohort,
  subspecialty_code,
  year,
  subspec_col = "subspecialty_normalized"
)
```

## Arguments

- year_coord_map:

  tibble with at least \`npi\`, \`analysis_year\`, \`coord_id\`,
  \`match_source\`.

- cohort:

  tibble with \`npi\` and a subspecialty column
  (\`subspecialty_normalized\`, values like "GO","MFM",...).

- subspecialty_code:

  Canonical short code to select (e.g. "GO").

- year:

  Analysis year (integer).

- subspec_col:

  Name of the subspecialty column in \`cohort\` (default
  "subspecialty_normalized").

## Value

tibble with \`coord_id\` and \`supply\` (integer count of distinct
NPIs), only origins with supply \> 0.

## Details

Placeholder rows (\`match_source\` NA) are dropped — they are not real
locations (CLAUDE.md \#19, Trust-a-Number / provenance).

## References

Supply S_j is the provider term of step 1 in Luo & Wang (2003)
doi:10.1068/b29120 \[source 1\]. The per-(npi, year) panel realizes the
temporal-2SFCA design of Paul & Edwards (2019) doi:10.1002/hpm.2667
\[source 9\]: the cohort inside each year's catchments varies by year.
Dropping match_source = NA placeholder rows enforces CLAUDE.md \#19
(Trust-a-Number): a non-real location must never inflate supply.

## See also

\[compute_e2sfca\]

Other E2SFCA computation:
[`compute_band_tract_overlap()`](https://mufflyt.github.io/twostep/reference/compute_band_tract_overlap.md),
[`compute_e2sfca()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca.md),
[`compute_e2sfca_raster()`](https://mufflyt.github.io/twostep/reference/compute_e2sfca_raster.md),
[`e2sfca_cell_summaries()`](https://mufflyt.github.io/twostep/reference/e2sfca_cell_summaries.md)
