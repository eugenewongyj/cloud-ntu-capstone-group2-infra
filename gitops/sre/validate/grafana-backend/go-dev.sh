#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

CACHE="$HOME/.cache/capstone-go"

mkdir -p "$CACHE/modules"
mkdir -p "$CACHE/build"
mkdir -p "$CACHE/sumdb/sum.golang.org"

exec docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e GOPATH=/go \
  -e GOMODCACHE=/go/pkg/mod \
  -e GOCACHE=/go-cache \
  -e GOTOOLCHAIN=go1.27.4 \
  -e GOSUMDB=sum.golang.org \
  -v "$CACHE/modules:/go/pkg/mod" \
  -v "$CACHE/sumdb:/go/pkg/sumdb" \
  -v "$CACHE/build:/go-cache" \
  -v "$PWD:/workspace" \
  -w /workspace \
  golang:1.26-bookworm \
  go "$@"
