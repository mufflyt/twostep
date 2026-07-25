#!/usr/bin/env bash
# =============================================================================
# ec2_run_seam.sh — run the 4-method national E2SFCA tract-vintage seam gate on
# EC2 (r6i.2xlarge / 64 GB), HARDENED. S3-transport-only. Preflight-gated:
#   * every input verified by SHA-256 (content, not ETag) before R starts;
#   * the shipped seam runner verified by SHA-256 against a code manifest;
#   * exact R/sf/terra/exactextractr/GDAL/GEOS/PROJ recorded + enforced (env lock);
#   * full input+config inventory printed to the permanent log before R;
#   * distinct terminal sentinels: _SUCCESS.json (only after every output+log+
#     checksum is uploaded AND re-verified in S3) vs _FAILED.json (+ full log).
#     No shell trap can create the success sentinel.
# Inputs are pre-staged to s3://$BUCKET/$PFX/inputs/ with a SHA256SUMS manifest.
# Usage:  bash scripts/ec2_run_seam.sh
#         PHASE=monitor RUN_ID=... bash scripts/ec2_run_seam.sh   # re-attach poll
# =============================================================================
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$PROJECT_ROOT"

REGION="${EC2_REGION:-us-east-2}"
BUCKET="${S3_BUCKET:-tyler-valhalla-tiles}"
PFX="${S3_PREFIX:-seam_run}"
AMI="${AMI_ID:-ami-081b31d5df91089c4}"
ITYPE="${INSTANCE_TYPE:-r6i.2xlarge}"
KEY_PATH="${KEY_PATH:-$HOME/.ssh/valhalla-key-tmuff2.pem}"
KEY_NAME="${KEY_NAME:-valhalla-key-tmuff2}"
PROFILE="${IAM_PROFILE:-valhalla-ec2-profile}"
SGNAME="${SG_NAME:-valhalla-sg}"
SRCRUN="${SRCRUN:-20260702_120134_90bf52ef}"          # artifacts dir the ycm/cohort came from
RUN_ID="${RUN_ID:-seam_$(date -u +%Y%m%d_%H%M%S)}"    # immutable per launch
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
RESULTS="$PFX/results/$RUN_ID"
SSH_OPTS="-i $KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=15 -o ServerAliveInterval=30 -o ServerAliveCountMax=6"
say(){ echo "[ec2-seam] $*"; }

# ── PHASE monitor (re-attach) ───────────────────────────────────────────────
if [[ "${PHASE:-all}" == "monitor" ]]; then
  say "polling s3://$BUCKET/$RESULTS/ for _SUCCESS.json / _FAILED.json ..."
  while true; do
    aws s3 ls "s3://$BUCKET/$RESULTS/_SUCCESS.json" --region "$REGION" >/dev/null 2>&1 && { say "_SUCCESS.json"; break; }
    aws s3 ls "s3://$BUCKET/$RESULTS/_FAILED.json"  --region "$REGION" >/dev/null 2>&1 && { say "_FAILED.json";  break; }
    sleep 60
  done
  mkdir -p "artifacts/2sfca_seam/ec2/$RUN_ID"
  aws s3 cp "s3://$BUCKET/$RESULTS/" "artifacts/2sfca_seam/ec2/$RUN_ID/" --recursive --region "$REGION" --no-progress || true
  say "results in artifacts/2sfca_seam/ec2/$RUN_ID/"; exit 0
fi

# ── PHASE 1: (re)stage code + code manifest + ycm/cohort; verify big inputs ──
say "RUN_ID=$RUN_ID  git=$GIT_SHA  region=$REGION"
TAR=/tmp/seam_code.tar.gz
tar czf "$TAR" -C "$PROJECT_ROOT" R/two_step_floating_catchment.R scripts/seam_test_2sfca.R DESCRIPTION .here
# code manifest recomputed from the EXACT files being shipped (consistency)
CODEMAN=/tmp/seam_code_SHA256SUMS.txt; : > "$CODEMAN"
for f in R/two_step_floating_catchment.R scripts/seam_test_2sfca.R; do
  shasum -a 256 "$f" | awk -v n="$(basename "$f")" '{print $1"  "n}' >> "$CODEMAN"; done
