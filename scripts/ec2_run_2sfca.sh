#!/usr/bin/env bash
# =============================================================================
# ec2_run_2sfca.sh — run the 11-year (2013-2023) national E2SFCA production
# series on EC2 (r6i.2xlarge/64GB) under the VALIDATED mass-conserving
# area-overlap allocator. S3-transport-only. HARDENED, preflight-gated:
#   * every input verified by SHA-256 (content, not ETag) before R starts;
#   * shipped code verified by SHA-256 against a code manifest;
#   * exact R/sf/terra/exactextractr/GDAL/GEOS/PROJ ENFORCED (env lock ASSERT) —
#     fail before compute on any drift from the seam-validated environment;
#   * 59-test allocator conservation suite run under R 4.5.1 — fail if any fail;
#   * ALLOCATOR IDENTITY: run_2sfca.R stops unless module sha == seam-validated
#     hash and dispatch resolves to area (mass-conserving), before any compute;
#   * per-year national population conservation asserted inside the runner;
#   * full input+config inventory printed to the permanent log before R;
#   * distinct terminal sentinels: _SUCCESS.json (only after every output+log+
#     checksum is uploaded AND re-verified in S3) vs _FAILED.json (+ full log).
#     No shell trap can create the success sentinel.
# Grid/resolution/CRS match the seam gate exactly: 500 m, EPSG:5070.
# Usage:  bash scripts/ec2_run_2sfca.sh
#         PHASE=monitor RUN_ID=... bash scripts/ec2_run_2sfca.sh   # re-attach poll
# =============================================================================
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$PROJECT_ROOT"

# Private infrastructure identifiers (bucket / AMI / SSH key / IAM / security
# group) are NOT committed. Copy scripts/ec2.env.example to scripts/ec2.env and
# fill in your values (or export the same vars in your shell). The CHANGEME-*
# defaults below are non-functional placeholders so a public clone leaks nothing.
[ -f scripts/ec2.env ] && . scripts/ec2.env

REGION="${EC2_REGION:-us-east-2}"
BUCKET="${S3_BUCKET:-CHANGEME-tiles-bucket}"
PFX="${S3_PREFIX:-e2sfca_run}"
ISO_PFX="${ISO_S3_PREFIX:-seam_run/inputs/isochrones}"   # reuse verified isochrones
AMI="${AMI_ID:-ami-CHANGEME}"
ITYPE="${INSTANCE_TYPE:-r6i.2xlarge}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/CHANGEME.pem}"
KEY_NAME="${KEY_NAME:-CHANGEME-key}"
PROFILE="${IAM_PROFILE:-CHANGEME-ec2-profile}"
SGNAME="${SG_NAME:-CHANGEME-sg}"
SRCRUN="${SRCRUN:-20260702_120134_90bf52ef}"          # ycm/cohort source artifacts dir
RUN_ID="${RUN_ID:-e2sfca_$(date -u +%Y%m%d_%H%M%S)}"  # immutable per launch
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
ALLOC_SHA="${E2SFCA_SEAM_ALLOCATOR_SHA256:-2b78718bf65c2ecb7a1c99fb027d4aa52aeabc345faf6ec71291197e3fe25c43}"
RESULTS="$PFX/results/$RUN_ID"
RESOLUTION="${RESOLUTION:-500}"
YEARS="${YEARS:-2013:2023}"
# seam-validated environment (must match on EC2 or we fail before compute)
EXP_R="4.5.1"; EXP_SF="1.1.1"; EXP_TERRA="1.9.34"; EXP_EXR="0.10.1"
EXP_GEOS="3.13.0"; EXP_GDAL="3.10.3"; EXP_PROJ="9.6.2"
# isochrone content SHAs (from seam _SUCCESS.json input_checksums)
ISO30="917d60e3e9f2f5c6a6c5f94d5024b71c050f2b700a6506ba642b23186aa38ea7"
ISO60="3ce5041be6e81ea6b047125f3f5542abbab4de9c4cd6351183dd68fb5128a29d"
ISO120="e6bc2ae5af32ea8b474509a95016fbbbab7741d2b9ddb43c75ed9b7db2df1127"
ISO180="4bfbd5c29814cc2cde4910b1a5bb00277f68c74b3258fe453b29a8e6ab80c99d"
SSH_OPTS="-i $KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
say(){ echo "[ec2-2sfca] $*"; }

