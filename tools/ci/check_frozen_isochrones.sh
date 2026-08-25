#!/usr/bin/env bash
# Verify E2SFCA_ISO_DIR holds the FROZEN isochrone set, by hash, before any year runs.
#
# Changing run_panel.sh to a different local path would have fixed today's wrong
# directory and left the same failure mode available tomorrow: nine isochrone
# directories exist across this machine and the Samsung drive, none of them the
# frozen set, and nothing about a path tells you which you have. Only the hash does.
set -uo pipefail
PIN="${FROZEN_ISO_PIN:-inst/multiverse/frozen_isochrones.sha256}"
DIR="${1:-${E2SFCA_ISO_DIR:-}}"

[ -n "$DIR" ] || { echo "::error::E2SFCA_ISO_DIR is unset"; exit 1; }
[ -f "$PIN" ] || { echo "::error::pin file missing: $PIN"; exit 1; }
[ -d "$DIR" ] || { echo "::error::isochrone dir does not exist: $DIR"; exit 1; }

bad=0; n=0
while read -r want f; do
  case "$want" in \#*|"") continue ;; esac
  n=$((n+1))
  p="$DIR/$f"
  if [ ! -f "$p" ]; then
    echo "  MISSING  $f"; bad=1; continue
  fi
  got=$(shasum -a 256 "$p" | awk '{print $1}')
  if [ "$got" != "$want" ]; then
    echo "  WRONG    $f"
    echo "           want $want"
    echo "           got  $got"
    bad=1
  else
    echo "  ok       $f"
  fi
done < "$PIN"

if [ "$bad" -ne 0 ]; then
  cat >&2 <<MSG
::error::E2SFCA_ISO_DIR is not the frozen isochrone set: $DIR
  The frozen set is staged at
    s3://tyler-valhalla-tiles/seam_run/inputs/isochrones/
  Fetch it, then re-run:
    aws s3 sync s3://tyler-valhalla-tiles/seam_run/inputs/isochrones/ "$DIR"
  Running the panel against any other set reintroduces the dropped-supply defect.
MSG
  exit 1
fi
echo "frozen isochrone set verified ($n files)"
