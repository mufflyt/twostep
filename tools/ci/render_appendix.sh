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
R_PROFILE_USER=/dev/null RENV_CONFIG_AUTOLOADER_ENABLED=false \
  Rscript -e 'rmarkdown::render("'"$SRC"'", output_format = "word_document", quiet = TRUE)'
[ "$(stat -f %m "$OUT")" -ge "$(stat -f %m "$SRC")" ] || {
  echo "ERROR: the DOCX is older than its source" >&2; exit 1; }
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
