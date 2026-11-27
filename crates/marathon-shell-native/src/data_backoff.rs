//! Mobile data retries after a failed activation. `NetworkManager` re-dials
//! a modem whose enable fails at once many times a second: it files the
//! modem's fall back to disabled as a user's disconnect, which spends no
//! autoconnect retry. So the shell blocks the device's autoconnect after a
//! failure and dials again itself, further apart each time, until it stops.

use std::time::Duration;

/// The wait after the first failure; each one after doubles it.
const FIRST_WAIT: Duration = Duration::from_secs(10);
/// Failures in a row before the shell stops dialling.
const MAX_FAILURES: u32 = 6;

#[derive(Default)]
pub(crate) struct Backoff {
    failures: u32,
    /// Tells a retry that is still due from one a reset made stale.
    generation: u32,
}

impl Backoff {
    /// One more failure: the wait before the next try and that try's
    /// generation, or `None` once the shell stops.
    pub(crate) fn failed(&mut self) -> Option<(Duration, u32)> {
        self.failures = self.failures.saturating_add(1);
        self.generation = self.generation.wrapping_add(1);
        (self.failures < MAX_FAILURES)
            .then(|| (FIRST_WAIT * 2u32.pow(self.failures - 1), self.generation))
    }

    /// Starts over; whether there were failures to forget.
    pub(crate) fn reset(&mut self) -> bool {
        self.generation = self.generation.wrapping_add(1);
        std::mem::take(&mut self.failures) > 0
    }

    /// Whether a retry scheduled as `generation` is still the one due.
    pub(crate) fn due(&self, generation: u32) -> bool {
        self.failures > 0 && self.failures < MAX_FAILURES && generation == self.generation
    }

    /// Failures since the last success or reset.
    pub(crate) fn failing(&self) -> bool {
        self.failures > 0
    }

    pub(crate) fn stopped(&self) -> bool {
        self.failures >= MAX_FAILURES
    }
}

/// `NetworkManager`'s device state went from activating (prepare 40 to
/// secondaries 90) to unavailable, disconnected or failed.
pub(crate) fn activation_failed(was: u32, now: u32) -> bool {
    (40..=90).contains(&was) && matches!(now, 20 | 30 | 120)
}

#[zbus::proxy(
    interface = "org.freedesktop.NetworkManager.Device",
    default_service = "org.freedesktop.NetworkManager"
)]
trait DeviceAutoconnect {
    /// The device's runtime autoconnect: false blocks it until set true,
    /// and the shell's own activations still go through.
    #[zbus(property)]
    fn set_autoconnect(&self, on: bool) -> zbus::Result<()>;
}

pub(crate) async fn set_autoconnect(
    bus: &zbus::Connection,
    device: zbus::OwnedObjectPath,
    on: bool,
) -> zbus::Result<()> {
    DeviceAutoconnectProxy::builder(bus)
        .path(device)
        .build()
        .await?
        .set_autoconnect(on)
        .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn waits_double_then_it_stops() {
        let mut backoff = Backoff::default();
        let waits: Vec<u64> = std::iter::from_fn(|| backoff.failed())
            .map(|(wait, _)| wait.as_secs())
            .collect();
        assert_eq!(waits, [10, 20, 40, 80, 160]);
        assert!(backoff.stopped());
        assert!(backoff.reset());
        assert!(!backoff.failing());
        assert!(!backoff.reset());
    }

    #[test]
    fn a_reset_makes_the_due_retry_stale() {
        let mut backoff = Backoff::default();
        let first = backoff.failed().map(|(_, generation)| generation);
        assert!(first.is_some_and(|g| backoff.due(g)));
        backoff.reset();
        assert!(!first.is_some_and(|g| backoff.due(g)));
        let next = backoff.failed().map(|(_, generation)| generation);
        assert!(!first.is_some_and(|g| backoff.due(g)));
        assert!(next.is_some_and(|g| backoff.due(g)));
    }

    #[test]
    fn only_a_failed_activation_counts() {
        assert!(activation_failed(40, 30));
        assert!(activation_failed(70, 120));
        assert!(activation_failed(50, 20));
        // Activated, then switched off or dropped: not an activation.
        assert!(!activation_failed(100, 30));
        assert!(!activation_failed(110, 30));
        // Still on its way.
        assert!(!activation_failed(40, 50));
    }
}
