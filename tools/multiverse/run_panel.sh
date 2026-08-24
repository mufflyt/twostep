#!/usr/bin/env bash
# Run the age-matched E2SFCA panel for every ACS vintage 2013-2023.
#
# SEQUENTIAL AND NICED ON PURPOSE. This is a 4-core machine that is usually
# already carrying other work, and over-parallelising this exact pipeline once
# drove it to load 118, at which point a 14-cell run was taking 64 min/cell.
# One year at a time, at low priority, is slower in theory and faster in
# practice.
#
# RESUMABLE. A year whose results CSV already exists is skipped, so an
# interrupted run continues where it stopped rather than starting over.
#
# 2020 is deliberately NOT in the list: it is already computed and committed at
# artifacts/multiverse/age_matched_results.csv, and re-running it would rewrite
# the file the manuscript and appendix read.
set -uo pipefail
cd "$(dirname "$0")/../.."

export S="artifacts/2sfca/agematched_panel"
export E2SFCA_ISO_DIR="/Users/tylermuffly/isochrones/artifacts/isochrones"
RUCA_2020="/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping.csv"
RUCA_2010="/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping_2010.csv"

# Fail before spending hours if an input is absent.
for f in "$E2SFCA_ISO_DIR/isochrones_30min_consolidated.rds" "$RUCA_2020" "$RUCA_2010"; do
  [ -f "$f" ] || { echo "::error::missing required input: $f" >&2; exit 1; }
done
[ -d "$S/sup/run_e2sfca_20260712_190734" ] || {
  echo "::error::supply directory missing: $S/sup/run_e2sfca_20260712_190734" >&2; exit 1; }

YEARS="${PANEL_YEARS:-2013 2014 2015 2016 2017 2018 2019 2021 2022 2023}"
ok=0; failed=0; skipped=0
echo "[panel-run] years: $YEARS"

for Y in $YEARS; do
  OUT="artifacts/multiverse/age_matched_results_${Y}.csv"
  if [ -f "$OUT" ]; then
    echo "[panel-run] $Y already done, skipping"; skipped=$((skipped+1)); continue
  fi
  # RUCA vintage must match the tract vintage, or the rurality join silently
  # drops tracts -- the Connecticut failure, generalised.
  if [ "$Y" -le 2019 ]; then R="$RUCA_2010"; else R="$RUCA_2020"; fi

  DEN="artifacts/2sfca/sensitivity/cache/age_matched_denominators_${Y}.rds"
  [ -f "$DEN" ] || { echo "[panel-run] $Y SKIPPED: denominators not built ($DEN)"; failed=$((failed+1)); continue; }

  echo "[panel-run] ===== $Y (ruca=$(basename "$R")) ====="
  t0=$(date +%s)
  if nice -n 10 env E2SFCA_AM_YEAR="$Y" E2SFCA_RUCA_PATH="$R" \
       R_PROFILE_USER=/dev/null RENV_CONFIG_AUTOLOADER_ENABLED=false \
       Rscript tools/multiverse/run_age_matched.R 2>&1 | tr '\r' '\n' | grep -vE "^\s*\|"; then
    dt=$(( $(date +%s) - t0 ))
    echo "[panel-run] $Y OK in $((dt/60))m$((dt%60))s"
    ok=$((ok+1))
  else
    echo "[panel-run] $Y FAILED"; failed=$((failed+1))
  fi
done
echo "[panel-run] complete: $ok ok, $skipped skipped, $failed failed"
