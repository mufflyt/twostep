#!/usr/bin/env bash
# =============================================================================
# Release audit: one top-to-bottom pass over everything that must hold
# =============================================================================
# The nightly and the PR gate each run a SUBSET of the gates, split across jobs
# for parallelism. That is right for CI and wrong for a freeze decision: no
# single place answers "is this SHA publishable?" without reading four workflow
# runs and reconciling them by hand.
#
# This runs every gate against the working tree, records each exit code, and
# reports one verdict. It deliberately does NOT stop on first failure -- a
# freeze decision needs the whole picture, not the first thing that broke. A
# run that halts at gate 3 tells you nothing about gates 4 through 19, and the
# temptation is then to fix one thing and re-run, learning the failures one at
# a time over an hour.
#
# Usage: bash tools/ci/release_audit.sh
# Exit:  0 if every gate passes, 1 otherwise.
set -uo pipefail

# Resolve the repo root rather than hardcoding it: this script is committed and
# will be run from clones, from worktrees, and on CI runners.
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "::error::not inside a git repository" >&2; exit 1; }
cd "$ROOT" || exit 1

# renv's autoloader and a user .Rprofile both mutate the library path, which is
# how a gate can pass locally and fail in CI against a different package set.
export RENV_CONFIG_AUTOLOADER_ENABLED=false R_PROFILE_USER=/dev/null

PASS=0; FAIL=0; declare -a BAD=()
run () {
  local label="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then printf "  PASS  %s\n" "$label"; PASS=$((PASS+1))
  else printf "  FAIL  %s (exit %d)\n" "$label" "$rc"; FAIL=$((FAIL+1)); BAD+=("$label")
       printf '%s\n' "$out" | tail -6 | sed 's/^/          /'
  fi
}

echo "RELEASE AUDIT -- twostep @ $(git rev-parse --short HEAD)"
echo "generated: $(date)"
# A dirty tree means the audit is not describing the SHA it just printed. This
# is a warning rather than a failure because auditing work in progress is a
# legitimate use, but a freeze must never be declared on one.
if [ -n "$(git status --porcelain)" ]; then
  echo "WARNING: working tree is dirty -- this audit does not describe $(git rev-parse --short HEAD) alone"
fi
echo

echo "== scientific invariants =="
run "supply conservation"        Rscript tools/ci/check_supply_conservation.R
run "panel invariants"           Rscript tools/ci/check_panel_invariants.R
run "denominator identity"       Rscript tools/ci/check_denominator_identity.R
run "age-matched SSOT"           Rscript tools/ci/check_agematched_ssot.R
run "scientific invariants"      Rscript tools/ci/check_scientific_invariants.R
echo
echo "== provenance and geography =="
run "artifact provenance"        Rscript tools/ci/check_artifact_provenance.R
run "frozen isochrones"          bash tools/ci/check_frozen_isochrones.sh artifacts/2sfca/frozen_isochrones
run "checksums"                  bash tools/ci/check_checksums.sh
run "lockfile"                   Rscript tools/ci/check_lockfile.R
echo
echo "== manuscript and appendix =="
run "manuscript guards"          Rscript tools/ci/check_manuscript.R
run "appendix literals"          Rscript tools/ci/check_appendix_literals.R
run "documented shortfalls"      Rscript tools/ci/check_documented_shortfalls.R
run "NEWS headings"              Rscript tools/ci/check_news_headings.R
run "version consistency"        Rscript tools/ci/check_version_consistency.R
run "docs fresh"                 Rscript tools/ci/check_docs_fresh.R
run "README agrees"              Rscript tools/ci/check_readme.R
echo
echo "== source hygiene =="
run "parse"                      Rscript tools/ci/check_parse.R
run "hygiene"                    Rscript tools/ci/check_hygiene.R
run "Rd percent escaping"        Rscript tools/ci/check_rd_percent.R
run "workflow syntax"            Rscript tools/ci/check_workflow_syntax.R
run "launcher heredocs"          Rscript tools/ci/check_launcher_heredoc.R
run "preflight"                  Rscript tools/ci/check_preflight.R
echo
echo "=============================================="
if [ $FAIL -eq 0 ]; then
  echo "AUDIT VERDICT: ALL $PASS GATES PASS"
  exit 0
fi
echo "AUDIT VERDICT: $PASS pass, $FAIL FAIL -- ${BAD[*]}"
exit 1
