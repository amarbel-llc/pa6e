use anyhow::{bail, Context, Result};
use image::imageops::FilterType;
use image::GenericImageView;
use image::ImageReader;
use std::path::Path;

/// Loads a PNG, resizes to printer width, converts to 1-bit monochrome.
/// Returns (packed_bytes, height) where each row is `row_width / 8` bytes.
pub fn prepare(path: &Path, row_width: u32) -> Result<(Vec<u8>, u16)> {
    let img = ImageReader::open(path)
        .with_context(|| format!("failed to open image: {}", path.display()))?
        .decode()
        .with_context(|| format!("failed to decode image: {}", path.display()))?;

    let (orig_w, orig_h) = img.dimensions();
    let new_height = (orig_h as f64 * row_width as f64 / orig_w as f64).round() as u32;

    let resized = img.resize_exact(row_width, new_height, FilterType::Lanczos3);
    let gray = resized.to_luma8();

    let row_bytes = (row_width / 8) as usize;
    let mut packed = Vec::with_capacity(row_bytes * new_height as usize);

    for y in 0..new_height {
        for byte_idx in 0..row_bytes {
            let mut byte: u8 = 0;
            for bit in 0..8u32 {
                let x = byte_idx as u32 * 8 + bit;
                let pixel = gray.get_pixel(x, y).0[0];
                // Invert: white (255) → 0, black (0) → 1. Threshold at 128.
                if pixel < 128 {
                    byte |= 1 << (7 - bit);
                }
            }
            packed.push(byte);
        }
    }

    if new_height > u16::MAX as u32 {
        bail!(
            "resized image height {new_height} exceeds maximum {}",
            u16::MAX
        );
    }
    Ok((packed, new_height as u16))
}
