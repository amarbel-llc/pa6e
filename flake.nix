{
  description = "a bash script that takes an HTML file and uses Chromium to
  render it as a PDF. Chromium is not from nix right now because of Darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/fea3b367d61c1a6592bc47c72f40a9f3e6a53e96";
    nixpkgs-master.url = "github:NixOS/nixpkgs/c7673e9a9a58dde446a5fe1d089d6cc12aa41238";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";

    chromium-html-to-pdf.url = "github:friedenberg/chromium-html-to-pdf";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
      chromium-html-to-pdf,
    }:
    utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        name = "pa6e-markdown-to-html";
        buildInputs = with pkgs; [
          bluez
          imagemagick
          pandoc
          chromium-html-to-pdf.packages.${system}.html-to-pdf
        ];
        pa6e-markdown-to-html =
          (pkgs.writeScriptBin name (builtins.readFile ./markdown-to-html.bash)).overrideAttrs
            (old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });

        pa6e = pkgs.rustPlatform.buildRustPackage {
          pname = "pa6e";
          version = "0.1.0";
          src = ./rs;
          cargoLock.lockFile = ./rs/Cargo.lock;
          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [ dbus ];
        };

        # to include all the templates and styles
        src = ./.;

      in
      rec {
        packages.pa6e-markdown-to-html = pkgs.symlinkJoin {
          name = name;
          paths = [
            pa6e-markdown-to-html
            src
          ]
          ++ buildInputs;
          buildInputs = [ pkgs.makeWrapper ];
          postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
        };

        packages.pa6e = pa6e;

        defaultPackage = packages.pa6e-markdown-to-html;

        devShells.default = pkgs.mkShell {
          packages = (
            with pkgs;
            [
              bluez
              imagemagick
              pandoc
              cargo
              rustc
              pkg-config
              dbus
              chromium-html-to-pdf.packages.${system}.html-to-pdf
            ]
          );

          LD_LIBRARY_PATH = [ "${pkgs.bluez.out}/lib" ];

          inputsFrom = [ ];
        };
      }
    );
}
