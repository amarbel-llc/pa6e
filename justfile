default: validate lint build test

# --- pre-build ---

[group("pre-build")]
validate: validate-devshell validate-manpages

# Verify the devShell evaluates and builds without errors. Catches
# regressions that the prod-binary build path can mask (the devShell
# and the wrapped binary are different derivations through different
# code paths). No store-output usage — just a build-check. Resolving the
# system tuple via `nix eval` keeps the recipe portable across linux /
# darwin without depending on just's `os()` (which returns `macos`, not
# nix's `darwin`).
[group("pre-build")]
validate-devshell:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#devShells.${system}.default"

# scdoc syntax gate: building the pa6e-manpages derivation runs scdoc
# over doc/*.1.scd in a sandbox, so a syntax error fails the build. No
# scdoc-in-devshell needed.
[group("pre-build")]
validate-manpages:
  nix build --print-build-logs --no-link ".#pa6e-manpages"

[group("pre-build")]
lint: lint-fmt

# Read-only formatting gate: builds the `checks.formatting` derivation,
# which runs treefmt against a /nix/store snapshot and fails if anything
# would change. Does NOT modify the worktree — the modifying counterpart
# is `codemod-fmt-treefmt`.
[group("pre-build")]
lint-fmt:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#checks.${system}.formatting"

# --- build ---

[group("build")]
build: build-nix

# Canonical build. cargo is intentionally absent from the devShell, so
# every build goes through nix (crane). crane caches dependency
# compilation in the Cargo.lock-keyed cargoArtifacts derivation, so only
# pa6e's own crate recompiles on a source edit.
[group("build")]
build-nix:
  nix build --show-trace

# --- post-build ---

[group("post-build")]
test: test-cargo

# Run the test suite through nix (crane cargoTest, reusing the cached
# cargoArtifacts). Mirror of the `checks.tests` flake output.
[group("post-build")]
test-cargo:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#checks.${system}.tests"

# --- run ---

# Run the wrapped binary with the pipeline tools (chrest/pandoc/magick/
# ghostscript) on PATH. Usage: just run-nix print label.md
run-nix *ARGS:
  nix run . -- {{ARGS}}

# --- codemod ---

[group("codemod")]
codemod-fmt: codemod-fmt-treefmt

# Format all source files via treefmt-nix (rustfmt for Rust, nixfmt for
# Nix, shfmt for shell/bats). Config lives in ./treefmt.nix; `nix fmt`
# runs the same wrapper. The read-only counterpart is `lint-fmt`.
[group("codemod")]
codemod-fmt-treefmt:
  nix fmt

# --- maintenance ---

# Sed-rewrite PA6E_VERSION in version.env to the given semver, and keep
# rs/Cargo.toml's package version in lockstep. version.env is the single
# source of truth (flake.nix reads it; the binary embeds it via
# build.rs); Cargo.toml's version is inert at runtime but synced here so
# the two never diverge. Usage: just bump-version 0.1.1
[group("maintenance")]
bump-version new_version:
  sed -E -i 's/^(export PA6E_VERSION)=.*/\1={{new_version}}/' version.env
  sed -E -i 's/^(version) = ".*"/\1 = "{{new_version}}"/' rs/Cargo.toml

# Tag a release. The version comes from version.env (the single source of
# truth), so pass only the message. pa6e's nix package lives at repo root
# (source in rs/ is just layout), so tags use the plain v prefix per
# eng-versioning(7). Usage: just tag "feat: public send API"
[group("maintenance")]
tag message:
  #!/usr/bin/env bash
  set -euo pipefail
  . version.env
  tag="v${PA6E_VERSION:?missing PA6E_VERSION in version.env}"
  git tag -s -m "{{message}}" "$tag"
  echo "Created tag: $tag"
  git push origin "$tag"
  echo "Pushed $tag"
  git tag -v "$tag"

# Cut a release: must be run on master. Generates the changelog BEFORE
# bumping (so the release-bump commit is not in its own changelog), bumps
# version.env + rs/Cargo.toml, commits, pushes master, signs+pushes the
# v<version> tag, then publishes a GitHub release. Usage: just release 0.1.1
[group("maintenance")]
release new_version:
  #!/usr/bin/env bash
  set -euo pipefail
  branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$branch" != "master" ]]; then
    echo "release only allowed from master (on '$branch')" >&2
    exit 1
  fi
  prev=$(git tag --sort=-v:refname -l "v*" | head -1)
  header="release v{{new_version}}"
  if [[ -n "$prev" ]]; then
    summary=$(git log --format='- %s' "$prev"..HEAD)
    msg="$header"$'\n\n'"$summary"
  else
    msg="$header"
  fi
  just bump-version "{{new_version}}"
  git add version.env rs/Cargo.toml
  git commit -m "$header"
  git push origin "$branch"
  just tag "$msg"
  gh release create "v{{new_version}}" --title "$header" --notes "$msg"

# --- debug ---

# Build the binary and print its version subcommand. Verifies build.rs
# env injection (version + pinned component table).
[group("debug")]
debug-version:
  #!/usr/bin/env bash
  set -euo pipefail
  just build >/dev/null
  {{justfile_directory()}}/result/bin/pa6e version

# Render a markdown file through the full pipeline without printing.
[group("debug")]
debug-render target='label.md':
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
