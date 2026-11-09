//! marathon-charger: what a phone shows when a charger, not the power key,
//! turned it on (Android's off-mode charging). The bootloader names the
//! reason in the device tree; `marathon-charger boot-mode` reports it, a
//! systemd generator boots `marathon-charging.target` for it, and the
//! daemon shows the charge on the boot splash. A press of the power key
//! shows it again, holding it starts Marathon, and pulling the charger
//! powers the phone off. It sleeps until a key, a power-supply event or
//! its next deadline.

use std::fs;
use std::os::fd::{AsFd, AsRawFd, OwnedFd};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};
use std::time::{Duration, Instant};

use evdev::{Device, EventSummary, KeyCode};
use nix::errno::Errno;
use nix::poll::{poll, PollFd, PollFlags, PollTimeout};
use nix::sys::socket::{
    bind, recv, socket, AddressFamily, MsgFlags, NetlinkAddr, SockFlag, SockProtocol, SockType,
};

const CHOSEN: &str = "/proc/device-tree/chosen";
const SUPPLIES: &str = "/sys/class/power_supply";
const BACKLIGHTS: &str = "/sys/class/backlight";
/// MediaTek preloader boot reason: a charger was plugged in (`BR_USB`).
const REASON_CHARGER: u32 = 1;
/// MediaTek boot modes: kernel and low-power off-mode charging.
const MODES_CHARGER: [u32; 2] = [8, 9];
const SHOW_FOR: Duration = Duration::from_secs(10);
const HOLD_TO_BOOT: Duration = Duration::from_secs(2);
const UNPLUGGED_FOR: Duration = Duration::from_secs(3);
/// Started with no charger in: time to hold the power key and boot instead.
const NEVER_PLUGGED_FOR: Duration = Duration::from_secs(30);

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-charger: {message}");
}

fn chosen_u32(name: &str) -> Option<u32> {
    let bytes = fs::read(Path::new(CHOSEN).join(name)).ok()?;
    Some(u32::from_be_bytes(bytes.get(..4)?.try_into().ok()?))
}

fn charger_boot() -> bool {
    chosen_u32("marathon,boot-reason") == Some(REASON_CHARGER)
        || chosen_u32("marathon,boot-mode").is_some_and(|m| MODES_CHARGER.contains(&m))
}

fn read(path: &Path) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| s.trim().to_owned())
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct Charge {
    percent: u8,
    full: bool,
    plugged: bool,
}

/// The first battery that reports a capacity, and whether any supply is online.
fn charge() -> Charge {
    let mut charge = Charge { percent: 0, full: false, plugged: false };
    let mut battery = false;
    for dir in fs::read_dir(SUPPLIES).into_iter().flatten().flatten().map(|e| e.path()) {
        if read(&dir.join("type")).as_deref() == Some("Battery") {
            let capacity = read(&dir.join("capacity")).and_then(|c| c.parse::<u8>().ok());
            if let (false, Some(percent)) = (battery, capacity) {
                battery = true;
                charge.percent = percent.min(100);
                charge.full = percent >= 100 || read(&dir.join("status")).as_deref() == Some("Full");
            }
        } else if read(&dir.join("online")).as_deref() == Some("1") {
            charge.plugged = true;
        }
    }
    charge
}

struct Backlight {
    brightness: PathBuf,
    on: String,
}

impl Backlight {
    fn find() -> Option<Self> {
        let dir = fs::read_dir(BACKLIGHTS).ok()?.flatten().next()?.path();
        let current = read(&dir.join("brightness"))?;
        let max: u32 = read(&dir.join("max_brightness"))?.parse().ok()?;
        let on = if current == "0" { (max / 2).max(1).to_string() } else { current };
        Some(Self { brightness: dir.join("brightness"), on })
    }

    fn set(&self, on: bool) {
        if let Err(e) = fs::write(&self.brightness, if on { self.on.as_str() } else { "0" }) {
            log(&format!("{}: {e}", self.brightness.display()));
        }
    }
}

fn run(program: &str, args: &[&str]) {
    match Command::new(program).args(args).status() {
        Ok(status) if status.success() => {}
        Ok(status) => log(&format!("{program} {}: {status}", args.join(" "))),
        Err(e) => log(&format!("{program}: {e}")),
    }
}

/// The splash draws the battery (marathon.script).
fn show(charge: Charge) {
    let state = if charge.full { "full" } else { "charging" };
    run("plymouth", &["update", &format!("--status=marathon-charge-{}-{state}", charge.percent)]);
}

fn uevents() -> nix::Result<OwnedFd> {
    let fd = socket(
        AddressFamily::Netlink,
        SockType::Datagram,
        SockFlag::SOCK_CLOEXEC | SockFlag::SOCK_NONBLOCK,
        SockProtocol::NetlinkKObjectUEvent,
    )?;
    bind(fd.as_raw_fd(), &NetlinkAddr::new(0, 1))?;
    Ok(fd)
}

