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

**Stage 1 --- Image generation** (`markdown-to-html.bash`, wrapped as
`pa6e-markdown-to-html` by the nix flake):

1.  pandoc: markdown → standalone HTML (embeds `peri-a6.css` which only applies
    via `@media print`)
2.  html-to-pdf: HTML → PDF (chromium headless, 57mm/2.2409in paper width, zero
    side margins)
3.  imagemagick: PDF → PNG at 300dpi, then trim whitespace via North-gravity
    splice+chop trick
4.  Outputs `<input>-trimmed.html.pdf.png`

**Stage 2 --- Printing** (`print_label.bash`):

- Runs `nix run . label.md`, moves output to `old/`, invokes the Rust `pa6e`
  binary
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
- `old/` --- Working directory used by `print_label.bash`

## Build & Run

Linux only (`x86_64-linux`, `aarch64-linux`). Uses nix flakes + direnv. The dev
shell provides: `bluez`, `imagemagick`, `pandoc`, `httpie`, `websocat`, `jq`,
`cargo`, `rustc`, `pkg-config`, `dbus`. **Chromium is not packaged** --- it must
be on PATH at runtime (e.g. system-installed `chromium` or
`google-chrome-stable`).

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

- Chromium headless is the only viable HTML-to-PDF renderer. Alternatives
  (weasyprint, wkhtmltopdf, prince, etc.) have inadequate CSS support and poor
  `@media print` handling compared to Chrome. Do not suggest replacing it.

## Key Details

- Printer MAC addresses exported in `.envrc` (`peri_primary`, `peri_secondary`)
- Secrets managed with `git-secret`; `.env` must be revealed for deployments
- The nix flake wraps `markdown-to-html.bash` via `writeScriptBin` +
  `symlinkJoin` + `wrapProgram` so all dependencies are on PATH
- `html-to-pdf` is an inlined bash script (`html-to-pdf.bash`) that launches
  Chromium headless, connects via WebSocket debugging protocol, and calls
  `Page.printToPDF`. Requires `chromium` on PATH (not packaged by the flake).
- Printer native X resolution is 384 pixels
- Two nix packages: `pa6e-markdown-to-html` (default, stage 1 bash pipeline) and
  `pa6e` (Rust printer CLI)
- `rs/` requires `dbus` and `pkg-config` as native build inputs (for bluer/bluez
  bindings)