# ── PHASE monitor (re-attach) ───────────────────────────────────────────────
if [[ "${PHASE:-all}" == "monitor" ]]; then
  say "polling s3://$BUCKET/$RESULTS/ for _SUCCESS.json / _FAILED.json ..."
  while true; do
    aws s3 ls "s3://$BUCKET/$RESULTS/_SUCCESS.json" --region "$REGION" >/dev/null 2>&1 && { say "_SUCCESS.json"; break; }
    aws s3 ls "s3://$BUCKET/$RESULTS/_FAILED.json"  --region "$REGION" >/dev/null 2>&1 && { say "_FAILED.json";  break; }
    sleep 120
  done
  mkdir -p "artifacts/2sfca/ec2/$RUN_ID"
  aws s3 cp "s3://$BUCKET/$RESULTS/" "artifacts/2sfca/ec2/$RUN_ID/" --recursive --region "$REGION" --no-progress || true
  say "results in artifacts/2sfca/ec2/$RUN_ID/"; exit 0
fi

# ── PHASE 1: stage code + code manifest + ycm/cohort + acs bundle + seam gate ─
say "RUN_ID=$RUN_ID  git=$GIT_SHA  region=$REGION  resolution=${RESOLUTION}m  years=$YEARS"
TAR=/tmp/e2sfca_code.tar.gz
tar czf "$TAR" -C "$PROJECT_ROOT" \
  R/two_step_floating_catchment.R scripts/run_2sfca.R \
  R/utils/write_rds_atomic.R R/utils/safe_save.R \
  scripts/ec2_install_pkgs.R \
  tests/testthat/test-two-step-floating-catchment.R DESCRIPTION .here
CODEMAN=/tmp/e2sfca_code_SHA256SUMS.txt; : > "$CODEMAN"
for f in R/two_step_floating_catchment.R scripts/run_2sfca.R R/utils/write_rds_atomic.R tests/testthat/test-two-step-floating-catchment.R; do
  shasum -a 256 "$f" | awk -v n="$(basename "$f")" '{print $1"  "n}' >> "$CODEMAN"; done
echo "git_sha $GIT_SHA" >> "$CODEMAN"
echo "allocator_sha $ALLOC_SHA" >> "$CODEMAN"

ACSB="artifacts/2sfca_seam/acs_bundle_2013_2022.rds"
SEAMGATE="artifacts/2sfca_seam/ec2/seam_20260712_141012/seam_report_all_2020.rds"
[[ -f "$ACSB" ]] || { say "MISSING $ACSB — run scripts/prefetch_2sfca_acs.R"; exit 1; }
[[ -f "$SEAMGATE" ]] || { say "MISSING seam gate $SEAMGATE"; exit 1; }

