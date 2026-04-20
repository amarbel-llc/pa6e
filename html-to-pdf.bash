#!/usr/bin/env bash
set -euo pipefail

target="$1"

chrest capture \
  --format pdf \
  --url "file://$(realpath "$target")" \
  --output "$target.pdf" \
  --no-headers \
  --background \
  --paper-width 2.2409 \
  --margin-left 0 \
  --margin-right 0
