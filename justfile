
build: build-cargo build-nix

build-cargo:
  cd rs && cargo build

build-nix:
  nix build --show-trace
