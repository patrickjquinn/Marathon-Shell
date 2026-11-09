//! marathon-power-profiles: the power-profiles D-Bus service
//! (`org.freedesktop.UPower.PowerProfiles`) on a phone, where a profile is
//! only the CPU governor: power-saver `powersave`, balanced the device
//! profile's governor, performance `performance`. It sleeps between calls.
//! The profile lasts across restarts; switching it takes polkit's yes.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::{env, fs};

use zbus::message::Header;
use zbus::{fdo, interface, OwnedVariant, Variant};

const BUS_NAME: &str = "org.freedesktop.UPower.PowerProfiles";
const PATH: &str = "/org/freedesktop/UPower/PowerProfiles";
const ACTION: &str = "org.marathonos.power-profiles.switch";
const PROFILES: [&str; 3] = ["power-saver", "balanced", "performance"];
const CPUFREQ: &str = "/sys/devices/system/cpu/cpufreq";
const DEVICE_PROFILE: &str = "/etc/marathon/device-profile.conf";

#[allow(clippy::print_stderr, reason = "journald collects stderr")]
fn log(message: &str) {
    eprintln!("marathon-power-profiles: {message}");
}

/// The governors a profile asks for, best first.
fn governors(profile: &str) -> Vec<String> {
    match profile {
        "power-saver" => vec!["powersave".into()],
        "performance" => vec!["performance".into()],
        _ => {
            let device = fs::read_to_string(DEVICE_PROFILE)
                .unwrap_or_default()
                .lines()
                .find_map(|l| l.trim().strip_prefix("CPU_GOVERNOR="))
                .map(|g| g.trim_matches(['"', '\'']).to_owned());
            device
                .into_iter()
                .chain(["ondemand".into(), "schedutil".into()])
                .collect()
        }
    }
}

/// Puts each CPU policy on the first of the profile's governors it has.
fn apply(profile: &str) {
    let wanted = governors(profile);
    for policy in fs::read_dir(CPUFREQ).into_iter().flatten().flatten() {
        let dir = policy.path();
        let available =
            fs::read_to_string(dir.join("scaling_available_governors")).unwrap_or_default();
        let Some(governor) = wanted
            .iter()
            .find(|g| available.split_whitespace().any(|a| a == g.as_str()))
        else {
            log(&format!("{}: none of {wanted:?} available", dir.display()));
            continue;
        };
        if let Err(e) = fs::write(dir.join("scaling_governor"), governor) {
            log(&format!("{}: {governor}: {e}", dir.display()));
        }
    }
}

fn state_file() -> Option<PathBuf> {
    env::var_os("STATE_DIRECTORY").map(|d| Path::new(&d).join("profile"))
}

async fn authorized(conn: &zbus::Connection, header: &Header<'_>) -> fdo::Result<()> {
    let sender = header
        .sender()
        .ok_or_else(|| fdo::Error::AccessDenied("unknown caller".into()))?
        .to_string();
    let subject = (
        "system-bus-name",
        HashMap::from([("name", Variant::from(sender.as_str()))]),
    );
    let reply = conn
        .call_method(
            Some("org.freedesktop.PolicyKit1"),
            "/org/freedesktop/PolicyKit1/Authority",
            Some("org.freedesktop.PolicyKit1.Authority"),
            "CheckAuthorization",
            &(subject, ACTION, HashMap::<&str, &str>::new(), 0_u32, ""),
        )
        .await?;
    let (yes, _, _): (bool, bool, HashMap<String, String>) = reply.body().deserialize()?;
    if yes {
        Ok(())
    } else {
        Err(fdo::Error::AccessDenied("not authorized".into()))
    }
}

struct Profiles {
    active: String,
}

#[interface(name = "org.freedesktop.UPower.PowerProfiles")]
#[allow(clippy::unused_self, reason = "D-Bus properties")]
impl Profiles {
    #[zbus(property)]
    fn active_profile(&self) -> String {
        self.active.clone()
    }

    #[zbus(property)]
    async fn set_active_profile(
        &mut self,
        profile: String,
        #[zbus(connection)] conn: &zbus::Connection,
        #[zbus(header)] header: Option<Header<'_>>,
    ) -> fdo::Result<()> {
        if !PROFILES.contains(&profile.as_str()) {
            return Err(fdo::Error::InvalidArgs(format!("no profile {profile}")));
        }
        let header = header.ok_or_else(|| fdo::Error::AccessDenied("unknown caller".into()))?;
        authorized(conn, &header).await?;
        apply(&profile);
        if let Some(file) = state_file() {
            fs::write(file, &profile).ok();
        }
        self.active = profile;
        Ok(())
    }

    #[zbus(property)]
    fn profiles(&self) -> Vec<HashMap<&'static str, Variant<'static>>> {
        PROFILES
            .iter()
            .map(|p| {
                HashMap::from([
                    ("Profile", Variant::from(*p)),
                    ("Driver", Variant::from("marathon")),
                    ("CpuDriver", Variant::from("marathon")),
                    ("PlatformDriver", Variant::from("placeholder")),
                ])
            })
            .collect()
    }

    #[zbus(property)]
    fn performance_degraded(&self) -> String {
        String::new()
    }

    #[zbus(property)]
    fn actions(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(property)]
    fn active_profile_holds(&self) -> Vec<HashMap<String, OwnedVariant>> {
        Vec::new()
    }

    #[zbus(property)]
    fn version(&self) -> String {
        env!("CARGO_PKG_VERSION").to_owned()
    }
}

fn main() -> ExitCode {
    let active = state_file()
        .and_then(|f| fs::read_to_string(f).ok())
        .map(|p| p.trim().to_owned())
        .filter(|p| PROFILES.contains(&p.as_str()))
        .unwrap_or_else(|| "balanced".to_owned());
    apply(&active);
    let served = zbus::block_on(async {
        let _conn = zbus::connection::Builder::system()
            .serve_at(PATH, Profiles { active })
            .name(BUS_NAME)
            .build()
            .await?;
        std::future::pending::<()>().await;
        zbus::Result::Ok(())
    });
    if let Err(e) = served {
        log(&format!("cannot serve {BUS_NAME}: {e}"));
    }
    ExitCode::FAILURE
}
