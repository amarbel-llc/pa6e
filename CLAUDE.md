# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

pa6e is a toolset for printing to Peripage A6 thermal printers via Bluetooth. It
converts markdown to HTML, renders to PDF, rasterizes to PNG, and sends to the
printer. The printer uses Bluetooth Serial Port Profile (BTSPP/RFCOMM), not
ESC/POS.

## Architecture

Single Rust binary (`pa6e`) with two subcommands:

**`pa6e print`** --- full markdown-to-image pipeline (and optional printing):

1.  pandoc: markdown -> standalone HTML (embeds `peri-a6.css` via `@media print`)
2.  chrest: HTML -> PDF (Firefox headless, 57mm/2.2409in paper width, zero side
    margins)
3.  imagemagick: PDF -> PNG at printer-native resolution, then trim whitespace
    via North-gravity splice+chop
4.  Outputs `<input>-trimmed.png`
5.  If `--mac` is provided, sends the image to the printer via Bluetooth

**`pa6e send`** --- sends a pre-rendered PNG image to the printer over Bluetooth.
Resizes to printer width (384px A6 / 576px A6+), converts to 1-bit monochrome,
transmits as packed row data via RFCOMM.

**CSS resolution:** `--css` flag > `PA6E_CSS_PATH` (burned in at build time by
nix) > `./peri-a6.css` in the working directory.

**Supporting files:**

- `peri-a6.css` --- Print stylesheet (Azuro TF font, `@media print` only)
- `label.md` --- Source content for labels

## Build & Run

Supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. Uses nix flakes +
direnv. The dev shell provides: `bluez` (Linux), `imagemagick`, `pandoc`,
`chrest`, `cargo`, `rustc`, `pkg-config`, `dbus` (Linux).

``` bash
direnv allow                      # enter dev environment

# Build
cd rs && cargo build              # build pa6e binary
cd rs && cargo test               # run tests
nix build                         # build wrapped binary via nix

# Run
nix run . -- print label.md                        # generate image only
nix run . -- print label.md -m AA:BB:CC:DD:EE:FF   # generate + print
nix run . -- send -m AA:BB:CC:DD:EE:FF -i img.png  # send pre-rendered image
```

## Justfile Commands

``` bash
just secret-edit    # Reveal, edit, and re-hide .env secrets (git-secret)
```

## Design Constraints

- chrest (Firefox headless) handles HTML-to-PDF rendering via
  `chrest capture --format pdf` with `--paper-width 2.2409` and zero side margins
- Future: chrest `--viewport-width` (chrest#42) will allow direct HTML-to-PNG,
  eliminating imagemagick and ghostscript from the pipeline

## Key Details

- Printer MAC addresses exported in `.envrc` (`peri_primary`, `peri_secondary`)
- Secrets managed with `git-secret`; `.env` must be revealed for deployments
- The nix flake wraps `pa6e` binary via `symlinkJoin` + `wrapProgram` so runtime
  dependencies (chrest, pandoc, imagemagick, ghostscript) are on PATH
- `PA6E_CSS_PATH` is set at build time by nix, pointing to `peri-a6.css` in the
  nix store; overridable with `--css` at runtime
- Printer native X resolution: 384 pixels (A6) / 576 pixels (A6+)
- `rs/` requires `dbus` and `pkg-config` as native build inputs on Linux (for
  bluer/bluez bindings)
