// Forward build-time env vars (set by the nix derivation, see flake.nix
// commonArgs) into the compiled binary as rustc-env values, so they are
// readable via env!/option_env! at runtime. PA6E_CSS_PATH locates the
// bundled stylesheet; the rest feed the `pa6e version` subcommand.
fn main() {
    let vars = [
        "PA6E_CSS_PATH",
        "PA6E_VERSION",
        "PA6E_COMMIT",
        "PA6E_CHREST_VERSION",
        "PA6E_CHREST_REV",
        "PA6E_PANDOC_VERSION",
        "PA6E_IMAGEMAGICK_VERSION",
        "PA6E_GHOSTSCRIPT_VERSION",
    ];
    for var in vars {
        println!("cargo:rerun-if-env-changed={var}");
        if let Ok(value) = std::env::var(var) {
            println!("cargo:rustc-env={var}={value}");
        }
    }
}
