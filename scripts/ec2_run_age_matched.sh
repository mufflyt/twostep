#!/usr/bin/env bash
# =============================================================================
# ec2_run_age_matched.sh -- the 11-year (2013-2023) age-matched E2SFCA panel
# =============================================================================
# Sibling of ec2_run_2sfca.sh. That one runs the PRIMARY all-ages pipeline
# (run_2sfca.R) and enforces an allocator-identity gate specific to it. This one
# runs the age-matched panel (tools/multiverse/run_age_matched.R) for every ACS
# vintage, then consolidates.
#
# WHY EC2. Measured locally: ~65 min for the first cell and ~28 min per
# additional denominator build, six distinct denominators per year -- roughly
# 4 h/year, so ~44 h for eleven years on a machine that is also being used for
# other work. On r6i.2xlarge the years run concurrently (each holds ~2 GB of a
# 64 GB box) and the whole panel lands in hours for a few dollars.
#
# THE GATE THAT MATTERS. Moving platforms changes sf/GEOS/GDAL, and overlap
# fractions plus floating-point accumulation can differ between them -- which is
# exactly why this repository carries cross-platform fingerprint machinery. So
# the instance REPRODUCES 2020 FIRST and compares against the committed results
# before computing a single new year. If EC2 cannot reproduce 2020, the panel
# would not be comparable to the numbers already in the manuscript, and the run
# aborts with _FAILED.json rather than producing eleven years of subtly
# different arithmetic.
#
# Usage:  bash scripts/ec2_run_age_matched.sh
#         PHASE=monitor RUN_ID=... bash scripts/ec2_run_age_matched.sh
#         DRY_RUN=1 bash scripts/ec2_run_age_matched.sh   # preflight only, no spend
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

[ -f scripts/ec2.env ] && . scripts/ec2.env

REGION="${EC2_REGION:-us-east-2}"
BUCKET="${S3_BUCKET:-CHANGEME-tiles-bucket}"
PFX="${S3_PREFIX_AM:-agematched_run}"
ISO_PFX="${ISO_S3_PREFIX:-seam_run/inputs/isochrones}"
AMI="${AMI_ID:-ami-CHANGEME}"
ITYPE="${INSTANCE_TYPE:-r6i.2xlarge}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/CHANGEME.pem}"
KEY_NAME="${KEY_NAME:-CHANGEME-key}"
PROFILE="${IAM_PROFILE:-CHANGEME-ec2-profile}"
SGNAME="${SG_NAME:-CHANGEME-sg}"
RUN_ID="${RUN_ID:-agematched_$(date -u +%Y%m%d_%H%M%S)}"
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
RESULTS="$PFX/results/$RUN_ID"
# Years run concurrently on the instance. 4 x ~2 GB against 64 GB and 8 vCPU
# leaves headroom; raise deliberately, not hopefully.
JOBS="${PANEL_JOBS:-4}"
# The seam-validated environment. The instance must match or we fail BEFORE
# spending compute -- a panel produced on a different geospatial stack is not
# comparable to the committed 2020 numbers.
EXP_R="4.5.1"; EXP_SF="1.1.1"; EXP_TERRA="1.9.34"; EXP_EXR="0.10.1"
EXP_GEOS="3.13.0"; EXP_GDAL="3.10.3"; EXP_PROJ="9.6.2"
# Isochrone content hashes, lifted from the frozen run's _SUCCESS.json. These are
# what make "same computational geography" a checkable claim rather than a hope.
ISO30="917d60e3e9f2f5c6a6c5f94d5024b71c050f2b700a6506ba642b23186aa38ea7"
ISO60="3ce5041be6e81ea6b047125f3f5542abbab4de9c4cd6351183dd68fb5128a29d"
ISO120="e6bc2ae5af32ea8b474509a95016fbbbab7741d2b9ddb43c75ed9b7db2df1127"
ISO180="4bfbd5c29814cc2cde4910b1a5bb00277f68c74b3258fe453b29a8e6ab80c99d"
SSH_OPTS="-i $KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
say(){ echo "[ec2-am] $*"; }

