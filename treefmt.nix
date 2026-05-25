# treefmt-nix configuration. Run via `nix fmt` or `just fmt`.
{ lib, ... }:
{
  projectRootFile = "flake.nix";

  programs.rustfmt.enable = true;

  programs.nixfmt.enable = true;

  programs.shfmt.enable = true;
  settings.formatter.shfmt.includes = [
    "*.sh"
    "*.bash"
    "*.bats"
  ];
  # treefmt-nix's shfmt module exposes `indent_size` and `simplify` but
  # not `--case-indent` (-ci). Override the full options list to keep
  # those flags AND add -ci so `case` branches stay indented one level
  # past the `case` keyword (matches the eng-wide convention).
  settings.formatter.shfmt.options = lib.mkForce [
    "-i"
    "2"
    "-s"
    "-ci"
  ];

  settings.global.excludes = [
    "flake.lock"
    "Cargo.lock"
    "LICENSE"
    "sweatfile"
    "*.md"
    "*.css"
    "result"
    ".tmp/**"
    "tmp/**"
    "*.html"
    "*.pdf"
    "*.png"
  ];
}
