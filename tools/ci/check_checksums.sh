#!/usr/bin/env bash
# Data + artifact integrity.
#
# SHA256SUMS.txt pins committed artifacts, and data/PROVENANCE_vendored_inputs.md
# pins the vendored analysis inputs by sha256 prefix. Those files are addressed by
# literal repo path from scripts/, the shiny app and the provenance manifests, and
# they are build-excluded, so NOTHING else in CI would notice if one changed. A
# silently mutated input is the worst failure mode in this repo: the pipeline still
# runs and quietly produces different numbers.
set -uo pipefail
status=0

if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
echo "using: $SHA"

echo "--- SHA256SUMS.txt ---"
if [ ! -f SHA256SUMS.txt ]; then
  echo "FAIL: SHA256SUMS.txt is missing"; exit 1
fi
n=$(grep -c . SHA256SUMS.txt)
if ! $SHA -c SHA256SUMS.txt > /tmp/sha_out 2>&1; then
  echo "FAIL: checksum mismatch or missing file"
  grep -v ': OK$' /tmp/sha_out | head -20
  status=1
else
  echo "OK: all $n pinned artifacts match"
fi

echo "--- data/PROVENANCE_vendored_inputs.md ---"
PROV="data/PROVENANCE_vendored_inputs.md"
if [ ! -f "$PROV" ]; then
  echo "FAIL: $PROV is missing"; exit 1
fi
# Rows look like: | `file.rds` | `39dda36fccdaf851...` | source | consumed by |
while IFS= read -r row; do
  file=$(echo "$row" | sed -E 's/^\| *`([^`]+)`.*/\1/')
  claim=$(echo "$row" | sed -E 's/^\|[^|]*\| *`([0-9a-f]+)\.\.\.`.*/\1/')
  [ "$file" = "$row" ] && continue
  [ -z "$claim" ] && continue
  path="data/$file"
  if [ ! -f "$path" ]; then
    echo "FAIL: $path listed in provenance but absent"; status=1; continue
  fi
  actual=$($SHA "$path" | cut -d' ' -f1)
  if [ "${actual:0:${#claim}}" = "$claim" ]; then
    echo "OK: $file matches pinned prefix $claim"
  else
    echo "FAIL: $file sha256 is ${actual:0:${#claim}}, provenance claims $claim"
    status=1
  fi
done < <(grep -E '^\| *`[^`]+` *\| *`[0-9a-f]+\.\.\.`' "$PROV")

echo "--- inst/shiny/access_explorer/provenance.txt ---"
# The shiny app pins the exact inputs it renders. If these drift from the data on
# disk the app silently plots numbers that no longer match its own manifest.
SHINY_PROV="inst/shiny/access_explorer/provenance.txt"
if [ ! -f "$SHINY_PROV" ]; then
  echo "FAIL: $SHINY_PROV is missing"; exit 1
fi
m=$(grep -c . "$SHINY_PROV")
if ! $SHA -c "$SHINY_PROV" > /tmp/shiny_sha_out 2>&1; then
  echo "FAIL: shiny provenance mismatch"
  grep -v ': OK$' /tmp/shiny_sha_out | head -10
  status=1
else
  echo "OK: all $m shiny-pinned inputs match"
fi

if [ "$status" -eq 0 ]; then
  echo "--- all provenance manifests agree with the files on disk ---"
fi
exit $status