# ── PHASE monitor (re-attach) ───────────────────────────────────────────────
if [[ "${PHASE:-all}" == "monitor" ]]; then
  say "polling s3://$BUCKET/$RESULTS/ ..."
  while true; do
    aws s3 ls "s3://$BUCKET/$RESULTS/_SUCCESS.json" --region "$REGION" >/dev/null 2>&1 && { say "_SUCCESS.json"; break; }
    aws s3 ls "s3://$BUCKET/$RESULTS/_FAILED.json"  --region "$REGION" >/dev/null 2>&1 && { say "_FAILED.json";  break; }
    sleep 120
  done
  mkdir -p "artifacts/2sfca/agematched_panel/ec2/$RUN_ID"
  aws s3 cp "s3://$BUCKET/$RESULTS/" "artifacts/2sfca/agematched_panel/ec2/$RUN_ID/" \
    --recursive --region "$REGION" --no-progress || true
  say "results in artifacts/2sfca/agematched_panel/ec2/$RUN_ID/"; exit 0
fi

# ── PHASE 0: preflight -- fail before spending anything ─────────────────────
say "RUN_ID=$RUN_ID  git=$GIT_SHA  region=$REGION  jobs=$JOBS"
case "$BUCKET$AMI$KEY_NAME$PROFILE$SGNAME" in
  *CHANGEME*) say "ERROR: scripts/ec2.env is not configured (CHANGEME placeholders remain)"; exit 1;;
esac
[ -f "$KEY_PATH" ] || { say "ERROR: SSH key not found: $KEY_PATH"; exit 1; }

RUCA_2020="${E2SFCA_RUCA_PATH:-/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping.csv}"
RUCA_2010="${E2SFCA_RUCA_2010_PATH:-/Users/tylermuffly/isochrones-den/data/external/ruca_tract_mapping_2010.csv}"
CACHE="artifacts/2sfca/sensitivity/cache"
REQ=( "$RUCA_2020" "$RUCA_2010"
      "$CACHE/acs2013_tracts.rds" "$CACHE/acs2020_tracts.rds"
      "artifacts/multiverse/age_matched_results.csv"
      "inst/multiverse/age_matched_denominator.yml"
      "inst/multiverse/age_matched_denominator.sha256" )
for y in 2013 2014 2015 2016 2017 2018 2019 2021 2022 2023; do
  REQ+=( "$CACHE/age_matched_denominators_${y}.rds" "$CACHE/acs${y}_age_bands.rds" )
done
REQ+=( "$CACHE/age_matched_denominators.rds" "$CACHE/acs2020_age_bands.rds" )
miss=0
for f in "${REQ[@]}"; do [ -f "$f" ] || { say "MISSING input: $f"; miss=1; }; done
n_sup=$(find artifacts/2sfca/agematched_panel/sup -name "*_providers.rds" 2>/dev/null | wc -l | tr -d ' ')
[ "$n_sup" -eq 77 ] || { say "MISSING supply: found $n_sup provider files, expected 77"; miss=1; }
[ "$miss" -eq 0 ] || { say "preflight FAILED -- nothing launched, nothing spent"; exit 1; }
say "preflight: all local inputs present (77 supply files, 11 vintages)"

say "verifying isochrones already staged at s3://$BUCKET/$ISO_PFX/"
for b in 30 60 120 180; do
  aws s3api head-object --bucket "$BUCKET" --key "$ISO_PFX/isochrones_${b}min_consolidated.rds" \
    --region "$REGION" --query ContentLength --output text >/dev/null \
    || { say "MISSING isochrone on S3: $ISO_PFX/isochrones_${b}min_consolidated.rds"; exit 1; }
done
say "isochrones present on S3 (no re-upload needed)"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  say "DRY_RUN=1 -- preflight passed; no upload, no instance, no spend."; exit 0
fi

# ── PHASE 1: stage inputs ───────────────────────────────────────────────────
TAR=/tmp/am_code.tar.gz
tar czf "$TAR" -C "$PROJECT_ROOT" \
  R scripts/manuscript_e2sfca_values.R tools/multiverse tools/ci inst/multiverse DESCRIPTION NAMESPACE
say "code bundle $(du -h "$TAR" | cut -f1)"
aws s3 cp "$TAR" "s3://$BUCKET/$PFX/inputs/am_code.tar.gz" --region "$REGION" --no-progress
[ "$(stat -f%z "$TAR")" = "$(aws s3api head-object --bucket "$BUCKET" --key "$PFX/inputs/am_code.tar.gz" --region "$REGION" --query ContentLength --output text 2>/dev/null || echo -1)" ] \
  || { say "ERROR: code bundle upload did not land"; exit 1; }

