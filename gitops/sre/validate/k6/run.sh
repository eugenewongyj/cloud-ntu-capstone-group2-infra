#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
: "${TARGET_HOST:?Set approved production TARGET_HOST}"
: "${CAPSTONE_PRODUCT_PATH:?Set verified CAPSTONE_PRODUCT_PATH}"
case "$TARGET_HOST" in https://*|http://*) ;; *) echo "Invalid TARGET_HOST" >&2; exit 2;; esac
case "$CAPSTONE_PRODUCT_PATH" in /*) case "$CAPSTONE_PRODUCT_PATH" in //*) exit 2;; esac;; *) exit 2;; esac
: "${LOAD_PROFILE:?Select normal or 1111}"
: "${RECOVERY_MINUTES:=10}"
: "${ASSESSMENT_RUN:=$(date -u +%Y%m%dT%H%M%SZ)-$$}"

case "$LOAD_PROFILE" in
  normal|1111) ;;
  *) echo "Invalid LOAD_PROFILE" >&2; exit 2 ;;
esac

export RECOVERY_MINUTES ASSESSMENT_RUN
: "${BASE_USERS:=1}"
mkdir -p results
export TARGET_HOST CAPSTONE_PRODUCT_PATH LOAD_PROFILE BASE_USERS
if [[ "${CAPSTONE_K6_REMOTE_WRITE:-}" == YES ]]; then
  : "${K6_PROMETHEUS_RW_SERVER_URL:?Set an authorized, reachable Prometheus remote-write URL}"
  export K6_PROMETHEUS_RW_SERVER_URL
  export K6_PROMETHEUS_RW_TREND_STATS="p(95)"
  k6 run -o experimental-prometheus-rw \
  -e "TARGET_HOST=$TARGET_HOST" \
  -e "CAPSTONE_PRODUCT_PATH=$CAPSTONE_PRODUCT_PATH" \
  -e "LOAD_PROFILE=$LOAD_PROFILE" \
  -e "BASE_USERS=$BASE_USERS" \
  -e "CAPSTONE_EXPECT_TEXT=${CAPSTONE_EXPECT_TEXT:-}" \
  --summary-export results/summary.json \
  product-listing.js
else
  k6 run \
  -e "TARGET_HOST=$TARGET_HOST" \
  -e "CAPSTONE_PRODUCT_PATH=$CAPSTONE_PRODUCT_PATH" \
  -e "LOAD_PROFILE=$LOAD_PROFILE" \
  -e "BASE_USERS=$BASE_USERS" \
  -e "CAPSTONE_EXPECT_TEXT=${CAPSTONE_EXPECT_TEXT:-}" \
  --summary-export results/summary.json \
  product-listing.js
fi
