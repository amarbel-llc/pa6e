{
  description = "Toolset for printing to Peripage A6 thermal printers via
  Bluetooth. Chromium must be on PATH at runtime (not packaged).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/fea3b367d61c1a6592bc47c72f40a9f3e6a53e96";
    nixpkgs-master.url = "github:NixOS/nixpkgs/c7673e9a9a58dde446a5fe1d089d6cc12aa41238";
    utils.url = "https://flakehub.com/f/numtide/flake-utils/0.1.102";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-master,
      utils,
    }:
    utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        name = "pa6e-markdown-to-html";
        html-to-pdf =
          (pkgs.writeScriptBin "html-to-pdf" (builtins.readFile ./html-to-pdf.bash)).overrideAttrs
            (old: {
              buildCommand = "${old.buildCommand}\n patchShebangs $out";
            });
        buildInputs = with pkgs; [
          imagemagick
          pandoc
          httpie
          websocat
          jq
          html-to-pdf
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

        src = pkgs.runCommand "pa6e-assets" { } ''
          mkdir -p $out
          cp ${./peri-a6.css} $out/peri-a6.css
        '';

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
              httpie
              websocat
              jq
              cargo
              rustc
              pkg-config
              dbus
            ]
          );

          LD_LIBRARY_PATH = [ "${pkgs.bluez.out}/lib" ];

          inputsFrom = [ ];
        };
      }
    );
}