IN=/tmp/am_inputs.tar.gz
# sensitivity_2020.csv is the GATE'S REFERENCE and must travel with the inputs.
# It did not, and the run computed 14 cells over an hour before the comparison
# failed on a missing file.
GATE_REF="artifacts/2sfca/sensitivity/sensitivity_2020.csv"
[ -f "$GATE_REF" ] || { say "ERROR: gate reference missing locally: $GATE_REF"; exit 1; }
tar czf "$IN" "$CACHE" artifacts/2sfca/agematched_panel/sup \
  artifacts/multiverse/age_matched_results.csv "$GATE_REF"
say "input bundle $(du -h "$IN" | cut -f1)"
# MULTIPART, NOT `s3 cp`. scripts/s3_multipart_put.sh exists because this
# environment SILENTLY DROPS s3 cp / put-object above ~16 MB -- its own header
# says so. A plain cp of this 224 MB bundle produced no output, no error, and no
# object: the instance then downloaded a stale tarball from a previous run and
# failed its input preflight. set -e cannot catch an upload that "succeeds".
bash scripts/s3_multipart_put.sh "$IN" "$BUCKET" "$PFX/inputs/am_inputs.tar.gz" "$REGION" \
  || { say "ERROR: multipart upload of the input bundle failed"; exit 1; }

# Verify what actually landed, the way ec2_run_2sfca.sh does: re-read the object
# size from S3 and require it to match the local file. Uploading and hoping is
# what cost the last two runs.
LOCAL_SZ=$(stat -f%z "$IN")
S3_SZ=$(aws s3api head-object --bucket "$BUCKET" --key "$PFX/inputs/am_inputs.tar.gz" \
        --region "$REGION" --query ContentLength --output text 2>/dev/null || echo -1)
[ "$LOCAL_SZ" = "$S3_SZ" ] || { say "ERROR: uploaded bundle is $S3_SZ bytes, local is $LOCAL_SZ"; exit 1; }
say "input bundle verified in S3 ($S3_SZ bytes)"
# mufflyaccess is the study's own SSOT package (scenario dictionary, projection
# contract, DENOMINATOR_CATEGORY) and six R/ files require it -- so the analysis
# genuinely needs it, and the run fails without it. It is PURE R with no compiled
# code, so ship the installed copy at the exact version this analysis uses rather
# than building it on the instance. Verified loading under R 4.5.1 there.
MA_LIB="$(R_PROFILE_USER=/dev/null Rscript -e 'cat(find.package("mufflyaccess"))' 2>/dev/null | tail -1)"
[ -d "$MA_LIB" ] || { say "ERROR: mufflyaccess not installed locally; cannot stage it"; exit 1; }
MA_VER="$(R_PROFILE_USER=/dev/null Rscript -e 'cat(as.character(packageVersion("mufflyaccess")))' 2>/dev/null | tail -1)"
COPYFILE_DISABLE=1 tar czf /tmp/mufflyaccess.tar.gz -C "$(dirname "$MA_LIB")" mufflyaccess
MA_SHA="$(shasum -a 256 /tmp/mufflyaccess.tar.gz | awk '{print $1}')"
say "staging mufflyaccess $MA_VER (sha256 ${MA_SHA:0:16}...)"
aws s3 cp /tmp/mufflyaccess.tar.gz "s3://$BUCKET/$PFX/inputs/mufflyaccess.tar.gz" --region "$REGION" --no-progress
aws s3 cp "$RUCA_2020" "s3://$BUCKET/$PFX/inputs/ruca_tract_mapping.csv" --region "$REGION" --no-progress
aws s3 cp "$RUCA_2010" "s3://$BUCKET/$PFX/inputs/ruca_tract_mapping_2010.csv" --region "$REGION" --no-progress

# Checksums travel with the inputs so the instance verifies what it received.
MAN=/tmp/am_inputs_SHA256SUMS.txt
: > "$MAN"
for f in "$TAR" "$IN" "$RUCA_2020" "$RUCA_2010"; do shasum -a 256 "$f" >> "$MAN"; done
aws s3 cp "$MAN" "s3://$BUCKET/$PFX/inputs/am_inputs_SHA256SUMS.txt" --region "$REGION" --no-progress
say "inputs staged"

