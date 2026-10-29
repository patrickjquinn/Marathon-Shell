//! What the session daemons that took services over from the shell share:
//! the shell's permission gate, its data directories and their store.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use zbus::fdo;
use zbus::message::Header;

/// Whether the caller of `header`'s method holds one of `permissions`, as
/// the shell answers for its own services; `area` is the rate limit's key.
pub async fn admit(
    bus: &zbus::Connection,
    header: &Header<'_>,
    area: &str,
    permissions: &[&str],
) -> fdo::Result<()> {
    let denied = |text: &str| Err(fdo::Error::AccessDenied(text.to_owned()));
    let Some(sender) = header.sender() else {
        return denied("Unknown caller");
    };
    let asked = bus
        .call_method(
            Some("org.marathonos.Shell"),
            "/org/marathonos/Shell/Permissions",
            Some("org.marathonos.Shell.Permissions1"),
            "Admit",
            &(sender.as_str(), area, permissions),
        )
        .await;
    match asked {
        Ok(_) => Ok(()),
        Err(zbus::Error::FDO(error))
            if matches!(
                *error,
                fdo::Error::AccessDenied(_) | fdo::Error::LimitsExceeded(_)
            ) =>
        {
            Err(*error)
        }
        Err(zbus::Error::MethodError(_, Some(text), _)) => denied(&text),
        Err(e) => {
            crate::log::warn(
                area,
                format_args!("the shell did not answer for {sender}: {e}"),
            );
            denied("Unknown caller")
        }
    }
}

/// The shell's own data (Qt's `AppLocalDataLocation`), where its services
/// kept their databases.
pub fn shell_data() -> PathBuf {
    crate::dirs::data().join("Marathon OS/Marathon Shell")
}

/// The shell's cache (`CacheLocation`), which app sandboxes bind.
pub fn shell_cache() -> PathBuf {
    crate::dirs::cache().join("Marathon OS/Marathon Shell")
}

/// State that blocking work takes in turn, off the executor.
pub struct Shared<T>(Arc<Mutex<T>>);

impl<T> Clone for Shared<T> {
    fn clone(&self) -> Self {
        Self(Arc::clone(&self.0))
    }
}

impl<T: Send + 'static> Shared<T> {
    pub fn new(value: T) -> Self {
        Self(Arc::new(Mutex::new(value)))
    }

    /// Runs blocking `work` with exclusive access to the shared state.
    ///
    /// Aborts rather than exposing the state if an earlier operation poisoned
    /// it. Continuing with potentially inconsistent daemon state is unsafe.
    pub async fn with<R: Send + 'static>(
        &self,
        work: impl FnOnce(&mut T) -> R + Send + 'static,
    ) -> R {
        let state = Arc::clone(&self.0);
        blocking::unblock(move || {
            let mut state = state.lock().unwrap_or_else(|_| std::process::abort());
            work(&mut state)
        })
        .await
    }
}

/// A phone number as dialled: its digits and `+`.
pub fn dialable(number: &str) -> String {
    number
        .chars()
        .filter(|c| c.is_ascii_digit() || *c == '+')
        .collect()
}

/// Whether two numbers reach the same phone: the same, or one ends in the
/// other's last ten digits.
pub fn same_number(a: &str, b: &str) -> bool {
    let (a, b) = (dialable(a), dialable(b));
    let last_ten = |n: &str| n[n.len().saturating_sub(10)..].to_owned();
    !a.is_empty()
        && !b.is_empty()
        && (a == b || a.ends_with(&last_ten(&b)) || b.ends_with(&last_ten(&a)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numbers_match_on_their_last_ten_digits() {
        assert!(same_number("+1 (415) 555-0142", "4155550142"));
        assert!(!same_number("+1 415 555 0142", "+1 415 555 0143"));
    }

    // A contact without a number matched every caller.
    #[test]
    fn no_number_matches_nothing() {
        assert!(!same_number("", "4155550142"));
        assert!(!same_number("4155550142", "Unknown"));
    }
}
