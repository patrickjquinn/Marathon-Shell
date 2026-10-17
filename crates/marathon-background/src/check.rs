//! `check`: a task's network and battery constraints, as an `ExecCondition=`.
//! Exit 0 runs the task; 1 skips it until its next slot.

use std::fs;
use std::path::Path;

use serde::Deserialize;

/// Marathon's own low-battery warning level (`PowerPolicyController`).
pub const LOW_BATTERY_PERCENT: u32 = 20;
const NM_STATE_CONNECTED_GLOBAL: u32 = 70;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Network {
    Any,
    Unmetered,
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Constraints {
    pub network: Option<Network>,
    pub battery_not_low: bool,
}

pub fn parse_args<I: IntoIterator<Item = String>>(args: I) -> Result<Constraints, String> {
    let mut constraints = Constraints::default();
    for arg in args {
        match arg.as_str() {
            "--network=any" => constraints.network = Some(Network::Any),
            "--network=unmetered" => constraints.network = Some(Network::Unmetered),
            "--battery-not-low" => constraints.battery_not_low = true,
            _ => return Err(format!("unknown argument {arg:?}")),
        }
    }
    Ok(constraints)
}

fn read(path: &Path) -> String {
    fs::read_to_string(path)
        .map(|s| s.trim().to_owned())
        .unwrap_or_default()
}

/// On battery and below `LOW_BATTERY_PERCENT`, from the kernel's power
/// supplies. Peripheral batteries (scope `Device`) do not count.
pub fn battery_low(power_supply: &Path) -> bool {
    let Ok(entries) = fs::read_dir(power_supply) else {
        return false;
    };
    let mut low = false;
    for supply in entries.filter_map(Result::ok).map(|e| e.path()) {
        if read(&supply.join("type")) != "Battery" {
            if read(&supply.join("online")) == "1" {
                return false;
            }
            continue;
        }
        if read(&supply.join("scope")) == "Device" {
            continue;
        }
        if let Ok(capacity) = read(&supply.join("capacity")).parse::<u32>() {
            low |= capacity < LOW_BATTERY_PERCENT;
        }
    }
    low
}

/// `NetworkManager`'s `State` and `Metered`: online is `CONNECTED_GLOBAL`;
/// unmetered is `NO` or `GUESS_NO`, so an unknown connection counts as metered.
pub fn network_ok(state: u32, metered: u32, need: Network) -> bool {
    state >= NM_STATE_CONNECTED_GLOBAL && (need == Network::Any || matches!(metered, 2 | 4))
}

fn network_manager() -> zbus::Result<(u32, u32)> {
    let conn = zbus::blocking::Connection::system()?;
    let nm = zbus::blocking::Proxy::new(
        &conn,
        "org.freedesktop.NetworkManager",
        "/org/freedesktop/NetworkManager",
        "org.freedesktop.NetworkManager",
    )?;
    Ok((nm.get_property("State")?, nm.get_property("Metered")?))
}

/// Why the constraints are not met, or `None` when the task may run.
pub fn unmet(constraints: &Constraints, power_supply: &Path) -> Option<String> {
    if constraints.battery_not_low && battery_low(power_supply) {
        return Some(format!("battery below {LOW_BATTERY_PERCENT}%"));
    }
    let need = constraints.network?;
    match network_manager() {
        Ok((state, metered)) if network_ok(state, metered, need) => None,
        Ok((state, metered)) => Some(format!(
            "network not {need:?} (NetworkManager State {state}, Metered {metered})"
        )),
        Err(e) => Some(format!("NetworkManager: {e}")),
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    fn supply(root: &Path, name: &str, attrs: &[(&str, &str)]) {
        let dir = root.join(name);
        fs::create_dir_all(&dir).unwrap();
        for (attr, value) in attrs {
            fs::write(dir.join(attr), format!("{value}\n")).unwrap();
        }
    }

    #[test]
    fn arguments_are_the_generated_ones() {
        assert_eq!(
            parse_args(["--network=unmetered".into(), "--battery-not-low".into()]).unwrap(),
            Constraints {
                network: Some(Network::Unmetered),
                battery_not_low: true
            }
        );
        assert_eq!(parse_args([]).unwrap(), Constraints::default());
        assert!(parse_args(["--network=wifi".into()]).is_err());
    }

    #[test]
    fn a_discharging_battery_under_the_warning_level_is_low() {
        let root = tempfile::tempdir().unwrap();
        supply(
            root.path(),
            "battery",
            &[("type", "Battery"), ("capacity", "19")],
        );
        supply(root.path(), "usb", &[("type", "USB"), ("online", "0")]);
        assert!(battery_low(root.path()));
        fs::write(root.path().join("battery/capacity"), "20").unwrap();
        assert!(!battery_low(root.path()));
    }

    #[test]
    fn external_power_is_never_low() {
        let root = tempfile::tempdir().unwrap();
        supply(
            root.path(),
            "battery",
            &[("type", "Battery"), ("capacity", "3")],
        );
        supply(root.path(), "usb", &[("type", "USB"), ("online", "1")]);
        assert!(!battery_low(root.path()));
    }

    #[test]
    fn peripheral_batteries_and_missing_supplies_do_not_count() {
        let root = tempfile::tempdir().unwrap();
        assert!(!battery_low(&root.path().join("missing")));
        supply(
            root.path(),
            "hid-mouse",
            &[("type", "Battery"), ("scope", "Device"), ("capacity", "2")],
        );
        assert!(!battery_low(root.path()));
    }

    #[test]
    fn network_needs_global_connectivity_and_unmetered_needs_no_meter() {
        assert!(network_ok(70, 1, Network::Any));
        assert!(!network_ok(60, 2, Network::Any));
        assert!(network_ok(70, 2, Network::Unmetered));
        assert!(network_ok(70, 4, Network::Unmetered));
        for metered in [0, 1, 3] {
            assert!(!network_ok(70, metered, Network::Unmetered), "{metered}");
        }
    }

    #[test]
    fn battery_is_checked_before_the_network() {
        let root = tempfile::tempdir().unwrap();
        supply(
            root.path(),
            "battery",
            &[("type", "Battery"), ("capacity", "5")],
        );
        let constraints = Constraints {
            network: None,
            battery_not_low: true,
        };
        assert_eq!(
            unmet(&constraints, root.path()).as_deref(),
            Some("battery below 20%")
        );
        assert_eq!(unmet(&Constraints::default(), root.path()), None);
    }
}
