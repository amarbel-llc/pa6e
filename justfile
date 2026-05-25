
default: lint build

# --- pre-build ---

[group('pre-build')]
lint: lint-fmt

# Check that all source files match treefmt's expected formatting.
# Sandboxed check derivation (no working-tree side effects); exits 1
# on drift. `just fmt` is the corresponding write mode. Resolving the
# system tuple via `nix eval` keeps the recipe portable across linux /
# darwin without depending on just's `os()` (which returns `macos`,
# not nix's `darwin`).
[group('pre-build')]
lint-fmt:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#checks.${system}.treefmt"

# Verify the devShell evaluates and builds without errors. Catches
# regressions that the prod-binary build path can mask (the devShell
# and the wrapped binary are different derivations through different
# code paths). No store-output usage — just a build-check.
[group('pre-build')]
validate-devshell:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#devShells.${system}.default"

# --- build ---

[group('build')]
build: build-cargo build-nix

[group('build')]
build-cargo:
  cd rs && cargo build

[group('build')]
build-nix:
  nix build --show-trace

# --- codemod ---

# Format all source files via treefmt-nix (rustfmt for Rust, nixfmt
# for Nix, shfmt for shell/bats). Config lives in ./treefmt.nix;
# `nix fmt` runs the same wrapper.
[group('codemod')]
fmt:
  nix fmt

# --- debug ---

# Render label.md through the full pipeline without printing
[group('debug')]
render target='label.md':
  pandoc --output "{{target}}.html" --standalone --embed-resources --css peri-a6.css "{{target}}"
  chrest capture \
    --format pdf \
    --url "file://$(realpath '{{target}}.html')" \
    --output "{{target}}.html.pdf" \
    --no-headers \
    --background \
    --paper-width 2.2409 \
    --margin-left 0 \
    --margin-right 0
  magick -density 512 "{{target}}.html.pdf" \
    -background white -flatten -resize 576 "{{target}}.html.pdf.png"
  @echo "{{target}}.html.pdf.png"