# fresh inputs manifest (content SHAs of the NEW inputs we stage)
INMAN=/tmp/e2sfca_inputs_SHA256SUMS.txt; : > "$INMAN"
for pair in "acs_bundle_2013_2022.rds|$ACSB" \
            "step_3_year_coord_map.rds|artifacts/$SRCRUN/step_3_year_coord_map.rds" \
            "step_2.5_final_cohort.rds|artifacts/$SRCRUN/step_2.5_final_cohort.rds" \
            "seam_report_all_2020.rds|$SEAMGATE"; do
  nm=${pair%%|*}; pth=${pair##*|}
  [[ -f "$pth" ]] || { say "MISSING input $pth"; exit 1; }
  shasum -a 256 "$pth" | awk -v n="$nm" '{print $1"  "n"  "}' >> "$INMAN"
done
# append the (already-verified) isochrone SHAs so the bootstrap can check them
echo "$ISO30  isochrones_30min_consolidated.rds  " >> "$INMAN"
echo "$ISO60  isochrones_60min_consolidated.rds  " >> "$INMAN"
echo "$ISO120  isochrones_120min_consolidated.rds  " >> "$INMAN"
echo "$ISO180  isochrones_180min_consolidated.rds  " >> "$INMAN"

say "staging code + inputs to s3://$BUCKET/$PFX/inputs/ (S3 multipart-safe cp)"
aws s3 cp "$TAR" "s3://$BUCKET/$PFX/inputs/e2sfca_code.tar.gz" --region "$REGION" --no-progress
aws s3 cp "$CODEMAN" "s3://$BUCKET/$PFX/inputs/e2sfca_code_SHA256SUMS.txt" --region "$REGION" --no-progress
aws s3 cp "$INMAN" "s3://$BUCKET/$PFX/inputs/e2sfca_inputs_SHA256SUMS.txt" --region "$REGION" --no-progress
bash scripts/s3_multipart_put.sh "$ACSB"     "$BUCKET" "$PFX/inputs/acs_bundle_2013_2022.rds" "$REGION"
aws s3 cp "artifacts/$SRCRUN/step_3_year_coord_map.rds" "s3://$BUCKET/$PFX/inputs/step_3_year_coord_map.rds" --region "$REGION" --no-progress
aws s3 cp "artifacts/$SRCRUN/step_2.5_final_cohort.rds" "s3://$BUCKET/$PFX/inputs/step_2.5_final_cohort.rds" --region "$REGION" --no-progress
aws s3 cp "$SEAMGATE" "s3://$BUCKET/$PFX/inputs/seam_report_all_2020.rds" --region "$REGION" --no-progress
say "verifying isochrones already present at s3://$BUCKET/$ISO_PFX/"
for b in 30 60 120 180; do
  aws s3api head-object --bucket "$BUCKET" --key "$ISO_PFX/isochrones_${b}min_consolidated.rds" --region "$REGION" --query ContentLength --output text >/dev/null \
    || { say "MISSING isochrone on S3: $ISO_PFX/isochrones_${b}min_consolidated.rds"; exit 1; }
done

# ── PHASE 2: security group + launch (immutable run id tag) ─────────────────
MY_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com || curl -s --max-time 5 https://api.ipify.org)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
  --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null || echo "")
[[ -z "$SG_ID" || "$SG_ID" == "None" ]] && SG_ID=$(aws ec2 create-security-group --group-name "$SGNAME" \
  --description "e2sfca compute SSH" --region "$REGION" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 \
  --cidr "${MY_IP}/32" --region "$REGION" >/dev/null 2>&1 || true
say "security group $SG_ID open to ${MY_IP}/32"

INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$ITYPE" \
  --instance-initiated-shutdown-behavior terminate --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" --iam-instance-profile "Name=$PROFILE" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":60,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUN_ID},{Key=Purpose,Value=e2sfca-11yr}]" \
  --region "$REGION" --query 'Instances[0].InstanceId' --output text)
say "launched INSTANCE_ID=$INSTANCE_ID ($ITYPE)"
echo "$INSTANCE_ID" > "/tmp/e2sfca_instance_${RUN_ID}.txt"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$REGION")
say "running: $INSTANCE_ID  ip=$PUBLIC_IP"
for i in $(seq 1 40); do ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true 2>/dev/null && break; sleep 15; done
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true || { say "SSH never came up"; exit 1; }
say "SSH up"

