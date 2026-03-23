use anyhow::{bail, Context, Result};
use core_foundation::runloop::{kCFRunLoopDefaultMode, CFRunLoopRunInMode};
use objc2::rc::Retained;
use objc2::runtime::AnyObject;
use objc2::{define_class, msg_send, AllocAnyThread, DefinedClass};
use objc2_foundation::{NSObject, NSString};
use objc2_io_bluetooth::{
    BluetoothRFCOMMChannelID, IOBluetoothDevice, IOBluetoothDeviceAsyncCallbacks,
    IOBluetoothRFCOMMChannel, IOBluetoothRFCOMMChannelDelegate, IOBluetoothSDPServiceRecord,
};
use std::cell::Cell;
use std::fmt;
use std::time::{Duration, Instant};
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const RUNLOOP_TICK: f64 = 0.1;

#[derive(Clone)]
pub struct BtAddress {
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

    for part in &parts {
        u8::from_str_radix(part, 16)
            .with_context(|| format!("invalid hex byte '{part}' in MAC address '{s}'"))?;
    }

    Ok(BtAddress {
        display: s.to_uppercase(),
    })
}

pub struct MacosRfcommStream {
    channel: Retained<IOBluetoothRFCOMMChannel>,
    #[allow(dead_code)]
    device: Retained<IOBluetoothDevice>,
}

impl super::RfcommStream for MacosRfcommStream {
    fn write_all(&mut self, data: &[u8]) -> Result<()> {
        let result = unsafe {
            self.channel
                .writeSync_length(data.as_ptr() as *mut _, data.len() as u16)
        };
        if result != 0 {
            bail!("RFCOMM writeSync failed with IOReturn {result}");
        }
        Ok(())
    }
}

/// Delegate that tracks completion of both baseband connection and RFCOMM
/// channel open. Both IOBluetooth operations deliver their callbacks via the
/// thread's CFRunLoop.
struct BluetoothDelegateIvars {
    conn_complete: Cell<bool>,
    conn_status: Cell<i32>,
    sdp_complete: Cell<bool>,
    sdp_status: Cell<i32>,
    rfcomm_complete: Cell<bool>,
    rfcomm_status: Cell<i32>,
}

define_class!(
    #[unsafe(super(NSObject))]
    #[name = "Pa6eBluetoothDelegate"]
    #[ivars = BluetoothDelegateIvars]
    struct BluetoothDelegate;

    unsafe impl IOBluetoothDeviceAsyncCallbacks for BluetoothDelegate {
        #[unsafe(method(remoteNameRequestComplete:status:))]
        unsafe fn remote_name_request_complete(
            &self,
            _device: Option<&IOBluetoothDevice>,
            _status: i32,
        ) {}

        #[unsafe(method(connectionComplete:status:))]
        unsafe fn connection_complete(
            &self,
            _device: Option<&IOBluetoothDevice>,
            status: i32,
        ) {
            self.ivars().conn_complete.set(true);
            self.ivars().conn_status.set(status);
        }

        #[unsafe(method(sdpQueryComplete:status:))]
        unsafe fn sdp_query_complete(
            &self,
            _device: Option<&IOBluetoothDevice>,
            status: i32,
        ) {
            self.ivars().sdp_complete.set(true);
            self.ivars().sdp_status.set(status);
        }
    }

    unsafe impl IOBluetoothRFCOMMChannelDelegate for BluetoothDelegate {
        #[unsafe(method(rfcommChannelOpenComplete:status:))]
        unsafe fn rfcomm_channel_open_complete(
            &self,
            _channel: Option<&IOBluetoothRFCOMMChannel>,
            error: i32,
        ) {
            self.ivars().rfcomm_complete.set(true);
            self.ivars().rfcomm_status.set(error);
        }
    }
);

impl BluetoothDelegate {
    fn new() -> Retained<Self> {
        let this = BluetoothDelegate::alloc().set_ivars(BluetoothDelegateIvars {
            conn_complete: Cell::new(false),
            conn_status: Cell::new(0),
            sdp_complete: Cell::new(false),
            sdp_status: Cell::new(0),
            rfcomm_complete: Cell::new(false),
            rfcomm_status: Cell::new(0),
        });
        unsafe { msg_send![super(this), init] }
    }
}

fn pump_until(
    deadline: Instant,
    condition: &Cell<bool>,
    what: &str,
    addr: &BtAddress,
) -> Result<()> {
    while !condition.get() {
        if Instant::now() >= deadline {
            bail!("{what} to {addr} timed out after {CONNECT_TIMEOUT:?}");
        }
        unsafe {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, RUNLOOP_TICK, 0);
        }
    }
    Ok(())
}

