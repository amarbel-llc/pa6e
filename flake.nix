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

    # Incremental-artifact Rust builder. crane is library-only (its
    # own `inputs = {}`), so there is no nixpkgs follows to set — it
    # consumes whatever `pkgs` we hand `crane.mkLib`. Splitting the
    # build into a Cargo.lock-keyed `cargoArtifacts` derivation keeps
    # the `nix build` inner loop fast now that cargo is no longer in
    # the devShell (every build goes through nix).
    crane.url = "github:ipetkov/crane";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      chrest,
      treefmt-nix,
      crane,
      ...
    }:
    let
      # version.env at repo root is the single source of truth for the
      # release version. Read here via builtins.readFile, sed-rewritten
      # by `just bump-version`, and embedded into the binary through
      # build.rs (see rs/build.rs). Match captures everything after
      # `PA6E_VERSION=` up to the line break. Mirrors amarbel-llc/madder
      # and eng-versioning(7).
      pa6eVersion = builtins.head (
        builtins.match ".*PA6E_VERSION=([^\n]+).*" (builtins.readFile ./version.env)
      );
      # shortRev for clean builds, dirtyShortRev for dirty working trees
      # (so devshell/local builds read `dirty-abcdef` rather than
      # masquerading as a clean release), "unknown" as a last resort.
      pa6eCommit = self.shortRev or self.dirtyShortRev or "unknown";
    in
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

          craneLib = crane.mkLib pkgs;

          css = pkgs.runCommand "pa6e-css" { } ''
            mkdir -p $out/share/pa6e
            cp ${./peri-a6.css} $out/share/pa6e/peri-a6.css
          '';

          # Shared between the deps-only and crate builds (crane's
          # commonArgs idiom). Every env var here lands as a derivation
          # attribute, which build.rs reads via std::env::var and
          # re-emits as cargo:rustc-env so the binary embeds it. The
          # PA6E_<TOOL>_VERSION/REV vars feed the hybrid `pa6e version`
          # component table (orchestrator form, eng-versioning(7)).
          commonArgs = {
            src = craneLib.cleanCargoSource ./rs;
            strictDeps = true;
            nativeBuildInputs = [ pkgs.pkg-config ];
            PA6E_CSS_PATH = "${css}/share/pa6e/peri-a6.css";
            PA6E_VERSION = pa6eVersion;
            PA6E_COMMIT = pa6eCommit;
            PA6E_CHREST_VERSION = chrest.packages.${system}.default.version or "unknown";
            PA6E_CHREST_REV = chrest.shortRev or "unknown";
            PA6E_PANDOC_VERSION = pkgs.pandoc.version;
            PA6E_IMAGEMAGICK_VERSION = pkgs.imagemagick.version;
            PA6E_GHOSTSCRIPT_VERSION = pkgs.ghostscript_headless.version;
          }
          // pkgs.lib.optionalAttrs isLinux {
            buildInputs = [ pkgs.dbus ];
          }
          // pkgs.lib.optionalAttrs isDarwin {
            buildInputs = [ pkgs.apple-sdk_15 ];
          };

          # Dependency-only build, cached on Cargo.lock. Source edits
          # to pa6e's own crate do not invalidate this, so they only
          # recompile pa6e's handful of files.
          cargoArtifacts = craneLib.buildDepsOnly commonArgs;

          pa6e = craneLib.buildPackage (
            commonArgs
            // {
              inherit cargoArtifacts;
              version = pa6eVersion;
              # Tests run through the dedicated `checks.tests` lane so a
              # plain `nix build` stays fast; doCheck here would couple
              # the binary build to the test run.
              doCheck = false;
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
            version = pa6eVersion;
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

          checks = {
            # Sandboxed treefmt check for `just lint-fmt` and `nix flake
            # check`. Runs formatters over the source tree in a nix build
            # and exits non-zero on drift — no working-tree side effects,
            # unlike `nix fmt -- --ci`.
            treefmt = treefmtEval.config.build.check self;

            # `cargo test` through nix (`just test`). Reuses the cached
            # cargoArtifacts so it only compiles pa6e's own crate. No
            # `#[test]` functions exist yet, so this is a near-noop
            # today — it establishes the nix-routed test lane.
            tests = craneLib.cargoTest (commonArgs // { inherit cargoArtifacts; });
          };

          # Run/iterate shell: cargo/rustc/pkg-config are intentionally
          # absent — all builds go through `nix build`. This carries the
          # pipeline runtime tools (for `just render` and manual print
          # testing) plus, on Linux, what's needed to RUN the wrapped
          # binary against a real printer.
          devShells.default = pkgs.mkShell (
            {
              packages =
                (with pkgs; [
                  imagemagick
                  ghostscript_headless
                  pandoc
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
                );
            }
            // pkgs.lib.optionalAttrs isLinux {
              LD_LIBRARY_PATH = [ "${pkgs.bluez.out}/lib" ];
            }
          );
        }
      );
}
