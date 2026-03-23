# Unified Print Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Package a single `pa6e-print` script via the nix flake that takes a
markdown file and prints it to a Peripage thermal printer, working on both Linux
and Darwin.

**Architecture:** A new `pa6e-print.bash` script runs the full pipeline: pandoc
(md→HTML), html-to-pdf (HTML→PDF via Chrome DevTools Protocol),
imagemagick+ghostscript (PDF→PNG), and the `pa6e` Rust binary (PNG→printer). The
flake packages this script with all dependencies on PATH via `symlinkJoin` +
`wrapProgram`. On Darwin, `html-to-pdf` uses system Chrome; on Linux, nix
chromium. The existing `html-to-pdf-darwin.bash` is merged with the upstream
`html-to-pdf.bash` into a single cross-platform `html-to-pdf.bash`.

**Tech Stack:** Nix flakes, bash, pandoc, Chrome DevTools Protocol (httpie,
websocat, jq), imagemagick, ghostscript, Rust (pa6e binary)

**Rollback:** Delete `pa6e-print.bash` and `html-to-pdf.bash`, revert
`flake.nix` changes. The existing `markdown-to-html.bash`,
`html-to-pdf-darwin.bash`, and `print_label.bash` remain as-is until promotion.

--------------------------------------------------------------------------------

### Task 1: Create cross-platform `html-to-pdf.bash`

**Promotion criteria:** Replaces both upstream `chromium-html-to-pdf` dependency
(Linux) and `html-to-pdf-darwin.bash` (Darwin). Remove `chromium-html-to-pdf`
flake input and `html-to-pdf-darwin.bash` after this is verified on both
platforms.

**Files:** - Create: `html-to-pdf.bash`

**Step 1: Write `html-to-pdf.bash`**

This script auto-detects the Chrome binary: system Chrome on Darwin, `chromium`
on Linux (provided by nix). Interface matches the upstream `html-to-pdf.bash`:
`html-to-pdf <file.html> '<CDP options>'`.

``` bash
#!/usr/bin/env bash
set -euo pipefail

# Find Chrome/Chromium binary
if [[ "$(uname)" == "Darwin" ]]; then
  CMD_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
  CMD_CHROME="$(which chromium)"
fi

if [[ ! -x "$CMD_CHROME" ]]; then
  echo "error: Chrome/Chromium not found at $CMD_CHROME" >&2
  exit 1
fi

target="$1"
options="$2"
buffer_size="${3:-9999999}"
port="9222"

echo "Running Chrome ($CMD_CHROME)" >&2
coproc chrome (
  "$CMD_CHROME" \
    --no-sandbox \
    --headless \
    --remote-debugging-port=$port \
    --remote-allow-origins=http://127.0.0.1:$port \
    --remote-allow-origins=http://localhost:$port \
    "$(realpath "$target")" 2>&1
)

trap 'kill -9 $chrome_PID 2>/dev/null' EXIT
read -r output <&"${chrome[0]}"
echo "$output" >&2

get_websocket_debugger_url() {
  http GET localhost:$port/json/list |
    jq -r '.[] | select(.type == "page") | .webSocketDebuggerUrl'
}

echo "Getting chrome websocket debugger url" >&2
url="$(get_websocket_debugger_url)"

request_print_page() {
  echo "Page.printToPDF { $options }" |
    websocat --buffer-size "$buffer_size" -n1 --jsonrpc --jsonrpc-omit-jsonrpc "$url"
}

outfile="$target.pdf"

echo "Requesting chrome print page from debugger url ($url)" >&2
request_print_page |
  jq -r '.result.data' |
  base64 -d -i - >"$outfile"

echo "Wrote PDF to '$outfile'" >&2
```

**Step 2: Verify on Darwin**

Run:
`bash html-to-pdf.bash /tmp/checklist-test3.html '"paperWidth": 2.2409, "marginLeft": 0, "marginRight": 0'`
Expected: PDF written to `/tmp/checklist-test3.html.pdf`