# ── PHASE 3: push hardened remote bootstrap + launch under nohup ────────────
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" "cat > /home/ec2-user/run_2sfca.sh" <<REMOTE
#!/usr/bin/env bash
set -uo pipefail
REGION=$REGION; BUCKET=$BUCKET; PFX=$PFX; ISO_PFX=$ISO_PFX; SRCRUN=$SRCRUN
RUN_ID=$RUN_ID; GIT_SHA=$GIT_SHA; ALLOC_SHA=$ALLOC_SHA; RESOLUTION=$RESOLUTION; YEARS=$YEARS
EXP_R=$EXP_R; EXP_SF=$EXP_SF; EXP_TERRA=$EXP_TERRA; EXP_EXR=$EXP_EXR
EXP_GEOS=$EXP_GEOS; EXP_GDAL=$EXP_GDAL; EXP_PROJ=$EXP_PROJ
S3IN="s3://\$BUCKET/\$PFX/inputs"; S3ISO="s3://\$BUCKET/\$ISO_PFX"; S3OUT="s3://\$BUCKET/\$PFX/results/\$RUN_ID"
LOG=/home/ec2-user/e2sfca.log; : > \$LOG
log(){ echo "[boot] \$*" | tee -a \$LOG; }
IID=\$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id || echo unknown)

fail(){
  log "PREFLIGHT/RUN FAILURE: \$1"
  aws s3 cp \$LOG "\$S3OUT/e2sfca_11yr.log" --region \$REGION >/dev/null 2>&1 || true
  RID="\$RUN_ID" IID="\$IID" GSHA="\$GIT_SHA" STAGE="\$1" Rscript -e 'jsonlite::write_json(list(status="FAILED", run_id=Sys.getenv("RID"), instance=Sys.getenv("IID"), git_sha=Sys.getenv("GSHA"), stage=Sys.getenv("STAGE"), when=format(Sys.time(),tz="UTC")), "/home/ec2-user/_FAILED.json", auto_unbox=TRUE, pretty=TRUE)' 2>/dev/null || echo "{\"status\":\"FAILED\",\"stage\":\"\$1\"}" > /home/ec2-user/_FAILED.json
  aws s3 cp /home/ec2-user/_FAILED.json "\$S3OUT/_FAILED.json" --region \$REGION >/dev/null 2>&1 || true
  sudo shutdown -h now; exit 1
}
( sleep 43200; sudo shutdown -h now ) &   # 12h safety ceiling

cd /home/ec2-user && rm -rf proj && mkdir proj && cd proj
log "=== download code + manifests ==="
aws s3 cp \$S3IN/e2sfca_code.tar.gz . --region \$REGION >>\$LOG 2>&1 && tar xzf e2sfca_code.tar.gz || fail "download/extract code"
touch .here
aws s3 cp \$S3IN/e2sfca_code_SHA256SUMS.txt code.sums --region \$REGION >>\$LOG 2>&1 || fail "download code manifest"
aws s3 cp \$S3IN/e2sfca_inputs_SHA256SUMS.txt inputs.sums --region \$REGION >>\$LOG 2>&1 || fail "download inputs manifest"

