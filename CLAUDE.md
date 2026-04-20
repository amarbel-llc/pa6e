# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project Overview

pa6e is a toolset for printing to Peripage A6 thermal printers via Bluetooth. It
converts markdown to HTML, renders to PDF, rasterizes to PNG, and sends to the
printer. The printer uses Bluetooth Serial Port Profile (BTSPP/RFCOMM), not
ESC/POS.

## Architecture

Two-stage pipeline: nix flake builds the image, then a separate script sends it
to the printer.

**Stage 1 --- Image generation** (`pa6e-print.bash`, wrapped as `pa6e-print` by
the nix flake):

1.  pandoc: markdown -> standalone HTML (embeds `peri-a6.css` which only applies
    via `@media print`)
2.  html-to-pdf: HTML -> PDF via chrest (Firefox headless, 57mm/2.2409in paper
    width, zero side margins)
3.  imagemagick: PDF -> PNG, then trim whitespace via North-gravity splice+chop
4.  Outputs `<input>-trimmed.png`

**Stage 2 --- Printing** (`print_label.bash`):

- Runs `nix run . label.md`, then invokes the Rust `pa6e` binary on the output
- Uses `peri_secondary` MAC address with concentration level 2

**Rust CLI** (`rs/` --- built as `pa6e` by the nix flake):

- Loads PNG, resizes to printer width (384px A6 / 576px A6+), converts to 1-bit
  monochrome
- Connects via Bluetooth RFCOMM (async, bluer/tokio), sends packed row data with
  10ms inter-row delay
- Usage: `pa6e -p A6p -m MAC_ADDRESS -i image.png -c 2` (concentration: 0/1/2)

**Supporting files:**

- `peri-a6.css` --- Print stylesheet (Azuro TF font, `@media print` only)
- `label.md` --- Source content for labels

## Build & Run

Supports `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin`. Uses nix flakes +
direnv. The dev shell provides: `bluez` (Linux), `imagemagick`, `pandoc`,
`chrest`, `cargo`, `rustc`, `pkg-config`, `dbus` (Linux).

``` bash
direnv allow                      # enter dev environment

nix run . label.md                # build image only (stage 1)
./print_label.bash                # build + print label (stages 1+2)

# Rust CLI (rs/)
cd rs && cargo build              # build pa6e binary
cd rs && cargo test               # run tests
nix build .#pa6e                  # build via nix
```

## Justfile Commands

``` bash
just secret-edit    # Reveal, edit, and re-hide .env secrets (git-secret)
```

## Design Constraints

- chrest (Firefox headless) handles HTML-to-PDF rendering. The `html-to-pdf.bash`
  wrapper calls `chrest capture --format pdf` with `--paper-width 2.2409` and
  zero side margins.

## Key Details

- Printer MAC addresses exported in `.envrc` (`peri_primary`, `peri_secondary`)
- Secrets managed with `git-secret`; `.env` must be revealed for deployments
- The nix flake wraps `pa6e-print.bash` via `writeScriptBin` + `symlinkJoin` +
  `wrapProgram` so all dependencies (including chrest) are on PATH
- `html-to-pdf` is a thin wrapper around `chrest capture --format pdf`
- Printer native X resolution is 384 pixels
- Two nix packages: `pa6e-print` (default, stage 1 bash pipeline) and `pa6e`
  (Rust printer CLI)
- `rs/` requires `dbus` and `pkg-config` as native build inputs (for bluer/bluez
  bindings)
