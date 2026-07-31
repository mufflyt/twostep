# Accessibility Scenario Cube (twostep)

The precomputation contract for turning twostep from a present-day accessibility
view into a **scenario-planning** product, borrowing NurseCast's key engineering
decision: **precompute every supported combination and serve frozen slices**, so
the Shiny app never reruns the E2SFCA computation reactively.

Companion to [`REPO_CHARTERS.md`](REPO_CHARTERS.md),
[`data-ownership.md`](data-ownership.md). No code or numbers asserted here; this is
the table twostep produces (upstream, frozen) and the app consumes (a slice at a time).

## The one canonical table

A long "cube", one row per fully-specified cell:

| column | meaning |
|---|---|
| `year` | projection year (baseline year .. horizon) |
| `specialty` | OB/GYN subspecialty (URPS, ...) |
| `scenario_id` | named scenario (see below); `baseline` is required |
| `travel_time_band` | 30 / 60 / 120 / 180 min |
| `geography_type` | national / conus / state / county / tract |
| `geography_id` | FIPS or "US" |
| `provider_definition` | which supply cohort (see below) |
| `measure_kind` | `headcount` or `clinical_fte` (kept SEPARATE, never merged) |
| `metric` | the accessibility metric (see below) |
| `value` | the metric value |
| `lower_95`, `upper_95` | uncertainty interval (widens with horizon) |

`provider_definition` enumerations: `abog_only`, `abu_net_new`, `abog_plus_abu`,
`active_roster`, `modeled_clinical_workforce`.

`metric` enumerations (all **descriptive, non-normative**):
`providers_within_band`, `clinical_fte_within_band`, `population_within_band`,
`e2sfca_score`, `change_from_baseline`, `percentile_rank`, `zero_access_indicator`,
`population_per_provider`.

## Change from baseline

The scenario-planning quantity is a difference against the baseline scenario at the
same cell (geography, year, band, provider definition, measure):

```
change_from_baseline[g,t,s] = value[g,t,s] - value[g,t,"baseline"]
```

stored as its own `metric = change_from_baseline` rows so the app reads it, never
recomputes it.

## Scenarios (baseline + named alternatives)

Following NurseCast: a visible baseline plus a small set of named alternatives, not
dozens of unconstrained sliders. The supply side of each scenario is produced by
**cliff** (see `cliff/docs/urps-workforce-projection-spec.md`); twostep layers
accessibility on top. Minimum set:

- `baseline` (required)
- `earlier_exit_2y`, `earlier_exit_5y`, `later_exit_2y`
- `fellowship_plus_10`, `fellowship_constrained`
- `lower_late_career_fte`
- `combined_pessimistic`, `combined_investment`

## Language: describe, do not adjudicate need

E2SFCA is a modeled supply-to-demand ratio, NOT need, adequacy, or shortage. The
`metric` vocabulary above is deliberately descriptive. Do **not** relabel any cell
"shortage", "surplus", "adequate/adequacy", or "need met/unmet" without a defensible
normative demand target (there is none). Enforced by
`R/access_language.R::assert_access_language()` and
`tests/testthat/test-access-language-guard.R`. Prefer: modeled accessibility,
relative accessibility, projected supply-demand difference, change from baseline,
population-to-clinical-FTE ratio.

## What twostep does and does not own

- **twostep produces** the accessibility slices of the cube (`e2sfca_score`,
  `*_within_band`, `change_from_baseline`) by combining cliff's scenario supply +
  isochrones' travel-time exposure + its own ACS demand, on the **same geography**
  (`assert_matching_geography()`).
- **twostep does not own** the workforce projection (cliff) or the served baseline
  counts (mufflyaccess `urps_count()`), and never hardcodes them.
- The app **reads a frozen slice** of the cube (one scenario x metric x geography x
  band) and renders it. Startup stays fast, memory stays low, geometry rendering
  does not recompute, and the three apps cannot silently diverge because they all
  read the same published cube.

## App read pattern

```
cube slice := filter(cube,
  specialty == S, scenario_id == SC, travel_time_band == B,
  geography_type == GT, provider_definition == PD,
  measure_kind == MK, metric == M)
```

The cube is expected at `artifacts/2sfca/scenario_cube.parquet` (or `.csv`); the
Access Explorer's Scenarios tab gates until it is staged, exactly like the map tab.

## What NOT to copy from NurseCast

- Do NOT assume baseline supply equals demand (NurseCast does this where vacancy
  data are missing; too strong for national urogynecology).
- Do NOT use a single deterministic retirement age; use age-specific exit / FTE.
- Do NOT model demand at county-only resolution; twostep is tract + drive-time.
- Do NOT run the microsimulation inside the Shiny process; consume frozen outputs.
- Do NOT port the JS stack; the transferable lesson is **precomputation**, not Svelte/Node.
