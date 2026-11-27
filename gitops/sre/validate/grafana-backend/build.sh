#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

export GOTOOLCHAIN=go1.27.4

go mod verify
go test ./...
go vet ./...

rm -rf dist
mkdir -p dist

(
    cd ../grafana-plugin
    npx --no-install webpack --config webpack.app.config.cjs
)

cp -a src/. dist/

CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build \
  -trimpath \
  -ldflags="-s -w" \
  -o dist/gpx_capstone_srecontrol_linux_amd64 .

test -s dist/plugin.json
test -s dist/module.js
test -x dist/gpx_capstone_srecontrol_linux_amd64

echo "PASS: Grafana backend package"
