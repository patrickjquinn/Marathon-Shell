//! A transient systemd user timer, `marathon-wake-<key>-<epoch>.timer`, that
//! marathon-background arm-wake reads before a suspend so the system wakes
//! for it (`docs/BACKGROUND_WORK.md`).

use zbus::zvariant::Value;

use crate::systemd::SystemdManagerProxy;

/// One key's wake-up; setting it again replaces the timer.
pub struct WakeTimer {
    key: String,
    unit: Option<String>,
}

impl WakeTimer {
    pub const fn new(key: String) -> Self {
        Self { key, unit: None }
    }

    /// Wakes the system at `epoch_secs`, or at no time for `epoch_secs <= 0`;
    /// false if systemd refused.
    pub async fn set(&mut self, bus: &zbus::Connection, epoch_secs: i64) -> bool {
        // The time is in the name: a stopped transient unit can linger for a
        // moment, so reusing one name would race its garbage collection.
        let unit = (epoch_secs > 0).then(|| unit_name(&self.key, epoch_secs));
        if unit == self.unit {
            return true;
        }
        let manager = match SystemdManagerProxy::new(bus).await {
            Ok(m) => m,
            Err(e) => {
                crate::log::warn("wake", e);
                return false;
            }
        };
        if let Some(old) = self.unit.take() {
            if let Err(e) = manager.stop_unit(&old, "replace").await {
                // An elapsed timer has already unloaded itself.
                if !is_error(&e, "org.freedesktop.systemd1.NoSuchUnit") {
                    crate::log::warn("wake", format_args!("could not stop {old}: {e}"));
                }
            }
        }
        let Some(unit) = unit else { return true };
        let service = unit.replace(".timer", ".service");
        let timer = [
            ("Description", Value::from(format!("Marathon wake-up: {}", self.key))),
            ("OnCalendar", Value::from(format!("@{epoch_secs}"))),
            ("RemainAfterElapse", Value::from(false)),
        ];
        // arm-wake only needs the timer's next elapse; its service does nothing.
        let exec = [("ExecStart", Value::from(vec![("/bin/true", vec!["/bin/true"], false)]))];
        match manager.start_transient_unit(&unit, "fail", &timer, &[(&service, &exec)]).await {
            // A previous shell left the same wake-up behind.
            Err(e) if !is_error(&e, "org.freedesktop.systemd1.UnitExists") => {
                crate::log::warn("wake", format_args!("could not start {unit}: {e}"));
                false
            }
            _ => {
                self.unit = Some(unit);
                true
            }
        }
    }
}

fn unit_name(key: &str, epoch_secs: i64) -> String {
    format!("marathon-wake-{key}-{epoch_secs}.timer")
}

fn is_error(e: &zbus::Error, name: &str) -> bool {
    matches!(e, zbus::Error::MethodError(n, _, _) if n.as_str() == name)
}

#[cfg(test)]
mod tests {
    #[test]
    fn the_unit_names_the_key_and_the_time() {
        assert_eq!(super::unit_name("alarm", 1_792_236_376), "marathon-wake-alarm-1792236376.timer");
    }
}
