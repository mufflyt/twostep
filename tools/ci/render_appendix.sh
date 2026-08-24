#!/usr/bin/env bash
# Render the age-matched denominator technical appendix to Word.
#
# Source of truth is the .Rmd: every table and every number in it is COMPUTED
# from the frozen manifest and the analysis artifacts, not typed. Re-run this
# after the analysis completes and the results section fills itself in.
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC="manuscript/appendix_age_matched_denominators.Rmd"
OUT="manuscript/appendix_age_matched_denominators.docx"
[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

# Every live chunk in the appendix is guarded with file.exists(), so a render
# without these inputs SUCCEEDS and quietly emits a document whose results
# tables, invariance check and 7-of-7 prediction table are simply absent. A
# hollow supplement that renders cleanly is worse than a build error, so refuse
# to produce one. (Two of these are ~5.5 MB caches that are deliberately not
# committed, which is also why the appendix render is not run in CI.)
missing=0
for f in artifacts/multiverse/age_matched_results.csv \
         artifacts/2sfca/sensitivity/cache/age_matched_denominators.rds \
         artifacts/2sfca/sensitivity/cache/acs2020_age_bands.rds \
         inst/multiverse/age_matched_denominator.yml \
         manuscript/figures/fig_age_matched_denominators.jpg; do
  [ -f "$f" ] || { echo "ERROR: appendix input missing: $f" >&2; missing=1; }
done
[ "$missing" -eq 0 ] || {
  echo "Refusing to render a supplement with sections silently omitted." >&2
  echo "Rebuild the inputs first:" >&2
  echo "  Rscript tools/multiverse/age_matched_denominators.R" >&2
  echo "  Rscript tools/multiverse/run_age_matched.R" >&2
  echo "  Rscript tools/multiverse/plot_age_matched.R" >&2
  exit 1; }
R_PROFILE_USER=/dev/null RENV_CONFIG_AUTOLOADER_ENABLED=false \
  Rscript -e 'rmarkdown::render("'"$SRC"'", output_format = "word_document", quiet = TRUE)'
[ "$(stat -f %m "$OUT")" -ge "$(stat -f %m "$SRC")" ] || {
  echo "ERROR: the DOCX is older than its source" >&2; exit 1; }
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