/// Connect to a Peripage printer over RFCOMM.
///
/// Must be called from the main thread — IOBluetooth delivers callbacks
/// through the main thread's CFRunLoop.
pub fn connect(address: &BtAddress) -> Result<MacosRfcommStream> {
    let addr_string = NSString::from_str(&address.display);
    let device = unsafe { IOBluetoothDevice::deviceWithAddressString(Some(&addr_string)) }
        .context("failed to create IOBluetoothDevice for address")?;

    let delegate = BluetoothDelegate::new();

    // Use openConnection: (with target) for async baseband connection.
    // This returns immediately and delivers connectionComplete:status:
    // via the CFRunLoop, which we pump below.
    eprintln!("opening baseband connection...");
    let result = unsafe { device.openConnection_(Some(&*delegate as &AnyObject)) };

    if result != 0 {
        bail!("openConnection to {} failed: IOReturn {result}", address);
    }

    let deadline = Instant::now() + CONNECT_TIMEOUT;
    pump_until(
        deadline,
        &delegate.ivars().conn_complete,
        "baseband connection",
        address,
    )?;

    let conn_status = delegate.ivars().conn_status.get();
    if conn_status != 0 {
        bail!(
            "baseband connection to {} failed: IOReturn {conn_status}",
            address
        );
    }

    if !unsafe { device.isConnected() } {
        bail!(
            "device {} reports not connected after openConnection",
            address
        );
    }

    // SDP query to discover the RFCOMM channel ID.
    eprintln!("baseband connected, querying SDP services...");
    let result = unsafe { device.performSDPQuery(Some(&*delegate as &AnyObject)) };

    if result != 0 {
        bail!("SDP query to {} failed to start: IOReturn {result}", address);
    }

    let deadline = Instant::now() + CONNECT_TIMEOUT;
    pump_until(
        deadline,
        &delegate.ivars().sdp_complete,
        "SDP query",
        address,
    )?;

    let sdp_status = delegate.ivars().sdp_status.get();
    if sdp_status != 0 {
        bail!("SDP query to {} failed: IOReturn {sdp_status}", address);
    }

    let channel_id = find_rfcomm_channel(&device)?;
    eprintln!("found RFCOMM channel {channel_id}, opening...");

    let mut channel: Option<Retained<IOBluetoothRFCOMMChannel>> = None;

    let result = unsafe {
        device.openRFCOMMChannelAsync_withChannelID_delegate(
            Some(&mut channel),
            channel_id,
            Some(&*delegate as &AnyObject),
        )
    };

    if result != 0 {
        bail!(
            "failed to start RFCOMM channel {channel_id} open to {}: IOReturn {result}",
            address
        );
    }

    // Check if the channel is already open (can happen for cached connections).
    if let Some(ref ch) = channel {
        if unsafe { ch.isOpen() } {
            eprintln!("channel already open");
        } else {
            let deadline = Instant::now() + CONNECT_TIMEOUT;
            pump_until(
                deadline,
                &delegate.ivars().rfcomm_complete,
                "RFCOMM channel open",
                address,
            )?;

            let rfcomm_status = delegate.ivars().rfcomm_status.get();
            if rfcomm_status != 0 {
                bail!(
                    "RFCOMM channel {channel_id} open to {} failed: IOReturn {rfcomm_status}",
                    address
                );
            }
        }
    }

    let channel =
        channel.context("openRFCOMMChannelAsync returned success but channel is None")?;

    Ok(MacosRfcommStream { channel, device })
}

/// Search the device's SDP service records for one with an RFCOMM channel.
fn find_rfcomm_channel(device: &IOBluetoothDevice) -> Result<BluetoothRFCOMMChannelID> {
    let services = unsafe { device.services() }
        .context("no SDP services found on device")?;

    let count = services.count();
    for i in 0..count {
        let obj = services.objectAtIndex(i);
        let record: &IOBluetoothSDPServiceRecord =
            unsafe { &*(Retained::as_ptr(&obj) as *const IOBluetoothSDPServiceRecord) };

        let mut channel_id: BluetoothRFCOMMChannelID = 0;
        let result = unsafe { record.getRFCOMMChannelID(&mut channel_id) };
        if result == 0 {
            return Ok(channel_id);
        }
    }

    bail!("no RFCOMM service found in SDP records");
}
