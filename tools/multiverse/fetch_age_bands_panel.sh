#!/usr/bin/env bash
# Fetch + build age-matched denominators for every ACS vintage 2013-2023.
# Sequential on purpose: the work is network-bound on the Census API, and the
# machine is a shared 4-core box. Each year is independent and cached, so this
# is resumable -- a year already built is skipped by the script's own cache.
set -uo pipefail
cd "$(dirname "$0")/../.."
RUCA_2020=/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping.csv
RUCA_2010=/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping_2010.csv
ok=0; fail=0
for Y in 2013 2014 2015 2016 2017 2018 2019 2021 2022 2023; do
  # RUCA vintage must match the tract vintage or the rurality join silently
  # drops tracts -- the Connecticut lesson, generalised.
  if [ "$Y" -le 2019 ]; then R="$RUCA_2010"; else R="$RUCA_2020"; fi
  OUT="artifacts/2sfca/sensitivity/cache/age_matched_denominators_${Y}.rds"
  if [ -f "$OUT" ]; then echo "[panel] $Y already built, skipping"; ok=$((ok+1)); continue; fi
  echo "[panel] ===== $Y (ruca=$(basename "$R")) ====="
  if E2SFCA_AM_YEAR="$Y" E2SFCA_RUCA_PATH="$R" \
     R_PROFILE_USER=/dev/null RENV_CONFIG_AUTOLOADER_ENABLED=false \
     Rscript tools/multiverse/age_matched_denominators.R 2>&1 | grep -vE "Getting data|receive"; then
    echo "[panel] $Y OK"; ok=$((ok+1))
  else
    echo "[panel] $Y FAILED"; fail=$((fail+1))
  fi
done
echo "[panel] denominators complete: $ok ok, $fail failed"
