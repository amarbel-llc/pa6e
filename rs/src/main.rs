mod bluetooth;
mod image_prep;
mod pipeline;
mod printer;

use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "pa6e", about = "Peripage A6 thermal printer toolset")]
struct Cli {
    #[command(subcommand)]
    command: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Send a pre-rendered image to the printer via Bluetooth
    Send(SendArgs),
    /// Convert markdown to a printer image and optionally print
    Print(PrintArgs),
}

#[derive(clap::Args)]
struct SendArgs {
    /// Printer Bluetooth MAC address (e.g. AA:BB:CC:DD:EE:FF)
    #[arg(short = 'm', long = "mac")]
    mac: String,

    /// Image file path
    #[arg(short = 'i', long = "image")]
    image: PathBuf,

    /// Printer model: A6 or A6p
    #[arg(short = 'p', long = "printer", default_value = "A6")]
    model: String,

    /// Concentration/heat level: 0, 1, or 2
    #[arg(short = 'c', long = "concentration", default_value_t = 1)]
    concentration: u8,

    /// Paper feed amount after printing (0-255)
    #[arg(short = 'f', long = "feed", default_value_t = 120)]
    feed: u8,
}

#[derive(clap::Args)]
struct PrintArgs {
    /// Markdown source file
    file: PathBuf,

    /// Printer Bluetooth MAC address (omit to only generate image)
    #[arg(short = 'm', long = "mac")]
    mac: Option<String>,

    /// Printer model: A6 or A6p
    #[arg(short = 'p', long = "printer", default_value = "A6p")]
    model: String,

    /// Concentration/heat level: 0, 1, or 2
    #[arg(short = 'c', long = "concentration", default_value_t = 2)]
    concentration: u8,

    /// Paper feed amount after printing (0-255)
    #[arg(short = 'f', long = "feed", default_value_t = 120)]
    feed: u8,

    /// Path to CSS stylesheet (overrides built-in path)
    #[arg(long = "css")]
    css: Option<PathBuf>,
}

fn resolve_model(model: &str) -> Result<(u32, u8)> {
    match model.to_lowercase().as_str() {
        "a6" => Ok((printer::A6_ROW_WIDTH, printer::A6_ROW_BYTES)),
        "a6p" | "a6+" => Ok((printer::A6P_ROW_WIDTH, printer::A6P_ROW_BYTES)),
        other => bail!("unknown printer model: {other} (expected A6 or A6p)"),
    }
}

fn send_image(
    mac: &str,
    image: &std::path::Path,
    row_width: u32,
    row_bytes: u8,
    concentration: u8,
    feed: u8,
) -> Result<()> {
    if concentration > 2 {
        bail!("concentration must be 0, 1, or 2");
    }

    let address = bluetooth::parse_address(mac)?;

    eprintln!("preparing image: {}", image.display());
    let (data, height) = image_prep::prepare(image, row_width)?;
    eprintln!("image: {row_width}x{height} pixels, {} bytes", data.len());

    eprintln!("connecting to {address}...");
    let mut stream = bluetooth::connect(&address)?;
    eprintln!("connected");

    printer::reset(&mut stream)?;
    printer::set_concentration(&mut stream, concentration)?;

    eprintln!("printing {height} rows...");
    printer::print_image(&mut stream, &data, row_bytes, height)?;

    std::thread::sleep(std::time::Duration::from_secs(2));
    printer::feed_and_end(&mut stream, feed)?;
    eprintln!("done");

    Ok(())
}

fn resolve_css(cli_override: Option<&PathBuf>) -> Result<PathBuf> {
    if let Some(p) = cli_override {
        return Ok(p.clone());
    }
    if let Some(p) = option_env!("PA6E_CSS_PATH") {
        let path = PathBuf::from(p);
        if path.exists() {
            return Ok(path);
        }
        eprintln!("warning: built-in CSS path not found: {p}");
    }
    let local = PathBuf::from("peri-a6.css");
    if local.exists() {
        return Ok(local);
    }
    bail!(
        "cannot find peri-a6.css (set --css, PA6E_CSS_PATH at build time, \
         or place peri-a6.css in the working directory)"
    );
}

fn cmd_print(args: PrintArgs) -> Result<()> {
    let (row_width, row_bytes) = resolve_model(&args.model)?;
    let css = resolve_css(args.css.as_ref())?;

    let tmp = tempfile::tempdir().context("failed to create temp directory")?;

    let html = tmp.path().join("output.html");
    let pdf = tmp.path().join("output.pdf");
    let png = tmp.path().join("output.png");
    let trimmed_tmp = tmp.path().join("trimmed.png");

    eprintln!("converting markdown to HTML...");
    pipeline::markdown_to_html(&args.file, &css, &html)?;

    eprintln!("rendering HTML to PDF...");
    pipeline::html_to_pdf(&html, &pdf)?;

    eprintln!("rasterizing PDF to PNG...");
    pipeline::pdf_to_png(&pdf, &png, row_width)?;

    pipeline::trim_whitespace(&png, &trimmed_tmp)?;

    let stem = args
        .file
        .file_name()
        .and_then(|n| n.to_str())
        .context("invalid input filename")?;
    let final_name = format!("{stem}-trimmed.png");
    let final_path = PathBuf::from(&final_name);
    std::fs::copy(&trimmed_tmp, &final_path)
        .with_context(|| format!("failed to copy output to {final_name}"))?;

    println!("{final_name}");

    if let Some(ref mac) = args.mac {
        send_image(
            mac,
            &final_path,
            row_width,
            row_bytes,
            args.concentration,
            args.feed,
        )?;
    }

    Ok(())
}

fn cmd_send(args: SendArgs) -> Result<()> {
    let (row_width, row_bytes) = resolve_model(&args.model)?;
    send_image(
        &args.mac,
        &args.image,
        row_width,
        row_bytes,
        args.concentration,
        args.feed,
    )
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Cmd::Send(args) => cmd_send(args),
        Cmd::Print(args) => cmd_print(args),
    }
}
