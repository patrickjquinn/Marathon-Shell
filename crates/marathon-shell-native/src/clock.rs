//! Local time, as libc's time zone has it.

use std::time::{SystemTime, UNIX_EPOCH};

/// Seconds since the epoch.
pub fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0))
}

pub fn local(at: i64) -> Option<libc::tm> {
    // SAFETY: localtime_r writes the zeroed tm it is given.
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        (!libc::localtime_r(&raw const at, &raw mut tm).is_null()).then_some(tm)
    }
}

/// The next `hour`:00 local time after `now`.
pub fn next(now: i64, hour: i32) -> i64 {
    let Some(mut tm) = local(now) else { return 0 };
    tm.tm_hour = hour;
    tm.tm_min = 0;
    tm.tm_sec = 0;
    tm.tm_isdst = -1;
    // SAFETY: mktime normalises the tm it is given.
    let mut at = unsafe { libc::mktime(&raw mut tm) };
    if now >= at {
        tm.tm_mday += 1;
        tm.tm_isdst = -1;
        // SAFETY: as above; a day past the month's end rolls over.
        at = unsafe { libc::mktime(&raw mut tm) };
    }
    at
}
