
build: build-cargo build-nix

build-cargo:
  cd rs && cargo build

build-nix:
  nix build --show-trace

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
