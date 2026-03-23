# pa6e

Toolset for printing to Peripage A6 thermal printers via Bluetooth.

Converts markdown to HTML, renders to PDF, rasterizes to PNG, and sends to the
printer over Bluetooth RFCOMM.

## Usage

``` bash
# Build image from markdown (stage 1)
nix run . label.md

# Build + print (stages 1+2)
./print_label.bash

# Rust CLI directly
pa6e -p A6p -m MAC_ADDRESS -i image.png -c 2
```

## Build

Linux only (`x86_64-linux`, `aarch64-linux`). Uses nix flakes + direnv.

``` bash
direnv allow          # enter dev environment
cd rs && cargo build  # build Rust CLI
cd rs && cargo test   # run tests
nix build .#pa6e      # build via nix
```

## License

See [LICENSE](LICENSE).
