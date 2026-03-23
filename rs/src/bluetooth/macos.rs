use anyhow::{bail, Context, Result};
use objc2::rc::Retained;
use objc2_io_bluetooth::{BluetoothDeviceAddress, IOBluetoothDevice, IOBluetoothRFCOMMChannel};
use std::fmt;

const RFCOMM_CHANNEL: u8 = 1;

#[derive(Clone)]
pub struct BtAddress {
    raw: BluetoothDeviceAddress,
    display: String,
}

impl fmt::Display for BtAddress {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.display)
    }
}

pub fn parse_address(s: &str) -> Result<BtAddress> {
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        bail!("invalid MAC address: expected 6 colon-separated hex bytes, got '{s}'");
    }

    let mut data = [0u8; 6];
    for (i, part) in parts.iter().enumerate() {
        data[i] = u8::from_str_radix(part, 16)
            .with_context(|| format!("invalid hex byte '{part}' in MAC address '{s}'"))?;
    }

    Ok(BtAddress {
        raw: BluetoothDeviceAddress { data },
        display: s.to_uppercase(),
    })
}

pub struct MacosRfcommStream {
    channel: Retained<IOBluetoothRFCOMMChannel>,
    #[allow(dead_code)]
    device: Retained<IOBluetoothDevice>,
}

impl super::RfcommStream for MacosRfcommStream {
    async fn write_all(&mut self, data: &[u8]) -> Result<()> {
        // IOBluetooth writeSync is blocking, so run it on a blocking thread
        // to avoid stalling the tokio runtime.
        let channel_ptr = Retained::as_ptr(&self.channel) as usize;
        let data = data.to_vec();

        tokio::task::spawn_blocking(move || {
            // SAFETY: The channel pointer is valid for the lifetime of the
            // MacosRfcommStream which we hold a &mut to. The spawn_blocking
            // task completes before the future resolves, so the channel
            // cannot be dropped while this runs.
            let channel = unsafe { &*(channel_ptr as *const IOBluetoothRFCOMMChannel) };
            let result = unsafe {
                channel.writeSync_length(data.as_ptr() as *mut _, data.len() as u16)
            };
            if result != 0 {
                bail!("RFCOMM writeSync failed with IOReturn {result}");
            }
            Ok(())
        })
        .await
        .context("blocking write task panicked")?
    }
}

pub async fn connect(address: &BtAddress) -> Result<MacosRfcommStream> {
    let addr = address.clone();

    // IOBluetooth APIs must run on the main thread / have a run loop,
    // so use spawn_blocking to avoid tokio worker thread issues.
    tokio::task::spawn_blocking(move || {
        let device = unsafe { IOBluetoothDevice::deviceWithAddress(&addr.raw as *const _) }
            .context("failed to create IOBluetoothDevice for address")?;

        let mut channel: Option<Retained<IOBluetoothRFCOMMChannel>> = None;
        let result = unsafe {
            device.openRFCOMMChannelSync_withChannelID_delegate(
                Some(&mut channel),
                RFCOMM_CHANNEL,
                None,
            )
        };

        if result != 0 {
            bail!(
                "failed to open RFCOMM channel {RFCOMM_CHANNEL} to {}: IOReturn {result}",
                addr
            );
        }

        let channel = channel.context("openRFCOMMChannelSync returned success but channel is None")?;

        Ok(MacosRfcommStream { channel, device })
    })
    .await
    .context("blocking connect task panicked")?
}

// SAFETY: IOBluetoothRFCOMMChannel and IOBluetoothDevice are Objective-C
// objects managed by the IOBluetooth framework. We guard all access behind
// spawn_blocking and hold Retained references to prevent premature dealloc.
unsafe impl Send for MacosRfcommStream {}
