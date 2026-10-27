//! `StorageMonitor`: free space on the filesystem holding `$HOME`, checked
//! every 30 minutes. Signals when it runs low and when it recovers.

use std::ffi::CString;
use std::pin::Pin;
use std::time::Duration;

use async_io::Timer;
use cxx_qt::Threading;

use crate::{io, log};

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    extern "RustQt" {
        #[qobject]
        type StorageMonitor = super::StorageMonitorRust;

        /// Free space fell under the low mark; `free_bytes` is what is left.
        #[qsignal]
        #[cxx_name = "lowStorage"]
        fn low_storage(self: Pin<&mut Self>, free_bytes: i64);
        /// Free space is back above the recovery mark.
        #[qsignal]
        #[cxx_name = "storageRecovered"]
        fn storage_recovered(self: Pin<&mut Self>);
    }

    impl cxx_qt::Threading for StorageMonitor {}
    impl cxx_qt::Initialize for StorageMonitor {}
}

const EVERY: Duration = Duration::from_mins(30);
const GIB: u64 = 1 << 30;

#[derive(Default)]
pub struct StorageMonitorRust;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Change {
    Low,
    Recovered,
}

/// Low under 10 % or 1 GiB, whichever is more; recovered over 15 % or
/// 1.5 GiB, so a small disk cannot flap between the two. The first reading
/// (`low` unknown) is one or the other, so a warning left from before a
/// restart is cleared.
fn change(low: Option<bool>, free: u64, total: u64) -> Option<Change> {
    let Some(low) = low else {
        return Some(change(Some(false), free, total).unwrap_or(Change::Recovered));
    };
    let (free, total) = (u128::from(free) * 100, u128::from(total));
    if low && free > (total * 15).max(u128::from(GIB) * 150) {
        Some(Change::Recovered)
    } else if !low && free < (total * 10).max(u128::from(GIB) * 100) {
        Some(Change::Low)
    } else {
        None
    }
}

/// (free to the user, total) bytes of the filesystem holding `$HOME`.
fn space() -> Option<(u64, u64)> {
    let home = CString::new(std::env::var_os("HOME")?.into_encoded_bytes()).ok()?;
    // SAFETY: statvfs(3) fills a plain struct; `home` is NUL-terminated.
    let s = unsafe {
        let mut s = std::mem::zeroed::<libc::statvfs>();
        (libc::statvfs(home.as_ptr(), &raw mut s) == 0).then_some(s)?
    };
    let unit = s.f_frsize;
    Some((s.f_bavail * unit, s.f_blocks * unit))
}

impl cxx_qt::Initialize for qobject::StorageMonitor {
    fn initialize(self: Pin<&mut Self>) {
        let qt = self.qt_thread();
        io::spawn(async move {
            let mut low = None;
            loop {
                match space().filter(|(_, total)| *total > 0) {
                    Some((free, total)) => match change(low, free, total) {
                        Some(Change::Low) => {
                            low = Some(true);
                            log::warn("storage", format_args!("{free} of {total} bytes free"));
                            qt.queue(move |obj| {
                                obj.low_storage(i64::try_from(free).unwrap_or(i64::MAX));
                            })
                            .ok();
                        }
                        Some(Change::Recovered) => {
                            low = Some(false);
                            qt.queue(qobject::StorageMonitor::storage_recovered).ok();
                        }
                        None => {}
                    },
                    None => log::warn("storage", format_args!("cannot read free space")),
                }
                Timer::after(EVERY).await;
            }
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOTAL: u64 = 17 * GIB;

    #[test]
    fn low_below_ten_percent_of_a_big_disk() {
        assert_eq!(
            change(Some(false), TOTAL / 10 - 1, TOTAL),
            Some(Change::Low)
        );
        assert_eq!(change(Some(false), TOTAL / 10 + GIB, TOTAL), None);
    }

    #[test]
    fn low_below_one_gib_of_a_small_disk() {
        let small = 4 * GIB;
        assert_eq!(change(Some(false), GIB - 1, small), Some(Change::Low));
        assert_eq!(change(Some(false), GIB + 1, small), None);
    }

    #[test]
    fn recovers_only_above_fifteen_percent() {
        assert_eq!(change(Some(true), TOTAL / 8, TOTAL), None);
        assert_eq!(change(Some(true), TOTAL * 15 / 100, TOTAL), None);
        assert_eq!(
            change(Some(true), TOTAL * 16 / 100, TOTAL),
            Some(Change::Recovered)
        );
    }

    #[test]
    fn a_small_disk_recovers_over_one_and_a_half_gib() {
        let small = 4 * GIB;
        assert_eq!(change(Some(true), GIB * 14 / 10, small), None);
        assert_eq!(
            change(Some(true), GIB * 16 / 10, small),
            Some(Change::Recovered)
        );
    }

    #[test]
    fn the_first_reading_is_low_or_recovered() {
        assert_eq!(change(None, TOTAL / 20, TOTAL), Some(Change::Low));
        assert_eq!(change(None, TOTAL / 2, TOTAL), Some(Change::Recovered));
    }

    #[test]
    fn nothing_changes_while_the_state_holds() {
        assert_eq!(change(Some(true), 0, TOTAL), None);
        assert_eq!(change(Some(false), TOTAL, TOTAL), None);
    }

    #[test]
    fn reads_the_home_filesystem() {
        let (free, total) = space().unwrap_or_default();
        assert!(total > 0 && free <= total);
    }
}
