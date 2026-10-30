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
    known(level) && warning >= 4 && !charging
}

/// Metadata only. Unreadable entries are skipped but keep the final decision
/// unknown, even if another entry appears valid. No ADC is sampled.
pub fn available(root: &std::path::Path) -> bool {
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
        all_measured &= supply.join("capacity").exists()
            || (supply.join("energy_now").exists()
                && (supply.join("energy_full").exists()
                    || supply.join("energy_full_design").exists()))
            || (supply.join("charge_now").exists()
                && (supply.join("charge_full").exists()
                    || supply.join("charge_full_design").exists()));
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
        assert!(!available(&root));
        let gauge = root.join("fuel-gauge");
        std::fs::create_dir(&gauge).unwrap();
        std::fs::write(gauge.join("type"), "Battery\n").unwrap();
        std::fs::write(gauge.join("voltage_now"), "4183000").unwrap();
        assert!(!available(&root));
        std::fs::write(gauge.join("capacity"), "0").unwrap();
        assert!(available(&root));
        let unreadable = root.join("broken");
        std::fs::create_dir(&unreadable).unwrap();
        assert!(!available(&root)); // no type; no permission-dependent test
        std::fs::remove_dir(&unreadable).unwrap();
        assert!(available(&root));
        let duplicate = root.join("bq256xx-battery");
        std::fs::create_dir(&duplicate).unwrap();
        std::fs::write(duplicate.join("type"), "Battery").unwrap();
        assert!(!available(&root)); // mixed known/unknown aggregate is unknown
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
