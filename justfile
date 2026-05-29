
default: lint build test

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

# Canonical build. cargo is intentionally absent from the devShell, so
# every build goes through nix (crane). For a fast compile-only check
# while iterating, re-run this — crane caches dependency compilation in
# the Cargo.lock-keyed cargoArtifacts derivation, so only pa6e's own
# crate recompiles.
[group('build')]
build:
  nix build --show-trace

# --- post-build ---

# Run the test suite through nix (crane cargoTest, reusing the cached
# cargoArtifacts). Mirror of the `checks.tests` flake output.
[group('post-build')]
test:
  #!/usr/bin/env bash
  set -euo pipefail
  system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
  nix build --print-build-logs --no-link ".#checks.${system}.tests"

# --- codemod ---

# Format all source files via treefmt-nix (rustfmt for Rust, nixfmt
# for Nix, shfmt for shell/bats). Config lives in ./treefmt.nix;
# `nix fmt` runs the same wrapper.
[group('codemod')]
fmt:
  nix fmt

# --- maint ---

# Sed-rewrite PA6E_VERSION in version.env to the given semver.
# version.env is the single source of truth for the release version;
# flake.nix reads it via builtins.readFile and the binary picks it up
# via build.rs env injection (see rs/build.rs). The `export ` prefix is
# tolerated and preserved. No-op if already at the target.
# Usage: just bump-version 0.1.1
[group('maint')]
bump-version new_version:
  #!/usr/bin/env bash
  set -euo pipefail
  current=$(grep -E '^(export )?PA6E_VERSION=' version.env | cut -d= -f2)
  if [[ "$current" == "{{new_version}}" ]]; then
    echo "already at {{new_version}}"
    exit 0
  fi
  sed -i.bak -E 's/^((export )?PA6E_VERSION=).*/\1{{new_version}}/' version.env && rm version.env.bak
  echo "bumped PA6E_VERSION: $current -> {{new_version}}"

# Tag a release. The "v" prefix is added for you, so pass the semver
# without it. pa6e's nix package lives at repo root (source in rs/ is
# just layout), so tags use the plain v prefix per eng-versioning(7) —
# not madder's go/v module-proxy form. Usage: just tag 0.1.1 "feat: ..."
[group('maint')]
tag version message:
  #!/usr/bin/env bash
  set -euo pipefail
  tag="v{{version}}"
  prev=$(git tag --sort=-v:refname -l "v*" | head -1)
  if [[ -n "$prev" ]]; then
    echo "Previous: $prev"
    git log --oneline "$prev"..HEAD
  fi
  git tag -s -m "{{message}}" "$tag"
  echo "Created tag: $tag"
  git push origin "$tag"
  echo "Pushed $tag"
  git tag -v "$tag"

# Cut a release: must be run on master. Bumps PA6E_VERSION in
# version.env, commits the bump with a changelog-style message built
# from commits since the last v* tag, pushes master, then signs and
# pushes the v{{version}} tag. The "v" prefix is added for you, so pass
# the semver without it. Usage: just release 0.1.1
#
# The tag-step is inlined here (rather than delegating to `tag`) because
# passing a multi-line message across `just` recipe boundaries is
# unreliable. The standalone `tag` recipe stays for callers who want to
# control the message without bumping.
[group('maint')]
release version:
  #!/usr/bin/env bash
  set -euo pipefail
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$current_branch" != "master" ]]; then
    echo "just release must be run on master (currently on $current_branch)" >&2
    exit 1
  fi
  prev=$(git tag --sort=-v:refname -l "v*" | head -1)
  header="release v{{version}}"
  if [[ -n "$prev" ]]; then
    summary=$(git log --format='- %s' "$prev"..HEAD)
    if [[ -n "$summary" ]]; then
      msg="$header"$'\n\n'"$summary"
    else
      msg="$header"
    fi
  else
    msg="$header"
  fi
  just bump-version "{{version}}"
  if ! git diff --quiet version.env; then
    git add version.env
    git commit -m "chore: release v{{version}}"
    git push origin master
    echo "pushed version.env bump to master"
  fi
  tag="v{{version}}"
  git tag -s -m "$msg" "$tag"
  echo "Created tag: $tag"
  git push origin "$tag"
  echo "Pushed $tag"

# --- debug ---

# Print the version subcommand output from the nix-built binary. Used
# to verify build.rs env injection (version + pinned component table).
[group('debug')]
debug-version:
  #!/usr/bin/env bash
  set -euo pipefail
  just build >/dev/null
  {{justfile_directory()}}/result/bin/pa6e version

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