echo "git_sha $GIT_SHA" >> "$CODEMAN"
aws s3 cp "$TAR" "s3://$BUCKET/$PFX/inputs/seam_code.tar.gz" --region "$REGION" --no-progress
aws s3 cp "$CODEMAN" "s3://$BUCKET/$PFX/inputs/seam_code_SHA256SUMS.txt" --region "$REGION" --no-progress
aws s3 cp "artifacts/$SRCRUN/step_3_year_coord_map.rds" "s3://$BUCKET/$PFX/inputs/step_3_year_coord_map.rds" --region "$REGION" --no-progress
aws s3 cp "artifacts/$SRCRUN/step_2.5_final_cohort.rds" "s3://$BUCKET/$PFX/inputs/step_2.5_final_cohort.rds" --region "$REGION" --no-progress
say "verifying pre-staged inputs + manifest exist on S3"
for k in seam_inputs_SHA256SUMS.txt seam_acs_bundle_2020.rds \
         isochrones/isochrones_30min_consolidated.rds isochrones/isochrones_60min_consolidated.rds \
         isochrones/isochrones_120min_consolidated.rds isochrones/isochrones_180min_consolidated.rds; do
  aws s3api head-object --bucket "$BUCKET" --key "$PFX/inputs/$k" --region "$REGION" --query ContentLength --output text >/dev/null \
    || { say "MISSING s3://$BUCKET/$PFX/inputs/$k"; exit 1; }
done

# ── PHASE 2: security group + launch (immutable run id tag) ─────────────────
MY_IP=$(curl -s --max-time 5 https://checkip.amazonaws.com || curl -s --max-time 5 https://api.ipify.org)
SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=$SGNAME" \
  --query 'SecurityGroups[0].GroupId' --output text --region "$REGION" 2>/dev/null || echo "")
[[ -z "$SG_ID" || "$SG_ID" == "None" ]] && SG_ID=$(aws ec2 create-security-group --group-name "$SGNAME" \
  --description "seam compute SSH" --region "$REGION" --query GroupId --output text)
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 \
  --cidr "${MY_IP}/32" --region "$REGION" >/dev/null 2>&1 || true
say "security group $SG_ID open to ${MY_IP}/32"

INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI" --instance-type "$ITYPE" \
  --instance-initiated-shutdown-behavior terminate --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" --iam-instance-profile "Name=$PROFILE" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":40,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$RUN_ID},{Key=Purpose,Value=seam-4method}]" \
  --region "$REGION" --query 'Instances[0].InstanceId' --output text)
say "launched INSTANCE_ID=$INSTANCE_ID ($ITYPE)"
echo "$INSTANCE_ID" > "/tmp/seam_instance_${RUN_ID}.txt"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text --region "$REGION")
say "running: $INSTANCE_ID  ip=$PUBLIC_IP"
for i in $(seq 1 40); do ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true 2>/dev/null && break; sleep 15; done
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" true || { say "SSH never came up"; exit 1; }
say "SSH up"

# ── PHASE 3: push hardened remote bootstrap + launch under nohup ────────────
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" "cat > /home/ec2-user/run_seam.sh" <<REMOTE
#!/usr/bin/env bash
set -uo pipefail
REGION=$REGION; BUCKET=$BUCKET; PFX=$PFX; SRCRUN=$SRCRUN; RUN_ID=$RUN_ID; GIT_SHA=$GIT_SHA
S3IN="s3://\$BUCKET/\$PFX/inputs"; S3OUT="s3://\$BUCKET/\$PFX/results/\$RUN_ID"
LOG=/home/ec2-user/seam.log; : > \$LOG
log(){ echo "[boot] \$*" | tee -a \$LOG; }
IID=\$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id || echo unknown)

