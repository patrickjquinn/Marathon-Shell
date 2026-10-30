//! Missing SOC is unknown, not a measured empty cell.

#[allow(
    clippy::cast_possible_truncation,
    reason = "finite percentage checked in 0..=100"
)]
pub fn level(percentage: Option<f64>, measured: bool) -> i32 {
    match percentage {
        Some(value) if measured && value.is_finite() && (0.0..=100.0).contains(&value) => {
            value.round() as i32
        }
        _ => -1,
    }
}

pub fn known(level: i32) -> bool {
    (0..=100).contains(&level)
}

pub fn can_arm_shutdown(level: i32, warning: u32, charging: bool) -> bool {
    known(level) && warning >= 4 && !charging && critical_actions_allowed()
}

/// Experimental board models may display an estimate without powering off
/// the device based on that estimate. Absence preserves ordinary gauge policy.
pub fn critical_actions_allowed() -> bool {
    !std::path::Path::new("/etc/marathon/battery-model-experimental")
        .try_exists()
        .unwrap_or(true)
}

/// Board policy lists redundant configuration supplies, one exact name per line.
/// Missing policy preserves normal enumeration; invalid policy keeps SOC unknown.
pub fn available(root: &std::path::Path) -> bool {
    available_with_policy(
        root,
        std::path::Path::new("/etc/marathon/power-supply-ignore"),
    )
}

fn available_with_policy(root: &std::path::Path, policy: &std::path::Path) -> bool {
    let ignored = match std::fs::read_to_string(policy) {
        Ok(text) => {
            let mut names = Vec::new();
            for line in text.lines().map(str::trim) {
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                if line.starts_with('.')
                    || !line
                        .bytes()
                        .all(|byte| byte.is_ascii_alphanumeric() || b"_-".contains(&byte))
                {
                    return false;
                }
                names.push(line.to_owned());
            }
            names
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Vec::new(),
        Err(_) => return false,
    };
    available_except(root, &ignored)
}

/// Use standard power-supply measurements. A declared but unreadable capacity
/// remains unknown, including a model whose initial seed has not been qualified.
fn available_except(root: &std::path::Path, ignored: &[String]) -> bool {
    let Ok(entries) = std::fs::read_dir(root) else {
        return false;
    };
    let mut found = false;
    let mut uncertain = false;
    let mut all_measured = true;
    for entry in entries {
        let Ok(entry) = entry else {
            uncertain = true;
            continue;
        };
        if ignored
            .iter()
            .any(|name| entry.file_name() == name.as_str())
        {
            continue;
        }
        let supply = entry.path();
        let Ok(kind) = std::fs::read_to_string(supply.join("type")) else {
            uncertain = true;
            continue;
        };
        if kind.trim() != "Battery" {
            continue;
        }
        if supply.join("scope").exists() {
            match std::fs::read_to_string(supply.join("scope")) {
                Ok(scope) if scope.trim() == "Device" => continue,
                Ok(_) => {}
                Err(_) => {
                    uncertain = true;
                    continue;
                }
            }
        }
        found = true;
        let read = |name| {
            std::fs::read_to_string(supply.join(name))
                .ok()
                .and_then(|value| value.trim().parse::<u64>().ok())
        };
        all_measured &= read("capacity").is_some_and(|value| value <= 100)
            || (read("energy_now").is_some()
                && read("energy_full")
                    .or_else(|| read("energy_full_design"))
                    .is_some_and(|value| value > 0))
            || (read("charge_now").is_some()
                && read("charge_full")
                    .or_else(|| read("charge_full_design"))
                    .is_some_and(|value| value > 0));
    }
    found && all_measured && !uncertain
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn unknown_is_not_empty_or_full() {
        assert_eq!(level(None, true), -1);
        assert_eq!(level(Some(0.0), false), -1);
        assert_eq!(level(Some(100.0), false), -1);
        for p in [f64::NAN, f64::INFINITY, -1.0, 101.0] {
            assert_eq!(level(Some(p), true), -1);
        }
    }
    #[test]
    fn real_zero_and_full_are_preserved() {
        assert_eq!(level(Some(0.0), true), 0);
        assert_eq!(level(Some(100.0), true), 100);
        assert_eq!(level(Some(54.6), true), 55);
    }
    #[test]
    fn unknown_cannot_arm_at_any_warning() {
        for warning in 0..=10 {
            assert!(!can_arm_shutdown(-1, warning, false));
            assert!(!can_arm_shutdown(-1, warning, true));
        }
        assert!(can_arm_shutdown(0, 4, false));
        assert!(!can_arm_shutdown(100, 1, false));
        assert!(!can_arm_shutdown(0, 4, true));
    }
    #[test]
    fn capability_evidence_is_conservative() {
        let root = std::env::temp_dir().join(format!("q25-soc-unit-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).unwrap();
        let available = |path| available_except(path, &[]);
        assert!(!available(&root));
        let gauge = root.join("fuel-gauge");
        std::fs::create_dir(&gauge).unwrap();
        std::fs::write(gauge.join("type"), "Battery\n").unwrap();
        std::fs::write(gauge.join("voltage_now"), "4183000").unwrap();
        assert!(!available(&root));
        std::fs::write(gauge.join("capacity"), "0").unwrap();
        assert!(available(&root));
        std::fs::write(gauge.join("capacity"), "invalid").unwrap();
        assert!(!available(&root));
        std::fs::write(gauge.join("capacity"), "101").unwrap();
        assert!(!available(&root));
        std::fs::write(gauge.join("capacity"), "0").unwrap();
        let unreadable = root.join("broken");
        std::fs::create_dir(&unreadable).unwrap();
        assert!(!available(&root)); // no type; no permission-dependent test
        std::fs::remove_dir(&unreadable).unwrap();
        assert!(available(&root));
        let duplicate = root.join("bq256xx-battery");
        std::fs::create_dir(&duplicate).unwrap();
        std::fs::write(duplicate.join("type"), "Battery").unwrap();
        assert!(!available(&root)); // mixed known/unknown aggregate is unknown
                                    // Policy lives outside the power_supply directory on real systems.
        let policy = root.with_extension("policy");
        std::fs::write(&policy, "# Q25 configuration proxy\nbq256xx-battery\n").unwrap();
        assert!(available_with_policy(&root, &policy));
        std::fs::write(&policy, "../fuel-gauge\n").unwrap();
        assert!(!available_with_policy(&root, &policy));
        std::fs::remove_file(&policy).unwrap();
        std::fs::write(duplicate.join("scope"), "Device").unwrap();
        assert!(available(&root)); // peripheral excluded
        std::fs::remove_file(gauge.join("capacity")).unwrap();
        std::fs::write(gauge.join("energy_full_design"), "13320000").unwrap();
        assert!(!available(&root)); // design-only is not remaining energy
        std::fs::write(gauge.join("energy_now"), "0").unwrap();
        assert!(available(&root));
        std::fs::remove_dir_all(root).unwrap();
    }
}
