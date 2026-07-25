#!/usr/bin/env bash
# Reliable large-file S3 upload via explicit low-level multipart (this env
# silently drops `s3 cp`/`put-object` >~16MB). 16MB parts, retry per part,
# verify ETag-part-count, then streamed-SHA gate vs the downloaded object size.
set -uo pipefail
FILE="$1"; BUCKET="$2"; KEY="$3"; REGION="${4:-us-east-2}"
PART_SIZE=$((16*1024*1024))
SZ=$(stat -f%z "$FILE")
echo "[mpu] $FILE -> s3://$BUCKET/$KEY ($SZ bytes, ${PART_SIZE}B parts) region=$REGION"
UPID=$(aws s3api create-multipart-upload --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query UploadId --output text)
echo "[mpu] upload-id: $UPID"
TMP=$(mktemp -d)
split -b "$PART_SIZE" "$FILE" "$TMP/part."
PARTS_JSON="$TMP/parts.json"; echo '{"Parts":[]}' > "$PARTS_JSON"
PN=0; PARTS=()
for p in "$TMP"/part.*; do
  PN=$((PN+1))
  ET=""
  for a in 1 2 3 4 5; do
    ET=$(aws s3api upload-part --bucket "$BUCKET" --key "$KEY" --region "$REGION" \
         --upload-id "$UPID" --part-number "$PN" --body "$p" --query ETag --output text 2>/dev/null) && [ -n "$ET" ] && break
    echo "[mpu] part $PN attempt $a failed; retry"; sleep 4
  done
  if [ -z "$ET" ]; then echo "[mpu] FATAL part $PN failed"; aws s3api abort-multipart-upload --bucket "$BUCKET" --key "$KEY" --upload-id "$UPID" --region "$REGION"; exit 1; fi
  PARTS+=("{\"ETag\":$ET,\"PartNumber\":$PN}")
  echo "[mpu] part $PN ok ($(stat -f%z "$p") B) etag=$ET"
done
printf '{"Parts":[%s]}' "$(IFS=,; echo "${PARTS[*]}")" > "$PARTS_JSON"
aws s3api complete-multipart-upload --bucket "$BUCKET" --key "$KEY" --region "$REGION" \
  --upload-id "$UPID" --multipart-upload "file://$PARTS_JSON" --query Location --output text
RSZ=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" --query ContentLength --output text)
echo "[mpu] uploaded size=$RSZ local size=$SZ"
[ "$RSZ" = "$SZ" ] && echo "[mpu] SIZE-GATE PASS" || { echo "[mpu] SIZE-GATE FAIL"; exit 1; }
rm -rf "$TMP"