/// Reads every queued uevent; true if one was about a power supply.
fn power_supply_changed(uevents: &OwnedFd) -> bool {
    let mut buf = [0_u8; 4096];
    let mut changed = false;
    while let Ok(n) = recv(uevents.as_raw_fd(), &mut buf, MsgFlags::empty()) {
        changed |= buf[..n].split(|&b| b == 0).any(|field| field == b"SUBSYSTEM=power_supply");
    }
    changed
}

#[allow(clippy::too_many_lines, reason = "one event loop")]
fn charging_screen() -> ExitCode {
    let mut keys: Vec<Device> = evdev::enumerate()
        .map(|(_, device)| device)
        .filter(|d| d.supported_keys().is_some_and(|k| k.contains(KeyCode::KEY_POWER)))
        .collect();
    if keys.is_empty() {
        log("no power key: the phone stays on the charging screen until it is unplugged");
    }
    let uevents = match uevents() {
        Ok(fd) => fd,
        Err(e) => {
            log(&format!("cannot follow power-supply events: {e}"));
            return ExitCode::FAILURE;
        }
    };
    let backlight = Backlight::find();
    let mut charge = charge();
    show(charge);
    let mut hide_at = Some(Instant::now() + SHOW_FOR);
    let mut pressed_at: Option<Instant> = None;
    let mut power_off_at = (!charge.plugged).then(|| Instant::now() + NEVER_PLUGGED_FOR);

    loop {
        let now = Instant::now();
        if power_off_at.is_some_and(|t| now >= t) {
            log("the charger is out: powering off");
            run("systemctl", &["poweroff"]);
            return ExitCode::SUCCESS;
        }
        if pressed_at.is_some_and(|t| now >= t + HOLD_TO_BOOT) {
            log("the power key was held: starting Marathon");
            run("systemctl", &["reboot"]);
            return ExitCode::SUCCESS;
        }
        if hide_at.is_some_and(|t| now >= t) {
            hide_at = None;
            if let Some(b) = &backlight {
                b.set(false);
            }
        }
        let next = [power_off_at, pressed_at.map(|t| t + HOLD_TO_BOOT), hide_at]
            .into_iter()
            .flatten()
            .min();
        let timeout = next.map_or(PollTimeout::NONE, |t| {
            PollTimeout::try_from(t.saturating_duration_since(now)).unwrap_or(PollTimeout::MAX)
        });

        let ready: Vec<bool> = {
            let mut fds: Vec<PollFd> = keys.iter().map(|d| PollFd::new(d.as_fd(), PollFlags::POLLIN)).collect();
            fds.push(PollFd::new(uevents.as_fd(), PollFlags::POLLIN));
            match poll(&mut fds, timeout) {
                Ok(_) | Err(Errno::EINTR) => {}
                Err(e) => {
                    log(&format!("poll: {e}"));
                    return ExitCode::FAILURE;
                }
            }
            fds.iter().map(|f| f.any().unwrap_or(false)).collect()
        };

        if ready.last() == Some(&true) && power_supply_changed(&uevents) {
            let now_charge = self::charge();
            if now_charge.plugged {
                power_off_at = None;
            } else if power_off_at.is_none() {
                power_off_at = Some(Instant::now() + UNPLUGGED_FOR);
            }
            if now_charge != charge {
                charge = now_charge;
                show(charge);
            }
        }

        for (device, _) in keys.iter_mut().zip(&ready).filter(|(_, ready)| **ready) {
            let events = match device.fetch_events() {
                Ok(events) => events,
                Err(e) => {
                    log(&format!("power key: {e}"));
                    continue;
                }
            };
            for event in events {
                match event.destructure() {
                    EventSummary::Key(_, KeyCode::KEY_POWER, 1) => {
                        pressed_at = Some(Instant::now());
                        hide_at = Some(Instant::now() + SHOW_FOR);
                        show(charge);
                        if let Some(b) = &backlight {
                            b.set(true);
                        }
                    }
                    EventSummary::Key(_, KeyCode::KEY_POWER, 0) => pressed_at = None,
                    _ => {}
                }
            }
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
        [] => charging_screen(),
        ["boot-mode"] => {
            #[allow(clippy::print_stdout, reason = "the command's answer")]
            {
                println!("{}", if charger_boot() { "charger" } else { "normal" });
            }
            ExitCode::SUCCESS
        }
        ["boot-mode", "charger"] => ExitCode::from(u8::from(!charger_boot())),
        ["boot-mode", "normal"] => ExitCode::from(u8::from(charger_boot())),
        _ => {
            log("usage: marathon-charger [boot-mode [charger|normal]]");
            ExitCode::from(2)
        }
    }
}
