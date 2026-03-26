#!/usr/bin/env bash
set -euo pipefail

source .env
nix run . -- label.md
nix run .#pa6e -- -p A6p -m "$peri_primary" -i label.md-trimmed.png -c 2
