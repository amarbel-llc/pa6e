use anyhow::Result;
use std::thread;
use std::time::Duration;

use crate::bluetooth::RfcommStream;

const MAX_CHUNK_ROWS: u16 = 64;
const ROW_DELAY: Duration = Duration::from_millis(10);
const CHUNK_DELAY: Duration = Duration::from_millis(200);

pub const A6_ROW_WIDTH: u32 = 384;
pub const A6P_ROW_WIDTH: u32 = 576;

pub const A6_ROW_BYTES: u8 = 48;
pub const A6P_ROW_BYTES: u8 = 72;

pub fn reset(stream: &mut impl RfcommStream) -> Result<()> {
    let mut cmd = vec![0x10, 0xFF, 0xFE, 0x01];
    cmd.extend_from_slice(&[0u8; 12]);
    stream.write_all(&cmd)?;
    Ok(())
}

pub fn set_concentration(stream: &mut impl RfcommStream, level: u8) -> Result<()> {
    let cmd = [0x10, 0xFF, 0x10, 0x00, level];
    stream.write_all(&cmd)?;
    Ok(())
}

pub fn print_image(
    stream: &mut impl RfcommStream,
    data: &[u8],
    row_bytes: u8,
    height: u16,
) -> Result<()> {
    let rb = row_bytes as usize;
    let mut rows_sent: u16 = 0;

    while rows_sent < height {
        let remaining = height - rows_sent;
        let chunk_height = remaining.min(MAX_CHUNK_ROWS);

        reset(stream)?;

        let preamble = [
            0x1D,
            0x76,
            0x30,
            0x00,
            row_bytes,
            0x00,
            chunk_height as u8,
            0x00,
        ];
        stream.write_all(&preamble)?;

        for row in 0..chunk_height {
            let offset = (rows_sent + row) as usize * rb;
            let row_data = &data[offset..offset + rb];
            stream.write_all(row_data)?;
            thread::sleep(ROW_DELAY);
        }

        rows_sent += chunk_height;
        thread::sleep(CHUNK_DELAY);
    }

    Ok(())
}

pub fn feed_and_end(stream: &mut impl RfcommStream, feed_amount: u8) -> Result<()> {
    stream.write_all(&[0x1B, 0x4A, feed_amount])?;
    stream.write_all(&[0x10, 0xFF, 0xFE, 0x45])?;
    Ok(())
}
