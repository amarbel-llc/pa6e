#! /usr/bin/env -S bash -ex

nix run . label.md
# pa6e -p A6p -m "$peri_secondary" -i "label.md-trimmed.html.pdf.png" -c 2
