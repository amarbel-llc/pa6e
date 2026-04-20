{
  description = "Toolset for printing to Peripage A6 thermal printers via Bluetooth.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/fea3b367d61c1a6592bc47c72f40a9f3e6a53e96";
    nixpkgs-master.url = "github:NixOS/nixpkgs/c7673e9a9a58dde446a5fe1d089d6cc12aa41238";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";

    chrest = {
      url = "github:amarbel-llc/chrest";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.utils.follows = "utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
      chrest,
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

          html-to-pdf-unwrapped =
            (pkgs.writeScriptBin "html-to-pdf" (builtins.readFile ./html-to-pdf.bash)).overrideAttrs
              (old: {
                buildCommand = "${old.buildCommand}\n patchShebangs $out";
              });

          html-to-pdf = pkgs.symlinkJoin {
            name = "html-to-pdf";
            paths = [
              html-to-pdf-unwrapped
              chrest.packages.${system}.default
            ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = "wrapProgram $out/bin/html-to-pdf --prefix PATH : $out/bin";
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

          print-deps = [
            pa6e
            html-to-pdf
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
              pa6e-manpages
              ./.
            ]
            ++ print-deps;
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
