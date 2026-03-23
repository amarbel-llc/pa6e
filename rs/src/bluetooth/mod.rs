#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "macos")]
mod macos;

use anyhow::Result;

#[cfg(target_os = "linux")]
pub use linux::BtAddress;
#[cfg(target_os = "macos")]
pub use macos::BtAddress;

/// A Bluetooth RFCOMM connection that supports writing data.
pub trait RfcommStream {
    /// Write all bytes to the RFCOMM channel.
    fn write_all(&mut self, data: &[u8]) -> Result<()>;
}

/// Connect to a Bluetooth device over RFCOMM channel 1.
pub fn connect(address: &BtAddress) -> Result<impl RfcommStream> {
    #[cfg(target_os = "linux")]
    {
        linux::connect(address)
    }
    #[cfg(target_os = "macos")]
    {
        macos::connect(address)
    }
}

/// Parse a MAC address string (e.g. "AA:BB:CC:DD:EE:FF") into a BtAddress.
pub fn parse_address(s: &str) -> Result<BtAddress> {
    #[cfg(target_os = "linux")]
    {
        linux::parse_address(s)
    }
    #[cfg(target_os = "macos")]
    {
        macos::parse_address(s)
    }
}