fail(){ # \$1 = stage message
  log "PREFLIGHT/RUN FAILURE: \$1"
  aws s3 cp \$LOG "\$S3OUT/seam_all7_4method.log" --region \$REGION >/dev/null 2>&1 || true
  RID="\$RUN_ID" IID="\$IID" GSHA="\$GIT_SHA" STAGE="\$1" Rscript -e 'jsonlite::write_json(list(status="FAILED", run_id=Sys.getenv("RID"), instance=Sys.getenv("IID"), git_sha=Sys.getenv("GSHA"), stage=Sys.getenv("STAGE"), when=format(Sys.time(),tz="UTC")), "/home/ec2-user/_FAILED.json", auto_unbox=TRUE, pretty=TRUE)' 2>/dev/null || echo "{\"status\":\"FAILED\",\"stage\":\"\$1\"}" > /home/ec2-user/_FAILED.json
  aws s3 cp /home/ec2-user/_FAILED.json "\$S3OUT/_FAILED.json" --region \$REGION >/dev/null 2>&1 || true
  sudo shutdown -h now; exit 1
}
( sleep 18000; sudo shutdown -h now ) &   # 5h safety ceiling

cd /home/ec2-user && rm -rf proj && mkdir proj && cd proj
log "=== download code + manifests ==="
aws s3 cp \$S3IN/seam_code.tar.gz . --region \$REGION >>\$LOG 2>&1 && tar xzf seam_code.tar.gz || fail "download/extract code"
touch .here
aws s3 cp \$S3IN/seam_code_SHA256SUMS.txt code.sums --region \$REGION >>\$LOG 2>&1 || fail "download code manifest"
aws s3 cp \$S3IN/seam_inputs_SHA256SUMS.txt inputs.sums --region \$REGION >>\$LOG 2>&1 || fail "download inputs manifest"

