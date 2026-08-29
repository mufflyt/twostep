#!/usr/bin/env bash
# =============================================================================
# Resolve the pinned RUCA inputs by hash, fetching from S3 if absent
# =============================================================================
# run_panel.sh, fetch_age_bands_panel.sh and ec2_run_age_matched.sh all used to
# name these files by absolute local path:
#
#   /Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping.csv
#
# That is the same failure class the clean room exposed with the ACS denominator
# cache, and the one that put the WRONG isochrone set into a four-day analysis: a
# load-bearing scientific input identified by where it sits rather than by what
# it is. It is especially dangerous here, because two RUCA files on this machine
# share an identical row count of 85,528 with different hashes -- a row-count
# check passes on the wrong one.
#
# Usage:  eval "$(bash tools/multiverse/resolve_ruca.sh)"
#   exports RUCA_2010 and RUCA_2020, or exits non-zero having explained why.
#   Override the cache location with E2SFCA_RUCA_DIR.
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 1; }
MAN="$ROOT/inst/multiverse/ruca_inputs.json"
DIR="${E2SFCA_RUCA_DIR:-$ROOT/artifacts/2sfca/ruca}"
[ -f "$MAN" ] || { echo "::error::RUCA manifest missing: $MAN" >&2; exit 1; }

PFX=$(python3 -c "import json;print(json.load(open('$MAN'))['s3_prefix'])")
mkdir -p "$DIR"

need_fetch=0
while read -r name want; do
  if [ ! -f "$DIR/$name" ]; then need_fetch=1; continue; fi
  got=$(shasum -a 256 "$DIR/$name" | awk '{print $1}')
  [ "$got" = "$want" ] || need_fetch=1
done < <(python3 -c "
import json
for f in json.load(open('$MAN'))['files']: print(f['name'], f['sha256'])")

if [ "$need_fetch" -eq 1 ]; then
  echo "# fetching pinned RUCA from $PFX" >&2
  aws s3 sync "$PFX" "$DIR/" --region us-west-2 --quiet || {
    echo "::error::could not fetch pinned RUCA from $PFX" >&2; exit 1; }
fi

# Verify unconditionally, including after a fetch. A sync that reports success
# is not evidence: this environment silently truncates large S3 transfers, and
# the whole point of pinning is that size and name prove nothing.
bad=0
while read -r name want; do
  if [ ! -f "$DIR/$name" ]; then echo "::error::missing after fetch: $name" >&2; bad=1; continue; fi
  got=$(shasum -a 256 "$DIR/$name" | awk '{print $1}')
  if [ "$got" != "$want" ]; then
    echo "::error::$name hash mismatch" >&2
    echo "         want $want" >&2
    echo "         got  $got" >&2
    bad=1
  fi
done < <(python3 -c "
import json
for f in json.load(open('$MAN'))['files']: print(f['name'], f['sha256'])")
[ "$bad" -eq 0 ] || { echo "::error::pinned RUCA not verified; refusing to proceed" >&2; exit 1; }

echo "export RUCA_2010='$DIR/ruca_tract_mapping_2010.csv'"
echo "export RUCA_2020='$DIR/ruca_tract_mapping.csv'"
echo "# RUCA verified by sha256 against inst/multiverse/ruca_inputs.json" >&2