**Step 3: Commit**

    git add html-to-pdf.bash
    git commit -m "Add cross-platform html-to-pdf using system Chrome on Darwin"

--------------------------------------------------------------------------------

### Task 2: Create `pa6e-print.bash` unified pipeline script

**Promotion criteria:** Replaces `markdown-to-html.bash` + `print_label.bash`.
Remove those files after verified on both platforms.

**Files:** - Create: `pa6e-print.bash`

**Step 1: Write `pa6e-print.bash`**

Usage: `pa6e-print <file.md> <mac-address> [printer-model] [concentration]`

The script references `peri-a6.css` relative to its own nix store path (same
pattern as `markdown-to-html.bash`). All tools (pandoc, html-to-pdf, magick, gs,
pa6e) are expected on PATH via nix wrapping.

``` bash
#!/usr/bin/env bash
set -euo pipefail

dir_nix_store="$(realpath "$(dirname "$0")/../")"

target="$1"
mac="$2"
model="${3:-A6}"
concentration="${4:-2}"

# Derive printer width from model
case "${model,,}" in
  a6)  width_px=384 ;;
  a6p|a6+) width_px=576 ;;
  *) echo "error: unknown model $model (expected A6 or A6p)" >&2; exit 1 ;;
esac

paper_width_in="2.2409"

echo "converting markdown to HTML..." >&2
pandoc \
  --output "$target.html" \
  --standalone \
  --embed-resources \
  --css "$dir_nix_store/peri-a6.css" \
  "$target" 2>/dev/null

echo "rendering HTML to PDF..." >&2
html-to-pdf "$target.html" \
  "\"paperWidth\": $paper_width_in, \"marginLeft\": 0, \"marginRight\": 0"

echo "rasterizing PDF to PNG..." >&2
render_dpi=$(echo "$width_px $paper_width_in" | awk '{printf "%d", ($1 / $2) * 2}')
magick -density "$render_dpi" "$target.html.pdf" \
  -background white -flatten -resize "${width_px}" "$target.html.pdf.png"

magick "$target.html.pdf.png" -gravity North \
  -background white -splice 0x1 \
  -background black -splice 0x1 \
  -trim +repage -chop 0x1 \
  "$target-trimmed.png"

echo "printing to $mac ($model)..." >&2
pa6e -p "$model" -m "$mac" -i "$target-trimmed.png" -c "$concentration"

echo "done" >&2
```

**Step 2: Verify the script runs manually on Darwin**

Requires all tools on PATH (from dev shell + system Chrome):

Run: `bash pa6e-print.bash /tmp/checklist-test.md 28:82:0B:04:01:70 A6p 2`
Expected: Prints the checklist to the printer

**Step 3: Commit**

    git add pa6e-print.bash
    git commit -m "Add pa6e-print unified markdown-to-printer script"

--------------------------------------------------------------------------------

### Task 3: Update `flake.nix` to package `pa6e-print`

**Promotion criteria:** `nix run .#pa6e-print -- file.md MAC` works on both
platforms. Remove `chromium-html-to-pdf` flake input after verified.

**Files:** - Modify: `flake.nix`

**Step 1: Update flake.nix**

Key changes: - Remove `chromium-html-to-pdf` flake input - Add
`ghostscript_headless` to build inputs - Add `httpie`, `websocat`, `jq` to build
inputs (needed by `html-to-pdf.bash`) - On Linux: add `chromium` to build
inputs - Create `html-to-pdf` package from local `html-to-pdf.bash` - Create
`pa6e-print` package that wraps `pa6e-print.bash` with all deps on PATH - Make
`pa6e-print` the default package on both platforms

