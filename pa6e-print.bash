#!/usr/bin/env bash
set -euo pipefail

script_dir="$(realpath "$(dirname "$0")")"

# In nix store: bin/pa6e-print sits next to peri-a6.css at ../
# Locally: script sits in the repo root next to peri-a6.css
if [[ -f "$script_dir/../peri-a6.css" ]]; then
  css_dir="$(realpath "$script_dir/..")"
elif [[ -f "$script_dir/peri-a6.css" ]]; then
  css_dir="$script_dir"
else
  echo "error: cannot find peri-a6.css" >&2
  exit 1
fi

if [[ -z ${peri_primary:-} && -f "$css_dir/.env" ]]; then
  source "$css_dir/.env"
fi

target="$1"
mac="${2:-${peri_primary:-}}"
model="${3:-A6p}"
concentration="${4:-2}"

# Derive printer width from model
model_lower="$(echo "$model" | tr '[:upper:]' '[:lower:]')"
case "$model_lower" in
a6) width_px=384 ;;
a6p | a6+) width_px=576 ;;
*)
  echo "error: unknown model $model (expected A6 or A6p)" >&2
  exit 1
  ;;
esac

paper_width_in="2.2409"

echo "converting markdown to HTML..." >&2
pandoc \
  --output "$target.html" \
  --standalone \
  --embed-resources \
  --css "$css_dir/peri-a6.css" \
  "$target" 2>/dev/null

echo "rendering HTML to PDF..." >&2
html-to-pdf "$target.html"

echo "rasterizing PDF to PNG..." >&2
render_dpi=$(echo "$width_px $paper_width_in" | awk '{printf "%d", ($1 / $2) * 2}')
magick -density "$render_dpi" "$target.html.pdf" \
  -background white -flatten -resize "${width_px}" "$target.html.pdf.png"

magick "$target.html.pdf.png" -gravity North \
  -background white -splice 0x1 \
  -background black -splice 0x1 \
  -trim +repage -chop 0x1 \
  "$target-trimmed.png"

echo "$target-trimmed.png"

if [[ -n $mac ]]; then
  echo "printing to $mac ($model)..." >&2
  pa6e -p "$model" -m "$mac" -i "$target-trimmed.png" -c "$concentration"
  echo "done" >&2
fi