log "=== verify seam runner (expected committed runner) ==="
for pair in "two_step_floating_catchment.R|R/two_step_floating_catchment.R" "seam_test_2sfca.R|scripts/seam_test_2sfca.R"; do
  nm=\${pair%%|*}; pth=\${pair##*|}
  exp=\$(grep "  \$nm\$" code.sums | awk '{print \$1}')
  got=\$(sha256sum "\$pth" | awk '{print \$1}')
  [ "\$exp" = "\$got" ] && log "  runner OK  \$nm \$got" || fail "runner checksum mismatch \$nm exp=\$exp got=\$got"
done

log "=== download + verify inputs (SHA-256 content, not ETag) ==="
mkdir -p artifacts/\$SRCRUN artifacts/isochrones artifacts/2sfca_seam
aws s3 cp \$S3IN/step_3_year_coord_map.rds artifacts/\$SRCRUN/ --region \$REGION >>\$LOG 2>&1 || fail "dl ycm"
aws s3 cp \$S3IN/step_2.5_final_cohort.rds artifacts/\$SRCRUN/ --region \$REGION >>\$LOG 2>&1 || fail "dl cohort"
aws s3 cp \$S3IN/seam_acs_bundle_2020.rds artifacts/2sfca_seam/ --region \$REGION >>\$LOG 2>&1 || fail "dl acs"
for b in 30 60 120 180; do aws s3 cp \$S3IN/isochrones/isochrones_\${b}min_consolidated.rds artifacts/isochrones/ --region \$REGION >>\$LOG 2>&1 || fail "dl iso \$b"; done
verify_input(){ local nm="\$1" pth="\$2"; local exp got
  exp=\$(grep "  \$nm  " inputs.sums | awk '{print \$1}')
  [ -n "\$exp" ] || fail "no expected sha for \$nm"
  got=\$(sha256sum "\$pth" | awk '{print \$1}')
  [ "\$exp" = "\$got" ] && log "  input OK  \$nm  \$got  (\$(stat -c%s "\$pth") B)" || fail "input checksum mismatch \$nm exp=\$exp got=\$got"
}
verify_input seam_acs_bundle_2020.rds           artifacts/2sfca_seam/seam_acs_bundle_2020.rds
for b in 30 60 120 180; do verify_input isochrones_\${b}min_consolidated.rds artifacts/isochrones/isochrones_\${b}min_consolidated.rds; done

log "=== ensure R packages ==="
Rscript -e 'for (p in c("terra","checkmate","jsonlite","digest","here","sf","exactextractr","dplyr","purrr")) if (!requireNamespace(p, quietly=TRUE)) install.packages(p, repos="https://cloud.r-project.org")' >>\$LOG 2>&1 || fail "package ensure"

log "=== record + lock environment ==="
Rscript -e 'sv<-sf::sf_extSoftVersion(); jsonlite::write_json(list(r_version=paste(R.version[["major"]],R.version[["minor"]],sep="."), sf=as.character(packageVersion("sf")), terra=as.character(packageVersion("terra")), exactextractr=as.character(packageVersion("exactextractr")), geos=unname(sv["GEOS"]), gdal=unname(sv["GDAL"]), proj=unname(sv["PROJ"])), "/home/ec2-user/proj/seam_env_lock.json", auto_unbox=TRUE, pretty=TRUE)' >>\$LOG 2>&1 || fail "env probe"
aws s3 cp /home/ec2-user/proj/seam_env_lock.json "\$S3OUT/seam_env_lock.json" --region \$REGION >>\$LOG 2>&1 || true
log "env lock:"; cat /home/ec2-user/proj/seam_env_lock.json | tee -a \$LOG

log "=== INPUT + CONFIG INVENTORY (permanent record) ==="
{ echo "run_id=\$RUN_ID instance=\$IID git=\$GIT_SHA ami=$AMI"
  echo "subspecs=all(expect 7)  methods=4(raw,equal_total,mass_conserving,mass_conserving_eqtot)"
  echo "thresholds=0,1,5,10,20,50  tol_mean_rel=0.02 tol_share_abs=0.01  resolution=500  CRS=EPSG:5070"
  echo "--- input checksums (verified above) ---"; cat inputs.sums
  echo "--- runner checksums (verified above) ---"; cat code.sums; } | tee -a \$LOG

log "=== RUN seam (env-locked, ACS pre-shipped) ==="
export SEAM_ACS_RDS=/home/ec2-user/proj/artifacts/2sfca_seam/seam_acs_bundle_2020.rds
export SEAM_ENV_LOCK=/home/ec2-user/proj/seam_env_lock.json
set +e
Rscript scripts/seam_test_2sfca.R --subspecs all --year 2020 --resolution 500 >> \$LOG 2>&1
RC=\$?
set -e
log "seam Rscript exit code=\$RC"

# upload log always
aws s3 cp \$LOG "\$S3OUT/seam_all7_4method.log" --region \$REGION >/dev/null 2>&1 || true
[ \$RC -eq 0 ] || fail "seam Rscript nonzero exit (\$RC)"

log "=== verify + upload required outputs ==="
REQ="artifacts/2sfca_seam/seam_report_all_2020.rds artifacts/2sfca_seam/seam_summary_2020.csv artifacts/2sfca_seam/seam_prespec_2020.json"
for f in \$REQ; do [ -f "\$f" ] || fail "missing required output \$f"; done
: > /home/ec2-user/proj/outputs.sums
for f in \$REQ \$LOG; do
  sha=\$(sha256sum "\$f" | awk '{print \$1}'); sz=\$(stat -c%s "\$f")
  bn=\$(basename "\$f")
  aws s3 cp "\$f" "\$S3OUT/\$bn" --region \$REGION >>\$LOG 2>&1 || fail "upload \$bn"
  rsz=\$(aws s3api head-object --bucket \$BUCKET --key "\$PFX/results/\$RUN_ID/\$bn" --region \$REGION --query ContentLength --output text 2>/dev/null || echo -1)
  [ "\$rsz" = "\$sz" ] || fail "upload size mismatch \$bn local=\$sz s3=\$rsz"
  echo "\$sha  \$bn  \$sz" >> /home/ec2-user/proj/outputs.sums
  log "  output verified \$bn \$sha (\$sz B == s3 \$rsz)"
done
aws s3 cp /home/ec2-user/proj/outputs.sums "\$S3OUT/outputs.sums" --region \$REGION >/dev/null 2>&1 || true

# extract the verdict/gate line for the sentinel
VERDICT=\$(grep -a "VERDICT:" \$LOG | tail -1 | sed 's/^\[seam\] VERDICT: //')
log "=== ALL OUTPUTS VERIFIED IN S3 — writing _SUCCESS.json ==="
RID="\$RUN_ID" IID="\$IID" GSHA="\$GIT_SHA" AMI="$AMI" VERD="\$VERDICT" Rscript -e '
outs <- readLines("/home/ec2-user/proj/outputs.sums")
env  <- jsonlite::read_json("/home/ec2-user/proj/seam_env_lock.json")
ins  <- readLines("/home/ec2-user/proj/inputs.sums")
jsonlite::write_json(list(status="SUCCESS", run_id=Sys.getenv("RID"), instance=Sys.getenv("IID"),
  git_sha=Sys.getenv("GSHA"), ami=Sys.getenv("AMI"), when=format(Sys.time(),tz="UTC"),
  verdict=Sys.getenv("VERD"), environment=env, input_checksums=ins, output_checksums=outs),
  "/home/ec2-user/_SUCCESS.json", auto_unbox=TRUE, pretty=TRUE)' 2>>\$LOG || fail "assemble _SUCCESS.json"
aws s3 cp /home/ec2-user/_SUCCESS.json "\$S3OUT/_SUCCESS.json" --region \$REGION >>\$LOG 2>&1 || fail "upload _SUCCESS.json"
# re-upload the final log (now includes the success lines)
aws s3 cp \$LOG "\$S3OUT/seam_all7_4method.log" --region \$REGION >/dev/null 2>&1 || true
log "DONE — _SUCCESS.json written. self-terminating."
sudo shutdown -h now
REMOTE
ssh $SSH_OPTS "ec2-user@$PUBLIC_IP" "chmod +x /home/ec2-user/run_seam.sh && nohup bash /home/ec2-user/run_seam.sh > /home/ec2-user/run_seam.out 2>&1 & echo REMOTE-LAUNCHED"
say "remote seam launched on $INSTANCE_ID under nohup"

# ── PHASE 4: poll S3 for the distinct terminal sentinels ────────────────────
say "polling s3://$BUCKET/$RESULTS/ for _SUCCESS.json / _FAILED.json ..."
OUTCOME="none"; dead=0
for i in $(seq 1 220); do   # ~220 min ceiling
  if aws s3 ls "s3://$BUCKET/$RESULTS/_SUCCESS.json" --region "$REGION" >/dev/null 2>&1; then say "=== _SUCCESS.json ==="; OUTCOME="success"; break; fi
  if aws s3 ls "s3://$BUCKET/$RESULTS/_FAILED.json"  --region "$REGION" >/dev/null 2>&1; then say "=== _FAILED.json ===";  OUTCOME="failed";  break; fi
  # if the instance has died without writing a sentinel, don't poll forever
  ST=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --region "$REGION" \
        --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo unknown)
  if [[ "$ST" == "terminated" || "$ST" == "stopped" || "$ST" == "stopping" ]]; then
    dead=$((dead+1)); [[ $dead -ge 2 ]] && { say "WARNING: instance $ST with NO sentinel — treating as failure. Inspect s3://$BUCKET/$RESULTS/"; OUTCOME="dead-no-sentinel"; break; }
  else dead=0; fi
  sleep 60
done
[[ "$OUTCOME" == "none" ]] && say "WARNING: poll ceiling reached with no sentinel — instance may still be running; re-attach with PHASE=monitor RUN_ID=$RUN_ID"
mkdir -p "artifacts/2sfca_seam/ec2/$RUN_ID"
aws s3 cp "s3://$BUCKET/$RESULTS/" "artifacts/2sfca_seam/ec2/$RUN_ID/" --recursive --region "$REGION" --no-progress || true
say "results in artifacts/2sfca_seam/ec2/$RUN_ID/  (RUN_ID=$RUN_ID)"
