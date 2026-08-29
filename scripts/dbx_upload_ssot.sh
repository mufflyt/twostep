#!/usr/bin/env bash
# =============================================================================
# Mirror the SSOT payloads to Dropbox, and actually verify they arrived
# =============================================================================
# The frozen isochrone set and the ABOG refresh registry are served by
# mufflyaccess as single sources of truth. The bytes live in two canonical
# places, S3 and Dropbox, recorded in mufflyaccess's ssot_sources.json. This
# script maintains the Dropbox side.
#
# WHY THIS SCRIPT IS IN THE REPOSITORY, AND WHY IT DIFFERS FROM WHAT RAN:
# the version that performed the original upload lived only in /tmp and verified
# with `rclone hashsum sha256 dropbox:...`. Dropbox does not expose SHA-256 --
# `rclone backend features dropbox:` reports exactly one algorithm, "dropbox",
# its own content hash. So every hashsum came back EMPTY, every comparison
# against a real local SHA-256 failed, and the run printed:
#
#     [dbx] MISMATCH 30min local=917d60e3... dropbox=
#     ... and four more
#
# The upload had in fact succeeded. The verification was structurally incapable
# of passing, and its five failures were read as noise rather than investigated.
# A check that cannot pass is worse than no check: it trains you to ignore it.
#
# `rclone check` negotiates a hash both sides support, so it compares content
# rather than nothing. Re-verified 2026-08-29: 4 matching files, 0 differences.
#
# Usage: bash scripts/dbx_upload_ssot.sh [--verify-only]
set -uo pipefail

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

DEST="dropbox:MufflyAccess_SSOT"
RUN_ID="e2sfca_20260712_190734"
ISO_LOCAL="artifacts/2sfca/frozen_isochrones"
ISO_REMOTE="$DEST/frozen_isochrones/$RUN_ID"
REFRESH_LOCAL_DIR="${ABOG_REFRESH_DIR:-$HOME/Downloads}"
REFRESH_REMOTE="$DEST/abog_refresh_2026"
VERIFY_ONLY=0
[ "${1:-}" = "--verify-only" ] && VERIFY_ONLY=1

command -v rclone >/dev/null || { echo "::error::rclone not installed" >&2; exit 1; }

# macOS TCC can deny reads of ~/Downloads even when the file stats fine, so test
# an actual read rather than -f/-r.
refresh_readable () { head -c 1 "$REFRESH_LOCAL_DIR/refresh_merged.csv" >/dev/null 2>&1; }

# Upload only what this machine can prove is the frozen set. Mirroring an
# unverified local directory would propagate the wrong isochrones to the place
# everyone else fetches from, which is strictly worse than not mirroring.
if [ $VERIFY_ONLY -eq 0 ]; then
  echo "[dbx] verifying the local set before mirroring it"
  bash tools/ci/check_frozen_isochrones.sh "$ISO_LOCAL" || {
    echo "::error::refusing to mirror: $ISO_LOCAL is not the frozen set" >&2; exit 1; }

  echo "[dbx] === frozen isochrones ($RUN_ID) ==="
  rclone mkdir "$ISO_REMOTE" 2>/dev/null
  rclone copy "$ISO_LOCAL" "$ISO_REMOTE" --progress --transfers 2 || exit 1
  rclone copy inst/multiverse/frozen_isochrones.sha256 "$ISO_REMOTE/" || exit 1

  if refresh_readable; then
    echo "[dbx] === abog refresh registry ==="
    rclone mkdir "$REFRESH_REMOTE" 2>/dev/null
    rclone copy "$REFRESH_LOCAL_DIR" "$REFRESH_REMOTE" --include 'refresh_merged.csv' || exit 1
  else
    echo "[dbx] refresh_merged.csv unreadable at $REFRESH_LOCAL_DIR -- skipped (set ABOG_REFRESH_DIR)"
  fi
fi

# --- verification -------------------------------------------------------------
# rclone check picks a hash both ends support and compares CONTENT. Do not
# substitute `rclone hashsum sha256` here; see the header.
rc=0
echo "[dbx] === verify: frozen isochrones ==="
rclone check "$ISO_LOCAL" "$ISO_REMOTE" --exclude 'frozen_isochrones.sha256' || rc=1

if refresh_readable; then
  echo "[dbx] === verify: abog refresh registry ==="
  rclone check "$REFRESH_LOCAL_DIR" "$REFRESH_REMOTE" --include 'refresh_merged.csv' || rc=1
else
  # NOT a mirror failure. Saying so would repeat this script's own cautionary
  # tale: a check reporting a cause it did not establish.
  echo "[dbx] refresh_merged.csv is not readable from here -- registry NOT verified."
  echo "[dbx]   This is a local access problem, not evidence about the mirror."
  echo "[dbx]   The S3 copy verifies against its recorded sha256 independently."
fi

if [ $rc -ne 0 ]; then
  echo "::error::Dropbox mirror does not match local. Do not record it as canonical." >&2
  exit 1
fi
echo "[dbx] mirror verified by content hash"