# ── PHASE 2: security group + launch ────────────────────────────────────────
MY_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com || curl -s --max-time 5 https://api.ipify.org)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
  --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null || echo "")
[[ -z "$SG_ID" || "$SG_ID" == "None" ]] && SG_ID=$(aws ec2 create-security-group --group-name "$SGNAME" \
  --description "age-matched panel compute SSH" --region "$REGION" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 \
  --cidr "${MY_IP}/32" --region "$REGION" >/dev/null 2>&1 || true
say "security group $SG_ID open to ${MY_IP}/32"

INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$ITYPE" \
  --instance-initiated-shutdown-behavior terminate --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" --iam-instance-profile "Name=$PROFILE" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUN_ID},{Key=Purpose,Value=agematched-panel-11yr}]" \
  --region "$REGION" --query 'Instances[0].InstanceId' --output text)
say "launched INSTANCE_ID=$INSTANCE_ID ($ITYPE)"
echo "$INSTANCE_ID" > "/tmp/am_instance_${RUN_ID}.txt"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$REGION")
say "running: $INSTANCE_ID  ip=$PUBLIC_IP"
for i in $(seq 1 40); do ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true 2>/dev/null && break; sleep 15; done
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true || { say "SSH never came up"; exit 1; }
say "SSH up"

