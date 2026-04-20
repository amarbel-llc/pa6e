#! /usr/bin/env -S bash -e

dir_nix_store="$(realpath "$(dirname "$0")/../")"

target="$1"
width_px="${2:-384}"

paper_width_in="2.2409"

pandoc \
  --output "$target.html" \
  --standalone \
  --embed-resources \
  --css "$dir_nix_store/peri-a6.css" \
  "$target" 2>/dev/null

html-to-pdf "$target.html"

render_dpi=$(echo "$width_px $paper_width_in" | awk '{printf "%d", ($1 / $2) * 2}')
magick -density "$render_dpi" "$target.html.pdf" -background white -flatten -resize "${width_px}" "$target.html.pdf.png"
magick "$target.html.pdf.png" -gravity North \
  -background white -splice 0x1 \
  -background black -splice 0x1 \
  -trim +repage -chop 0x1 \
  "$target-trimmed.html.pdf.png"

echo "$target-trimmed.html.pdf.png"
