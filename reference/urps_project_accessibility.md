# Project accessibility across URPS workforce scenarios

The orchestration entry point. For each (\`scenario_id\`, \`year\`) in
the requested grid, allocate that scenario's national supply to CONUS
states (\[urps_scenario_supply()\]), optionally distribute it onto
baseline provider origins (\[urps_allocate_origins()\]), hand the supply
to \`accessibility_fn\`, and stack the returned per-scenario-year
accessibility metrics into one long, contract-keyed table.

## Usage

``` r
urps_project_accessibility(
  projection,
  accessibility_fn,
  baseline_origins = NULL,
  scenarios = NULL,
  years = NULL,
  basis = c("headcount", "clinical_fte"),
  weights = NULL,
  ...
)
```

## Arguments

- projection:

  A projection file path or a validated projection \`data.frame\`.

- accessibility_fn:

  \`function(supply, scenario_id, year, ...)\` -\> \`data.frame\`.

- baseline_origins:

  Optional baseline per-origin supply (see \[urps_allocate_origins()\]);
  when given, \`accessibility_fn\` receives engine-ready
  \`data.frame(coord_id, supply)\`.

- scenarios:

  Character vector of scenario ids; \`NULL\` runs every scenario in the
  projection.

- years:

  Integer vector of years; \`NULL\` runs every year in the projection.

- basis:

  \`"headcount"\` (default) or \`"clinical_fte"\`.

- weights:

  Optional allocation weights forwarded to the allocator.

- ...:

  Extra arguments forwarded to \`accessibility_fn\` (e.g. the overlap
  table, tract population, band weights).

## Value

A long \`data.frame\`: \`accessibility_fn\`'s columns prefixed with
\`scenario_id\` and \`year\`, row-bound across the grid. Scenario ids
are validated against the SSOT registry before any compute runs.

## Details

\`accessibility_fn\` is the seam between this deterministic wiring and
the geospatial engine. Signature: \`function(supply, scenario_id, year,
...)\` -\> \`data.frame\`. When \`baseline_origins\` is supplied,
\`supply\` is the per-origin \`data.frame(coord_id, supply)\` that
\`compute_e2sfca()\` consumes; otherwise it is the per-state
\[urps_scenario_supply()\] frame. Tests inject a lightweight
deterministic stub so the orchestration is verifiable without sf/terra.

## See also

\[urps_scenario_supply()\], \[urps_allocate_origins()\],
\`mufflyaccess::urps_scenarios()\`
