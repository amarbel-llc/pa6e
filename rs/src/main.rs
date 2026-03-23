mod bluetooth;
mod image_prep;
mod printer;

use anyhow::{bail, Result};
use clap::Parser;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "pa6e-print", about = "Send images to Peripage A6 thermal printers")]
struct Cli {
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
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    if cli.concentration > 2 {
        bail!("concentration must be 0, 1, or 2");
    }

    let (row_width, row_bytes) = match cli.model.to_lowercase().as_str() {
        "a6" => (printer::A6_ROW_WIDTH, printer::A6_ROW_BYTES),
        "a6p" | "a6+" => (printer::A6P_ROW_WIDTH, printer::A6P_ROW_BYTES),
        other => bail!("unknown printer model: {other} (expected A6 or A6p)"),
    };

    let address = bluetooth::parse_address(&cli.mac)?;

    eprintln!("preparing image: {}", cli.image.display());
    let (data, height) = image_prep::prepare(&cli.image, row_width)?;
    eprintln!("image: {row_width}x{height} pixels, {} bytes", data.len());

    eprintln!("connecting to {address}...");
    let mut stream = bluetooth::connect(&address).await?;
    eprintln!("connected");

    printer::reset(&mut stream).await?;
    printer::set_concentration(&mut stream, cli.concentration).await?;

    eprintln!("printing {height} rows...");
    printer::print_image(&mut stream, &data, row_bytes, height).await?;

    printer::feed_and_end(&mut stream).await?;
    eprintln!("done");

    Ok(())
}
