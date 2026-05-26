{
  description = "Toolset for printing to Peripage A6 thermal printers via Bluetooth.";

  inputs = {
    nixpkgs = {
      url = "github:amarbel-llc/nixpkgs";
      inputs.nixpkgs-master.follows = "nixpkgs-master";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
    # nixpkgs-master is the SHA-pinned upstream anchor that eng's
    # update-nix-repos recipe cascades. Without this input the cascade
    # falls through to `nix flake update` on the floating `nixpkgs`
    # ref and churns flake.lock every run.
    nixpkgs-master.url = "github:NixOS/nixpkgs/d233902339c02a9c334e7e593de68855ad26c4cb";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";

    # `nix fmt` driver. Config lives in ./treefmt.nix.
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pinned past amarbel-llc/tap@e4f75a7c so chrest's transitive tap
    # (still at 527bce2 in chrest's lock) collapses onto this fixed
    # node and Determinate Nix 3.20 stops choking on bats.nix's POSIX
    # bracket regex on darwin. Mirrors amarbel-llc/eng@0fe43804.
    tap = {
      url = "github:amarbel-llc/tap";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-master.follows = "nixpkgs-master";
      inputs.utils.follows = "utils";
    };

    chrest = {
      url = "github:amarbel-llc/chrest";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
      inputs.tap.follows = "tap";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      chrest,
      treefmt-nix,
      ...
    }:
    utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
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

          # `nix fmt` entry point. Config lives in ./treefmt.nix.
          treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

          css = pkgs.runCommand "pa6e-css" { } ''
            mkdir -p $out/share/pa6e
            cp ${./peri-a6.css} $out/share/pa6e/peri-a6.css
          '';

          pa6e = pkgs.rustPlatform.buildRustPackage (
            {
              pname = "pa6e";
              version = "0.1.0";
              src = ./rs;
              cargoLock.lockFile = ./rs/Cargo.lock;
              nativeBuildInputs = with pkgs; [ pkg-config ];
              PA6E_CSS_PATH = "${css}/share/pa6e/peri-a6.css";
            }
            // pkgs.lib.optionalAttrs isLinux {
              buildInputs = with pkgs; [ dbus ];
            }
            // pkgs.lib.optionalAttrs isDarwin {
              buildInputs = [ pkgs.apple-sdk_15 ];
            }
          );

          pa6e-wrapped = pkgs.symlinkJoin {
            name = "pa6e";
            paths = [ pa6e ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/pa6e --prefix PATH : ${
                pkgs.lib.makeBinPath [
                  chrest.packages.${system}.default
                  pkgs.pandoc
                  pkgs.imagemagick
                  pkgs.ghostscript_headless
                ]
              }
            '';
          };

          pa6e-manpages = pkgs.stdenvNoCC.mkDerivation {
            pname = "pa6e-manpages";
            version = "0.1.0";
            src = ./doc;
            nativeBuildInputs = [ pkgs.scdoc ];
            dontUnpack = true;
            dontBuild = true;
            installPhase = ''
              mkdir -p $out/share/man/man1
              for f in $src/*.1.scd; do
                scdoc < "$f" > "$out/share/man/man1/$(basename "$f" .scd)"
              done
            '';
          };

        in
        {
          packages = {
            inherit pa6e pa6e-wrapped pa6e-manpages;
            default = pa6e-wrapped;
          };

          formatter = treefmtEval.config.build.wrapper;

          # Sandboxed treefmt check for `just lint-fmt` and `nix flake
          # check`. Runs formatters over the source tree in a nix build
          # and exits non-zero on drift — no working-tree side effects,
          # unlike `nix fmt -- --ci`.
          checks.treefmt = treefmtEval.config.build.check self;

          devShells.default = pkgs.mkShell (
            {
              packages =
                (with pkgs; [
                  imagemagick
                  ghostscript_headless
                  pandoc
                  cargo
                  rustc
                  pkg-config
                ])
                ++ [
                  chrest.packages.${system}.default
                ]
                ++ pkgs.lib.optionals isLinux (
                  with pkgs;
                  [
                    bluez
                    dbus
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
