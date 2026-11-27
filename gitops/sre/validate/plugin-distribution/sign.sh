#!/usr/bin/env bash
set -Eeuo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ROOT_URL="https://group2-capstone-grafana.sctp-sandbox.com/"

: "${GRAFANA_ACCESS_POLICY_TOKEN:?Signing credential required}"

export GRAFANA_ACCESS_POLICY_TOKEN

for plugin in grafana-plugin grafana-backend; do
    (
        cd "$BASE/$plugin"

        test -s dist/plugin.json
        test -s dist/module.js

        npx --yes @grafana/sign-plugin@4.0.0 \
            --rootUrls "$ROOT_URL"

        test -s dist/MANIFEST.txt
    )

    echo "PASS: $plugin signature manifest"
done