log "=== verify shipped code (expected committed code) ==="
for pair in "two_step_floating_catchment.R|R/two_step_floating_catchment.R" "run_2sfca.R|scripts/run_2sfca.R" "write_rds_atomic.R|R/utils/write_rds_atomic.R" "test-two-step-floating-catchment.R|tests/testthat/test-two-step-floating-catchment.R"; do
  nm=\${pair%%|*}; pth=\${pair##*|}
  exp=\$(grep "  \$nm\$" code.sums | awk '{print \$1}')
  got=\$(sha256sum "\$pth" | awk '{print \$1}')
  [ "\$exp" = "\$got" ] && log "  code OK  \$nm \$got" || fail "code checksum mismatch \$nm exp=\$exp got=\$got"
done
# allocator identity binding recorded in the code manifest must match the pin
CM_ALLOC=\$(grep "^allocator_sha " code.sums | awk '{print \$2}')
[ "\$CM_ALLOC" = "\$ALLOC_SHA" ] || fail "allocator sha in code manifest (\$CM_ALLOC) != launch pin (\$ALLOC_SHA)"
MOD_SHA=\$(sha256sum R/two_step_floating_catchment.R | awk '{print \$1}')
[ "\$MOD_SHA" = "\$ALLOC_SHA" ] || fail "shipped module sha (\$MOD_SHA) != seam-validated allocator (\$ALLOC_SHA)"
log "  ALLOCATOR IDENTITY (module sha == seam): \$MOD_SHA"

log "=== download + verify inputs (SHA-256 content, not ETag) ==="
mkdir -p artifacts/\$SRCRUN artifacts/isochrones artifacts/2sfca_seam
aws s3 cp \$S3IN/step_3_year_coord_map.rds artifacts/\$SRCRUN/ --region \$REGION >>\$LOG 2>&1 || fail "dl ycm"
aws s3 cp \$S3IN/step_2.5_final_cohort.rds artifacts/\$SRCRUN/ --region \$REGION >>\$LOG 2>&1 || fail "dl cohort"
aws s3 cp \$S3IN/acs_bundle_2013_2022.rds artifacts/2sfca_seam/ --region \$REGION >>\$LOG 2>&1 || fail "dl acs bundle"
aws s3 cp \$S3IN/seam_report_all_2020.rds artifacts/2sfca_seam/ --region \$REGION >>\$LOG 2>&1 || fail "dl seam gate"
for b in 30 60 120 180; do aws s3 cp \$S3ISO/isochrones_\${b}min_consolidated.rds artifacts/isochrones/ --region \$REGION >>\$LOG 2>&1 || fail "dl iso \$b"; done
verify_input(){ local nm="\$1" pth="\$2"; local exp got
  exp=\$(grep -E "  \$nm(  |\$)" inputs.sums | awk '{print \$1}' | head -1)
  [ -n "\$exp" ] || fail "no expected sha for \$nm"
  got=\$(sha256sum "\$pth" | awk '{print \$1}')
  [ "\$exp" = "\$got" ] && log "  input OK  \$nm  \$got  (\$(stat -c%s "\$pth") B)" || fail "input checksum mismatch \$nm exp=\$exp got=\$got"
}
verify_input acs_bundle_2013_2022.rds     artifacts/2sfca_seam/acs_bundle_2013_2022.rds
verify_input step_3_year_coord_map.rds    artifacts/\$SRCRUN/step_3_year_coord_map.rds
verify_input step_2.5_final_cohort.rds    artifacts/\$SRCRUN/step_2.5_final_cohort.rds
verify_input seam_report_all_2020.rds     artifacts/2sfca_seam/seam_report_all_2020.rds
for b in 30 60 120 180; do verify_input isochrones_\${b}min_consolidated.rds artifacts/isochrones/isochrones_\${b}min_consolidated.rds; done

log "=== ensure R packages (binaries via Posit PPM; no compilation on the AMI) ==="
MISSING=\$(Rscript -e 'cat(paste(Filter(function(p) !requireNamespace(p, quietly=TRUE), c("terra","checkmate","jsonlite","digest","here","sf","exactextractr","dplyr","purrr","testthat")), collapse=" "))' 2>>\$LOG)
if [ -n "\$MISSING" ]; then
  log "  missing: \$MISSING — installing binaries via scripts/ec2_install_pkgs.R (sudo)"
  sudo Rscript scripts/ec2_install_pkgs.R \$MISSING >>\$LOG 2>&1 || fail "package install (\$MISSING)"
  STILL=\$(Rscript -e "cat(paste(Filter(function(p) !requireNamespace(p, quietly=TRUE), strsplit(trimws('\$MISSING'),' +')[[1]]), collapse=' '))" 2>>\$LOG)
  [ -z "\$STILL" ] || fail "packages STILL missing after install: \$STILL"
  log "  installed OK: \$MISSING"
else
  log "  all required packages already present"
fi

log "=== record + ENFORCE environment lock (fail before compute on drift) ==="
Rscript -e 'sv<-sf::sf_extSoftVersion(); jsonlite::write_json(list(r_version=paste(R.version[["major"]],R.version[["minor"]],sep="."), sf=as.character(packageVersion("sf")), terra=as.character(packageVersion("terra")), exactextractr=as.character(packageVersion("exactextractr")), geos=unname(sv["GEOS"]), gdal=unname(sv["GDAL"]), proj=unname(sv["PROJ"])), "/home/ec2-user/proj/e2sfca_env_lock.json", auto_unbox=TRUE, pretty=TRUE)' >>\$LOG 2>&1 || fail "env probe"
aws s3 cp /home/ec2-user/proj/e2sfca_env_lock.json "\$S3OUT/e2sfca_env_lock.json" --region \$REGION >>\$LOG 2>&1 || true
cat /home/ec2-user/proj/e2sfca_env_lock.json | tee -a \$LOG
chk(){ local nm="\$1" got="\$2" exp="\$3"; [ "\$got" = "\$exp" ] && log "  env \$nm want=\$exp have=\$got OK" || fail "ENV LOCK DRIFT \$nm want=\$exp have=\$got"; }
GR=\$(Rscript -e 'cat(paste(R.version[["major"]],R.version[["minor"]],sep="."))'); chk r_version "\$GR" "\$EXP_R"
GSF=\$(Rscript -e 'cat(as.character(packageVersion("sf")))'); chk sf "\$GSF" "\$EXP_SF"
GTE=\$(Rscript -e 'cat(as.character(packageVersion("terra")))'); chk terra "\$GTE" "\$EXP_TERRA"
GEX=\$(Rscript -e 'cat(as.character(packageVersion("exactextractr")))'); chk exactextractr "\$GEX" "\$EXP_EXR"
GGE=\$(Rscript -e 'cat(unname(sf::sf_extSoftVersion()["GEOS"]))'); chk geos "\$GGE" "\$EXP_GEOS"
GGD=\$(Rscript -e 'cat(unname(sf::sf_extSoftVersion()["GDAL"]))'); chk gdal "\$GGD" "\$EXP_GDAL"
GPR=\$(Rscript -e 'cat(unname(sf::sf_extSoftVersion()["PROJ"]))'); chk proj "\$GPR" "\$EXP_PROJ"
log "environment lock: MATCH"

log "=== 59-test allocator conservation suite (R 4.5.1) — fail if any fail ==="
set +e
Rscript -e 'suppressMessages(library(testthat)); options(e2sfca_alloc_batch=2L); df<-as.data.frame(test_file("tests/testthat/test-two-step-floating-catchment.R", reporter="silent")); p<-sum(df\$passed); f<-sum(df\$failed); cat(sprintf("TESTS pass=%d fail=%d\n",p,f)); if(f>0 || p<59) quit(status=1)' >>\$LOG 2>&1
TRC=\$?
set -e
[ \$TRC -eq 0 ] && log "  59-test suite PASSED under \$GR" || fail "allocator test suite FAILED (rc=\$TRC)"

log "=== INPUT + CONFIG INVENTORY (permanent record) ==="
{ echo "run_id=\$RUN_ID instance=\$IID git=\$GIT_SHA ami=$AMI"
  echo "series=2013-2023 subspecs=all(expect 7) allocator=mass_conserving(area-overlap, native totals)"
  echo "AUTHORITATIVE GATE METHOD = mass_conserving (validated by seam gate seam_20260712_141012)"
  echo "resolution=\${RESOLUTION}m CRS=EPSG:5070  national_conservation_tol=0.005  allocator_conservation_tol=1e-6"
  echo "allocator_sha(seam-validated)=\$ALLOC_SHA"
  echo "--- input checksums (verified above) ---"; cat inputs.sums
  echo "--- code checksums (verified above) ---"; cat code.sums; } | tee -a \$LOG

log "=== RUN 11-year E2SFCA production series (env-locked, ACS pre-shipped) ==="
export E2SFCA_SEAM_ALLOCATOR_SHA256=\$ALLOC_SHA
export E2SFCA_GIT_SHA=\$GIT_SHA
export E2SFCA_NATIONAL_CONS_TOL=0.005
OUTD=/home/ec2-user/proj/artifacts/2sfca/run_\$RUN_ID
set +e
Rscript scripts/run_2sfca.R --subspec all --years \$YEARS --engine raster --resolution \$RESOLUTION \
  --run-id \$RUN_ID \
  --acs-bundle /home/ec2-user/proj/artifacts/2sfca_seam/acs_bundle_2013_2022.rds \
  --year-coord-map /home/ec2-user/proj/artifacts/\$SRCRUN/step_3_year_coord_map.rds \
  --cohort /home/ec2-user/proj/artifacts/\$SRCRUN/step_2.5_final_cohort.rds \
  --seam-gate-rds /home/ec2-user/proj/artifacts/2sfca_seam/seam_report_all_2020.rds \
  --out \$OUTD >> \$LOG 2>&1
RC=\$?
set -e
log "run_2sfca Rscript exit code=\$RC"
aws s3 cp \$LOG "\$S3OUT/e2sfca_11yr.log" --region \$REGION >/dev/null 2>&1 || true
[ \$RC -eq 0 ] || fail "run_2sfca nonzero exit (\$RC)"

log "=== verify + upload outputs ==="
REQ="\$OUTD/e2sfca_index.csv \$OUTD/e2sfca_national_summary.csv \$OUTD/e2sfca_run_manifest.json"
for f in \$REQ; do [ -f "\$f" ] || fail "missing required output \$f"; done
# expected cell count: 7 subspec x 11 years = 77 (allow fewer only if a cell had no providers)
NCELL=\$(grep -c "^" \$OUTD/e2sfca_index.csv || echo 0); NCELL=\$((NCELL-1))
log "  produced \$NCELL (subspec,year) cells (expect up to 77)"
# tar the entire run output dir for a single verifiable artifact
TARO=/home/ec2-user/proj/e2sfca_outputs_\$RUN_ID.tar.gz
tar czf "\$TARO" -C "\$OUTD/.." "\$(basename \$OUTD)" || fail "tar outputs"
: > /home/ec2-user/proj/outputs.sums
for f in \$REQ "\$TARO" \$LOG; do
  sha=\$(sha256sum "\$f" | awk '{print \$1}'); sz=\$(stat -c%s "\$f"); bn=\$(basename "\$f")
  aws s3 cp "\$f" "\$S3OUT/\$bn" --region \$REGION >>\$LOG 2>&1 || fail "upload \$bn"
  rsz=\$(aws s3api head-object --bucket \$BUCKET --key "\$PFX/results/\$RUN_ID/\$bn" --region \$REGION --query ContentLength --output text 2>/dev/null || echo -1)
  [ "\$rsz" = "\$sz" ] || fail "upload size mismatch \$bn local=\$sz s3=\$rsz"
  echo "\$sha  \$bn  \$sz" >> /home/ec2-user/proj/outputs.sums
  log "  output verified \$bn \$sha (\$sz B == s3 \$rsz)"
done
aws s3 cp /home/ec2-user/proj/outputs.sums "\$S3OUT/outputs.sums" --region \$REGION >/dev/null 2>&1 || true

log "=== ALL OUTPUTS VERIFIED IN S3 — writing _SUCCESS.json ==="
VERD="11-year (2013-2023) national E2SFCA series COMPLETE under the AUTHORITATIVE mass_conserving area-overlap production allocator (module sha==seam-validated \$ALLOC_SHA). Per-year national population conservation asserted (tol 0.5%); allocator per-tract+global conservation asserted (tol 1e-6). Grid/resolution/CRS identical to seam gate (\${RESOLUTION}m, EPSG:5070). Authoritative gate method = mass_conserving; equal_total/geometry_only are diagnostics, not the gate. \$NCELL (subspec,year) cells."
RID="\$RUN_ID" IID="\$IID" GSHA="\$GIT_SHA" AMI="$AMI" VERD="\$VERD" NC="\$NCELL" ASHA="\$ALLOC_SHA" Rscript -e '
outs <- readLines("/home/ec2-user/proj/outputs.sums")
env  <- jsonlite::read_json("/home/ec2-user/proj/e2sfca_env_lock.json")
ins  <- readLines("/home/ec2-user/proj/inputs.sums")
jsonlite::write_json(list(status="SUCCESS", run_id=Sys.getenv("RID"), instance=Sys.getenv("IID"),
  git_sha=Sys.getenv("GSHA"), ami=Sys.getenv("AMI"), when=format(Sys.time(),tz="UTC"),
  authoritative_gate_method="mass_conserving (area-overlap, native totals)",
  allocator_sha256=Sys.getenv("ASHA"), n_cells=as.integer(Sys.getenv("NC")),
  verdict=Sys.getenv("VERD"), environment=env, input_checksums=ins, output_checksums=outs),
  "/home/ec2-user/_SUCCESS.json", auto_unbox=TRUE, pretty=TRUE)' 2>>\$LOG || fail "assemble _SUCCESS.json"
aws s3 cp /home/ec2-user/_SUCCESS.json "\$S3OUT/_SUCCESS.json" --region \$REGION >>\$LOG 2>&1 || fail "upload _SUCCESS.json"
aws s3 cp \$LOG "\$S3OUT/e2sfca_11yr.log" --region \$REGION >/dev/null 2>&1 || true
log "DONE — _SUCCESS.json written. self-terminating."
sudo shutdown -h now
REMOTE
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" "chmod +x /home/ec2-user/run_2sfca.sh && nohup bash /home/ec2-user/run_2sfca.sh > /home/ec2-user/run_2sfca.out 2>&1 & echo REMOTE-LAUNCHED"
say "remote 11-year run launched on $INSTANCE_ID under nohup"

# ── PHASE 4: poll S3 for the distinct terminal sentinels ────────────────────
say "polling s3://$BUCKET/$RESULTS/ for _SUCCESS.json / _FAILED.json ..."
OUTCOME="none"; dead=0
for i in $(seq 1 720); do   # ~12h ceiling
  if aws s3 ls "s3://$BUCKET/$RESULTS/_SUCCESS.json" --region "$REGION" >/dev/null 2>&1; then say "=== _SUCCESS.json ==="; OUTCOME="success"; break; fi
  if aws s3 ls "s3://$BUCKET/$RESULTS/_FAILED.json"  --region "$REGION" >/dev/null 2>&1; then say "=== _FAILED.json ===";  OUTCOME="failed";  break; fi
  ST=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo unknown)
  if [[ "$ST" == "terminated" || "$ST" == "stopped" || "$ST" == "stopping" ]]; then
    dead=$((dead+1)); [[ $dead -ge 2 ]] && { say "WARNING: instance $ST with NO sentinel — treating as failure. Inspect s3://$BUCKET/$RESULTS/"; OUTCOME="dead-no-sentinel"; break; }
  else dead=0; fi
  sleep 60
done
[[ "$OUTCOME" == "none" ]] && say "WARNING: poll ceiling reached with no sentinel — re-attach with PHASE=monitor RUN_ID=$RUN_ID"
mkdir -p "artifacts/2sfca/ec2/$RUN_ID"
aws s3 cp "s3://$BUCKET/$RESULTS/" "artifacts/2sfca/ec2/$RUN_ID/" --recursive --region "$REGION" --no-progress || true
say "results in artifacts/2sfca/ec2/$RUN_ID/  (RUN_ID=$RUN_ID, OUTCOME=$OUTCOME)"
