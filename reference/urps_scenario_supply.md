# National URPS supply for one scenario-year, allocated to CONUS states

Takes cliff's projection table and returns the provider supply a given
\`scenario_id\` implies in a given \`year\`, allocated from the national
total to the 49 CONUS states (+ DC) with the shared weights in
\`mufflyaccess::urps_allocate_national()\`.

## Usage

``` r
urps_scenario_supply(
  projection,
  scenario_id,
  year,
  basis = c("headcount", "clinical_fte"),
  weights = NULL
)
```

## Arguments

- projection:

  A projection file path (read + validated via the SSOT) or an
  already-validated projection \`data.frame\` (the cliff artifact /
  contract).

- scenario_id:

  A single registered scenario id
  (\`mufflyaccess::urps_scenario_ids()\`).

- year:

  A single projection year present in the table.

- basis:

  \`"headcount"\` (default) or \`"clinical_fte"\` – which supply measure
  to allocate. Fractional clinical-FTE is rounded before integer
  allocation; the pre-rounding value is returned in \`national_supply\`.

- weights:

  Optional allocation weights forwarded to
  \`mufflyaccess::urps_allocate_national()\`; \`NULL\` uses the SSOT
  default.

## Value

A \`data.frame\`, one row per CONUS state: \`scenario_id\`, \`year\`,
\`basis\`, \`state_abbr\`, \`state_fips\`, \`supply\` (integer,
allocated), and \`national_supply\` (the unrounded national total).
\`supply\` sums to the rounded national total – allocation is
mass-conserving.

## See also

\[urps_allocate_origins()\], \[urps_project_accessibility()\],
\`mufflyaccess::urps_allocate_national()\`
