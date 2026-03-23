use anyhow::{Context, Result};
use bluer::rfcomm::{Socket, SocketAddr};
use bluer::Address;
use tokio::io::AsyncWriteExt;

const RFCOMM_CHANNEL: u8 = 1;

pub type BtAddress = Address;

pub struct BluerStream {
    inner: bluer::rfcomm::Stream,
}

impl super::RfcommStream for BluerStream {
    fn write_all(&mut self, data: &[u8]) -> Result<()> {
        tokio::runtime::Handle::current().block_on(async {
            self.inner.write_all(data).await?;
            Ok(())
        })
    }
}

pub fn parse_address(s: &str) -> Result<BtAddress> {
    s.parse()
        .map_err(|e| anyhow::anyhow!("invalid MAC address: {e}"))
}

pub fn connect(address: &BtAddress) -> Result<BluerStream> {
    let rt = tokio::runtime::Runtime::new().context("failed to create tokio runtime")?;
    rt.block_on(async {
        let socket = Socket::new()?;
        let addr = SocketAddr::new(*address, RFCOMM_CHANNEL);
        let stream = socket
            .connect(addr)
            .await
            .with_context(|| {
                format!("failed to connect to {address} on channel {RFCOMM_CHANNEL}")
            })?;
        Ok(BluerStream { inner: stream })
    })
}
