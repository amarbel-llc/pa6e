# pa6e

Toolset for printing to Peripage A6 thermal printers via Bluetooth.

Converts markdown to HTML, renders to PDF, rasterizes to PNG, and sends to the
printer over Bluetooth RFCOMM.

## Usage

``` bash
# Render markdown to a printer image
nix run . -- print label.md

# Render + print
nix run . -- print label.md -m MAC_ADDRESS

# Send a pre-rendered image
nix run . -- send -m MAC_ADDRESS -i image.png -p A6p -c 2

# Version + pinned component table
nix run . -- version
```

## Build

Supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. Uses nix flakes
+ direnv. **All builds go through nix** — `cargo` is intentionally not in the dev
shell; the Rust package is built with `crane`.

``` bash
direnv allow   # enter dev environment
just build     # nix build (wrapped binary via crane)
just test      # run tests through nix
just default   # validate + lint + build + test
```

## License

See [LICENSE](LICENSE).