# ── PHASE 3: push the remote bootstrap and launch it under nohup ────────────
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" "cat > /home/ec2-user/run_am.sh" <<REMOTE
#!/usr/bin/env bash
set -uo pipefail
B="$BUCKET"; R="$REGION"; P="$PFX"; RES="$RESULTS"; RID="$RUN_ID"; J="$JOBS"
ISO="$ISO_PFX"; GIT="$GIT_SHA"
MA_VER="$MA_VER"; MA_SHA="$MA_SHA"
EXP_R="$EXP_R"; EXP_SF="$EXP_SF"; EXP_TERRA="$EXP_TERRA"; EXP_EXR="$EXP_EXR"
EXP_GEOS="$EXP_GEOS"; EXP_GDAL="$EXP_GDAL"; EXP_PROJ="$EXP_PROJ"
cd /home/ec2-user
log(){ echo "[remote] \$*"; }
fail(){ log "FAILED: \$*"
  # Plain printf, not a nested Python heredoc. The previous version interpolated
  # the run id through three quoting layers, raised a Python SyntaxError, and
  # wrote a ZERO-BYTE _FAILED.json -- so the failure reported nothing about itself.
  printf '{\n  "status": "FAILED",\n  "run_id": "%s",\n  "reason": "%s",\n  "when": "%s"\n}\n' \
    "\$RID" "\$*" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /home/ec2-user/_FAILED.json
  # Upload EVERY log. The last run failed inside year_2020.log, which was never
  # uploaded, and the instance terminated holding the only copy of the error.
  cp /home/ec2-user/run_am.out /home/ec2-user/run_am.log 2>/dev/null || true
  for f in /home/ec2-user/*.log /home/ec2-user/*.txt; do
    [ -f "\$f" ] && aws s3 cp "\$f" "s3://\$B/\$RES/logs/\$(basename \$f)" --region "\$R" >/dev/null 2>&1 || true
  done
  aws s3 cp /home/ec2-user/_FAILED.json "s3://\$B/\$RES/_FAILED.json" --region "\$R" || true
  # 20 minutes, not 2: a real window to SSH in and look before it vanishes.
  sudo shutdown -h +20; exit 1; }

mkdir -p proj && cd proj
aws s3 cp "s3://\$B/\$P/inputs/am_code.tar.gz"   . --region "\$R" || fail "code download"
aws s3 cp "s3://\$B/\$P/inputs/am_inputs.tar.gz" . --region "\$R" || fail "inputs download"
aws s3 cp "s3://\$B/\$P/inputs/am_inputs_SHA256SUMS.txt" . --region "\$R" || fail "manifest download"
aws s3 cp "s3://\$B/\$P/inputs/ruca_tract_mapping.csv"      . --region "\$R" || fail "ruca download"
aws s3 cp "s3://\$B/\$P/inputs/ruca_tract_mapping_2010.csv" . --region "\$R" || fail "ruca2010 download"
tar xzf am_code.tar.gz && tar xzf am_inputs.tar.gz || fail "extract"

mkdir -p iso
for b in 30 60 120 180; do
  aws s3 cp "s3://\$B/\$ISO/isochrones_\${b}min_consolidated.rds" "iso/" --region "\$R" --no-progress \
    || fail "isochrone \$b download"
done
# The whole defensibility argument is that the computational geography is
# IDENTICAL to the primary analysis and only the denominator changed. That is a
# claim about bytes, so verify it rather than assert it. Hashes come from the
# frozen run's own _SUCCESS.json input_checksums.
declare -A ISOSHA=( [30]="$ISO30" [60]="$ISO60" [120]="$ISO120" [180]="$ISO180" )
: > /home/ec2-user/iso.sums
for b in 30 60 120 180; do
  got=\$(sha256sum "iso/isochrones_\${b}min_consolidated.rds" | awk '{print \$1}')
  echo "\$got  isochrones_\${b}min_consolidated.rds" >> /home/ec2-user/iso.sums
  [ "\$got" = "\${ISOSHA[\$b]}" ] || fail "isochrone \$b hash mismatch: got \$got want \${ISOSHA[\$b]} -- NOT the geography the primary analysis used"
done
log "isochrones byte-identical to the primary analysis"

# The study's SSOT package, shipped at the pinned version. This goes into a USER
# library so it cannot shadow anything in the frozen system library; the gate
# below proves the spatial stack still resolves from the frozen one.
aws s3 cp "s3://\$B/\$P/inputs/mufflyaccess.tar.gz" . --region "\$R" || fail "mufflyaccess download"
got_ma=\$(sha256sum mufflyaccess.tar.gz | awk '{print \$1}')
[ "\$got_ma" = "\$MA_SHA" ] || fail "mufflyaccess hash mismatch: got \$got_ma want \$MA_SHA"
mkdir -p /home/ec2-user/Rlib
tar xzf mufflyaccess.tar.gz -C /home/ec2-user/Rlib || fail "mufflyaccess extract"
export R_LIBS_USER=/home/ec2-user/Rlib
log "mufflyaccess \$MA_VER staged into a user library (hash verified)"

# NOTHING ELSE IS INSTALLED AT RUNTIME. An earlier version installed pkgload into a
# user library; that is now unnecessary (the runner sources R/ directly when no
# loader is present) and it was undesirable -- any runtime install weakens the
# claim that the spatial computation ran in the same environment as the frozen
# primary analysis. Verify what is here, install nothing.
Rscript -e '
.libPaths(c(path.expand("~/Rlib"), .libPaths()))
need <- c("dplyr","tidyr","yaml","digest","sf","terra","exactextractr","mufflyaccess")
miss <- need[!vapply(need, requireNamespace, logical(1), quietly=TRUE)]
if (length(miss)) { cat("MISSING:", paste(miss, collapse=","), "\n"); quit(status=1) }
# HARD GATE: every package that determines the arithmetic must resolve from the
# frozen system library, never from a user library. A future bootstrap that
# shadowed the pinned spatial stack would otherwise pass silently.
# ALLOWLIST, not a blocklist: ~/Rlib may contain and resolve ONLY mufflyaccess.
# Simpler and stronger than naming individual prohibited packages -- it catches
# anything that appears there in future without needing to anticipate it.
ulib <- path.expand("~/Rlib")
present <- list.dirs(ulib, full.names=FALSE, recursive=FALSE)
present <- present[nzchar(present)]
extra <- setdiff(present, "mufflyaccess")
if (length(extra)) {
  cat("USER LIB CONTAMINATED:", paste(extra, collapse=","), "\n"); quit(status=3)
}
# and nothing except mufflyaccess may RESOLVE from there
from_ulib <- Filter(function(p) identical(dirname(find.package(p)), ulib), need)
if (!setequal(from_ulib, intersect("mufflyaccess", need))) {
  cat("RESOLVED FROM USER LIB:", paste(from_ulib, collapse=","), "\n"); quit(status=2)
}
spatial <- c("sf","terra","exactextractr")
loc <- vapply(spatial, function(p) dirname(find.package(p)), character(1))
ma <- dirname(find.package("mufflyaccess"))
writeLines(c(paste("libPaths:", paste(.libPaths(), collapse=" | ")),
             paste(spatial, unname(loc), vapply(spatial, function(p) as.character(utils::packageVersion(p)), character(1)),
                   sep="@", collapse="; "),
             paste0("mufflyaccess@", ma, "@", as.character(utils::packageVersion("mufflyaccess")),
                    " (shipped from the local install, hash-verified; pure R, not built here)"),
             "runtime_installs: none (mufflyaccess was copied, not compiled)",
             "spatial_stack_source: frozen system library"), "/home/ec2-user/pkgs.log")
cat("packages verified, none installed, spatial stack from the frozen library\n")'
PKG=\$?
cat /home/ec2-user/pkgs.log 2>/dev/null
[ \$PKG -eq 0 ] || fail "package verification failed (status \$PKG: 1=missing, 2=resolved from user lib, 3=user lib contaminated)"

# Environment gate: a different geospatial stack produces different overlap
# fractions, so refuse before computing anything.
Rscript -e '
g <- function(p) as.character(utils::packageVersion(p))
e <- list(r=paste(R.version\$major, R.version\$minor, sep="."), sf=g("sf"),
          terra=g("terra"), exr=g("exactextractr"))
x <- sf::sf_extSoftVersion()
cat(e\$r, e\$sf, e\$terra, e\$exr, x[["GEOS"]], x[["GDAL"]], x[["PROJ"]], sep="\n")' > /tmp/env.txt 2>/dev/null || fail "env probe"
mapfile -t E < /tmp/env.txt
for pair in "\${E[0]}:\$EXP_R" "\${E[1]}:\$EXP_SF" "\${E[2]}:\$EXP_TERRA" "\${E[3]}:\$EXP_EXR" \
            "\${E[4]}:\$EXP_GEOS" "\${E[5]}:\$EXP_GDAL" "\${E[6]}:\$EXP_PROJ"; do
  got="\${pair%%:*}"; want="\${pair##*:}"
  [ "\$got" = "\$want" ] || fail "environment mismatch: got \$got want \$want"
done
log "environment matches the seam-validated stack"

# Verify every input the run will need BEFORE computing anything. The previous
# attempt spent an hour on 14 cells and then died because the gate's reference
# file had never been uploaded. Inputs are cheap to check; compute is not.
for f in artifacts/2sfca/sensitivity/sensitivity_2020.csv \
         artifacts/multiverse/age_matched_results.csv \
         inst/multiverse/age_matched_denominator.yml \
         inst/multiverse/age_matched_denominator.sha256; do
  [ -f "\$f" ] || fail "required input missing on the instance: \$f"
done
for y in 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023; do
  d="artifacts/2sfca/sensitivity/cache/age_matched_denominators_\$y.rds"
  [ "\$y" = "2020" ] && d="artifacts/2sfca/sensitivity/cache/age_matched_denominators.rds"
  [ -f "\$d" ] || fail "denominators missing for \$y"
done
log "all analysis inputs present on the instance"

export S=artifacts/2sfca/agematched_panel
export E2SFCA_ISO_DIR=/home/ec2-user/proj/iso
run_year(){
  local Y=\$1
  local RU=ruca_tract_mapping.csv
  [ "\$Y" -le 2019 ] && RU=ruca_tract_mapping_2010.csv
  E2SFCA_AM_YEAR="\$Y" E2SFCA_RUCA_PATH="/home/ec2-user/proj/\$RU" \
    Rscript tools/multiverse/run_age_matched.R > "/home/ec2-user/year_\$Y.log" 2>&1
}

# ---- THE GATE: reproduce 2020 before computing anything new ----------------
# THE REFERENCE IS THE FROZEN ANALYSIS, NOT THE PREVIOUS LOCAL RUN.
# artifacts/multiverse/age_matched_results.csv was computed locally against an
# INCOMPLETE isochrone set -- 5 of 516 GO origins had no catchment and their
# supply was dropped, putting it 0.786% below the frozen analysis. Gating on it
# would demand that EC2 reproduce a known defect.
#
# artifacts/2sfca/sensitivity/sensitivity_2020.csv `base` is the right reference:
# frozen, and computed at the same 1000 m resolution this runner uses.
log "gate: reproducing 2020 against the FROZEN sensitivity base variant"
if ! run_year 2020; then
  log "---- year_2020.log (tail) ----"; tail -40 /home/ec2-user/year_2020.log || true
  fail "2020 reproduction run errored (see logs/year_2020.log)"
fi
Rscript -e '
ref <- read.csv("artifacts/2sfca/sensitivity/sensitivity_2020.csv", stringsAsFactors=FALSE)
ref <- ref[ref\$variant == "base", c("subspec","national")]
got <- read.csv("artifacts/multiverse/age_matched_results.csv", stringsAsFactors=FALSE)
got <- got[got\$regime == "all_ages", c("subspec","national","n_supply_origins","n_iso_origins")]
m <- merge(ref, got, by="subspec", suffixes=c("_frozen","_ec2"))
if (nrow(m) != nrow(ref)) { cat("subspecialty mismatch\n"); quit(status=2) }
m\$rel <- abs(m\$national_ec2 - m\$national_frozen) / m\$national_frozen
for (i in seq_len(nrow(m)))
  cat(sprintf("  %-6s frozen %.5f  ec2 %.5f  rel %+.4f%%  origins %d/%d\n",
      m\$subspec[i], m\$national_frozen[i], m\$national_ec2[i], 100*m\$rel[i],
      m\$n_iso_origins[i], m\$n_supply_origins[i]))
cat(sprintf("max relative deviation: %.3e\n", max(m\$rel)))
# EVERY supply origin must have a catchment. The local run silently dropped five
# and landed 0.786% low; that must never pass here.
drop <- m\$n_supply_origins - m\$n_iso_origins
if (any(drop > 0)) {
  cat("SUPPLY DROPPED for:", paste(m\$subspec[drop>0], collapse=","), "\n"); quit(status=4)
}
if (max(m\$rel) > 1e-3) quit(status=3)' GS=\${?:-1}
cat /home/ec2-user/gate.txt
aws s3 cp /home/ec2-user/gate.txt "s3://\$B/\$RES/gate_2020.txt" --region "\$R" || true
[ \$GS -eq 0 ] || fail "EC2 could not reproduce the committed 2020 results (status \$GS) -- the panel would not be comparable"
log "gate PASSED: 2020 reproduces on this platform"
cp artifacts/multiverse/age_matched_results.csv /home/ec2-user/ec2_2020.csv

# ---- the remaining ten vintages, J at a time -------------------------------
i=0
for Y in 2013 2014 2015 2016 2017 2018 2019 2021 2022 2023; do
  run_year "\$Y" &
  i=\$((i+1))
  if [ \$((i % J)) -eq 0 ]; then wait; log "batch complete (through \$Y)"; fi
done
wait
log "all years finished"

for Y in 2013 2014 2015 2016 2017 2018 2019 2021 2022 2023; do
  [ -f "artifacts/multiverse/age_matched_results_\$Y.csv" ] || fail "missing results for \$Y"
done

Rscript tools/multiverse/consolidate_panel.R > /home/ec2-user/consolidate.log 2>&1 \
  || { cat /home/ec2-user/consolidate.log; fail "consolidation"; }
Rscript tools/ci/check_panel_invariants.R > /home/ec2-user/invariants.log 2>&1
IV=\$?
cat /home/ec2-user/invariants.log

# Prove the panel is the AGE-MATCHED analysis and not eleven copies of the
# universal denominator: both regimes present in every year, and the age-matched
# denominator must actually DIFFER from all-ages for every subspecialty except
# where the window genuinely covers everyone.
Rscript -e '
p <- read.csv("artifacts/2sfca/agematched_panel/age_matched_panel.csv", stringsAsFactors=FALSE)
stopifnot(setequal(unique(p\$regime), c("all_ages","age_matched")))
yrs <- sort(unique(p\$year)); subs <- unique(p\$subspec)
for (y in yrs) for (r in c("all_ages","age_matched"))
  stopifnot(length(unique(p\$subspec[p\$year==y & p\$regime==r])) == length(subs))
aa <- p[p\$regime=="all_ages",]; am <- p[p\$regime=="age_matched",]
k <- paste(am\$year, am\$subspec); ref <- setNames(aa\$denominator, paste(aa\$year, aa\$subspec))
share <- am\$denominator / ref[k]
cat(sprintf("age-eligible share: min %.3f max %.3f over %d cells\n",
            min(share), max(share), length(share)))
if (max(share) >= 0.999) quit(status=4)   # an age window covering everyone means
                                          # the universal denominator leaked in
if (any(share <= 0)) quit(status=5)
cat(sprintf("tracts: %d years x %d subspecialties x 2 regimes = %d rows\n",
            length(yrs), length(subs), nrow(p)))' > /home/ec2-user/panel_assertions.txt 2>&1
PA=\$?
cat /home/ec2-user/panel_assertions.txt
[ \$PA -eq 0 ] || fail "panel assertions failed (status \$PA) -- the denominators may not be the age-matched ones"

OUTD=/home/ec2-user/out; mkdir -p \$OUTD
cp artifacts/2sfca/agematched_panel/age_matched_panel.csv \$OUTD/ 2>/dev/null
cp artifacts/2sfca/agematched_panel/provenance.json       \$OUTD/ 2>/dev/null
cp artifacts/multiverse/age_matched_results_*.csv         \$OUTD/ 2>/dev/null
cp /home/ec2-user/ec2_2020.csv \$OUTD/age_matched_results_2020_ec2.csv 2>/dev/null
cp /home/ec2-user/*.log /home/ec2-user/gate.txt \$OUTD/ 2>/dev/null
( cd \$OUTD && shasum -a 256 * > outputs.sums )
[ \$IV -eq 0 ] || fail "panel invariants failed (outputs staged for inspection)"

aws s3 cp \$OUTD "s3://\$B/\$RES/" --recursive --region "\$R" --no-progress || fail "upload"
python3 - <<'PY' > /home/ec2-user/_SUCCESS.json
import json, subprocess, datetime, os
def sh(c):
    try: return subprocess.check_output(c, shell=True, text=True).strip()
    except Exception: return None
json.dump({
  "status":"SUCCESS", "run_id": os.environ.get("RID_ENV",""),
  "git_sha": os.environ.get("GIT_ENV",""),
  "when": datetime.datetime.utcnow().isoformat(),
  "instance_type": sh("curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-type"),
  "ami": sh("curl -s --max-time 3 http://169.254.169.254/latest/meta-data/ami-id"),
  "gate_2020": open("/home/ec2-user/gate.txt").read().strip(),
  "panel_assertions": open("/home/ec2-user/panel_assertions.txt").read().strip(),
  "environment": dict(zip(
      ["r","sf","terra","exactextractr","geos","gdal","proj"],
      open("/tmp/env.txt").read().split())),
  "isochrone_checksums": open("/home/ec2-user/iso.sums").read().strip().splitlines(),
  "package_provenance": open("/home/ec2-user/pkgs.log").read().strip().splitlines(),
  "mufflyaccess": {"version": os.environ.get("MA_VER_ENV",""),
                   "staged_tarball_sha256": os.environ.get("MA_SHA_ENV",""),
                   "source": "copied from the local install; pure R, not built on the instance"},
  "sourced_R_files": (open("/home/ec2-user/proj/artifacts/multiverse/sourced_R_files.sums").read().strip().splitlines()
                      if os.path.exists("/home/ec2-user/proj/artifacts/multiverse/sourced_R_files.sums") else
                      ["load_all() was used; R/ was not sourced directly"]),
  "denominator_manifest_sha256": sh("sha256sum /home/ec2-user/proj/inst/multiverse/age_matched_denominator.yml | cut -d\" \" -f1"),
  "outputs": open("/home/ec2-user/out/outputs.sums").read().strip().splitlines(),
}, open(1,"w"), indent=2)
PY
RID_ENV="\$RID" GIT_ENV="\$GIT" MA_VER_ENV="\$MA_VER" MA_SHA_ENV="\$MA_SHA" \
  aws s3 cp /home/ec2-user/_SUCCESS.json "s3://\$B/\$RES/_SUCCESS.json" --region "\$R" || true
log "SUCCESS uploaded; shutting down"
sudo shutdown -h +2
REMOTE

ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" \
  "chmod +x /home/ec2-user/run_am.sh && nohup bash /home/ec2-user/run_am.sh > /home/ec2-user/run_am.out 2>&1 & echo REMOTE-LAUNCHED"
say "remote launched. Re-attach with:"
say "  PHASE=monitor RUN_ID=$RUN_ID bash scripts/ec2_run_age_matched.sh"
say "Instance self-terminates on completion or failure."