``` nix
{
  description = "Peripage A6 thermal printer toolset: markdown to print";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };

          isLinux = pkgs.stdenv.hostPlatform.isLinux;
          isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

          pa6e = pkgs.rustPlatform.buildRustPackage (
            {
              pname = "pa6e";
              version = "0.1.0";
              src = ./rs;
              cargoLock.lockFile = ./rs/Cargo.lock;
              nativeBuildInputs = with pkgs; [ pkg-config ];
            }
            // pkgs.lib.optionalAttrs isLinux {
              buildInputs = with pkgs; [ dbus ];
            }
            // pkgs.lib.optionalAttrs isDarwin {
              buildInputs = [ pkgs.apple-sdk_15 ];
            }
          );

          html-to-pdf =
            (pkgs.writeScriptBin "html-to-pdf" (builtins.readFile ./html-to-pdf.bash)).overrideAttrs
              (old: {
                buildCommand = "${old.buildCommand}\n patchShebangs $out";
              });

          html-to-pdf-deps = with pkgs; [
            httpie
            jq
            websocat
          ] ++ pkgs.lib.optionals isLinux [
            chromium
          ];

          html-to-pdf-wrapped = pkgs.symlinkJoin {
            name = "html-to-pdf";
            paths = [ html-to-pdf ] ++ html-to-pdf-deps;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/html-to-pdf --prefix PATH : $out/bin";
          };

          print-deps = [
            pa6e
            html-to-pdf-wrapped
            pkgs.pandoc
            pkgs.imagemagick
            pkgs.ghostscript_headless
          ];

          pa6e-print-unwrapped =
            (pkgs.writeScriptBin "pa6e-print" (builtins.readFile ./pa6e-print.bash)).overrideAttrs
              (old: {
                buildCommand = "${old.buildCommand}\n patchShebangs $out";
              });

          pa6e-print = pkgs.symlinkJoin {
            name = "pa6e-print";
            paths = [
              pa6e-print-unwrapped
              ./.
            ] ++ print-deps;
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/pa6e-print --prefix PATH : $out/bin";
          };

        in
        {
          packages = {
            inherit pa6e pa6e-print;
            default = pa6e-print;
          };

          devShells.default = pkgs.mkShell (
            {
              packages =
                (with pkgs; [
                  imagemagick
                  ghostscript_headless
                  pandoc
                  httpie
                  jq
                  websocat
                  cargo
                  rustc
                  pkg-config
                ])
                ++ pkgs.lib.optionals isLinux (
                  with pkgs;
                  [
                    bluez
                    dbus
                    chromium
                  ]
                )
                ++ pkgs.lib.optionals isDarwin [
                  pkgs.apple-sdk_15
                ];
            }
            // pkgs.lib.optionalAttrs isLinux {
              LD_LIBRARY_PATH = [ "${pkgs.bluez.out}/lib" ];
            }
          );
        }
      );
}
```

**Step 2: Build the flake**

Run: `nix build .#pa6e-print` Expected: Builds successfully,
`result/bin/pa6e-print` exists with all deps on PATH

**Step 3: Test with `nix run`**

Run: `nix run .#pa6e-print -- /tmp/checklist-test.md 28:82:0B:04:01:70 A6p 2`
Expected: Full pipeline runs and prints

**Step 4: Commit**

    git add flake.nix
    git commit -m "Package pa6e-print with all deps, remove chromium-html-to-pdf input"

--------------------------------------------------------------------------------

### Task 4: Clean up replaced files

**Promotion criteria:** N/A

**Files:** - Delete: `html-to-pdf-darwin.bash` - Delete:
`markdown-to-html.bash` - Delete: `print_label.bash`

**Step 1: Verify pa6e-print works end-to-end**

Run: `nix run . -- /tmp/checklist-test.md 28:82:0B:04:01:70 A6p 2` Expected:
Prints successfully

**Step 2: Remove old files**

``` bash
git rm html-to-pdf-darwin.bash markdown-to-html.bash print_label.bash
```

**Step 3: Commit**

    git add -A
    git commit -m "Remove old pipeline scripts replaced by pa6e-print"
