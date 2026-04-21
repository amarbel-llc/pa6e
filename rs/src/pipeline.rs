use anyhow::{bail, Context, Result};
use std::path::Path;
use std::process::Command;

const PAPER_WIDTH_IN: f64 = 2.2409;

pub fn markdown_to_html(input: &Path, css: &Path, output: &Path) -> Result<()> {
    let status = Command::new("pandoc")
        .arg("--output")
        .arg(output)
        .arg("--standalone")
        .arg("--embed-resources")
        .arg("--css")
        .arg(css)
        .arg(input)
        .status()
        .context("failed to run pandoc")?;
    if !status.success() {
        bail!("pandoc exited with {status}");
    }
    Ok(())
}

pub fn html_to_pdf(input: &Path, output: &Path) -> Result<()> {
    let canonical = input
        .canonicalize()
        .with_context(|| format!("cannot resolve {}", input.display()))?;
    let url = format!("file://{}", canonical.display());
    let status = Command::new("chrest")
        .args(["capture", "--format", "pdf", "--url", &url, "--output"])
        .arg(output)
        .args([
            "--no-headers",
            "--background",
            "--paper-width",
            &PAPER_WIDTH_IN.to_string(),
            "--margin-left",
            "0",
            "--margin-right",
            "0",
        ])
        .status()
        .context("failed to run chrest")?;
    if !status.success() {
        bail!("chrest exited with {status}");
    }
    Ok(())
}

pub fn pdf_to_png(input: &Path, output: &Path, width_px: u32) -> Result<()> {
    let dpi = (width_px as f64 / PAPER_WIDTH_IN * 2.0) as u32;
    let status = Command::new("magick")
        .arg("-density")
        .arg(dpi.to_string())
        .arg(input)
        .args(["-background", "white", "-flatten", "-resize"])
        .arg(width_px.to_string())
        .arg(output)
        .status()
        .context("failed to run magick")?;
    if !status.success() {
        bail!("magick (rasterize) exited with {status}");
    }
    Ok(())
}

pub fn trim_whitespace(input: &Path, output: &Path) -> Result<()> {
    let status = Command::new("magick")
        .arg(input)
        .args([
            "-gravity",
            "North",
            "-background",
            "white",
            "-splice",
            "0x1",
            "-background",
            "black",
            "-splice",
            "0x1",
            "-trim",
            "+repage",
            "-chop",
            "0x1",
        ])
        .arg(output)
        .status()
        .context("failed to run magick")?;
    if !status.success() {
        bail!("magick (trim) exited with {status}");
    }
    Ok(())
}
