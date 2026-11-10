#!/usr/bin/env bash
set -euo pipefail
: "${TARGET_HOST:?Set TARGET_HOST to an approved test/staging URL, e.g. https://staging.example.com}"
if [[ ! "$TARGET_HOST" =~ ^https?:// ]]; then
  echo 'TARGET_HOST must begin with http:// or https://' >&2
  exit 2
fi
: "${CAPSTONE_PRODUCT_PATH:?Set CAPSTONE_PRODUCT_PATH to the verified product listing endpoint path}"
if [[ ! "$CAPSTONE_PRODUCT_PATH" == /* || "$CAPSTONE_PRODUCT_PATH" == //* ]]; then
  echo 'CAPSTONE_PRODUCT_PATH must begin with one /' >&2
  exit 2
fi
LOAD_PROFILE="${LOAD_PROFILE:-baseline}"
case "$LOAD_PROFILE" in baseline|flash-demo|flash-2h) ;; *) echo 'Invalid LOAD_PROFILE' >&2; exit 2;; esac
OUT="${OUTPUT_DIR:-results/$(date -u +%Y%m%dT%H%M%SZ)-${LOAD_PROFILE}}"
mkdir -p "$(dirname "$OUT")"
export LOAD_PROFILE CAPSTONE_PRODUCT_PATH
printf 'Host: %s\nPath: %s\nProfile: %s\nResults: %s\n' "$TARGET_HOST" "$CAPSTONE_PRODUCT_PATH" "$LOAD_PROFILE" "$OUT"
locust -f locustfile.py --headless --host "$TARGET_HOST" \
  --csv "$OUT" --csv-full-history --html "${OUT}.html" \
  --only-summary
