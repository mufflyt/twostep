# Accessibility-disparity statistics re-exported from mufflyaccess

These objects are not defined here. They are bound live to the
implementations in the shared mufflyaccess package, the single source of
truth across isochrones / twostep / cliff, so cross-repo drift is
impossible. They are re-exported under their original names so code that
\`source()\`s this file keeps working unchanged. See the mufflyaccess
documentation for the full argument and return contracts.

## Objects

- \`weighted_mean_all\`:

  Population-weighted mean across all tracts.

- \`zero_access_share\`:

  Population share with zero modelled access.

- \`rurality_from_ruca\`:

  Map RUCA codes to a rurality class.

- \`tract_vintage_of\`:

  Census-tract vintage for an analysis year.

- \`acs_year_of\`:

  ACS 5-year vintage for an analysis year.

- \`mc_weighted_ci\`:

  Monte-Carlo CI for a weighted statistic.

- \`annual_trend\`:

  Annual trend estimate over the study period.

- \`TOTAL_FEMALE_VAR\`:

  ACS variable for the total female denominator.

- \`RACE_FEMALE_VARS\`:

  ACS variables for race-stratified female denominators.

- \`RUCA_NONMETRO_MIN\`:

  Minimum RUCA code counted as non-metro.

## See also

The guards in \`tests/testthat/test-accessibility-stratification.R\` and
\`tests/testthat/test-mufflyaccess-consistency.R\`.
