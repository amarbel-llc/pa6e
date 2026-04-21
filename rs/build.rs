fn main() {
    println!("cargo:rerun-if-env-changed=PA6E_CSS_PATH");
    if let Ok(path) = std::env::var("PA6E_CSS_PATH") {
        println!("cargo:rustc-env=PA6E_CSS_PATH={path}");
    }
}
