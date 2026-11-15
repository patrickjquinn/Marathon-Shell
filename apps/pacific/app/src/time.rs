// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Local time for "today" and history sections.

/// The local time zone's offset from UTC in seconds, from `date +%z`'s
/// form in `TZ`-aware libc (`localtime_r`).
pub fn local_utc_offset() -> i64 {
    // SAFETY: localtime_r writes into the tm we own; time_t is plain data.
    unsafe {
        let now = libc_time();
        let mut tm: Tm = std::mem::zeroed();
        if localtime_r(std::ptr::from_ref(&now), std::ptr::from_mut(&mut tm)).is_null() {
            0
        } else {
            tm.tm_gmtoff
        }
    }
}

/// glibc's `struct tm` (LP64).
#[repr(C)]
#[allow(clippy::struct_field_names, reason = "the C field names")]
struct Tm {
    tm_sec: i32,
    tm_min: i32,
    tm_hour: i32,
    tm_mday: i32,
    tm_mon: i32,
    tm_year: i32,
    tm_wday: i32,
    tm_yday: i32,
    tm_isdst: i32,
    tm_gmtoff: i64,
    tm_zone: *const std::ffi::c_char,
}

extern "C" {
    fn localtime_r(t: *const i64, tm: *mut Tm) -> *mut Tm;
    fn time(t: *mut i64) -> i64;
}

fn libc_time() -> i64 {
    // SAFETY: time() with a null pointer only returns the time.
    unsafe { time(std::ptr::null_mut()) }
}

/// The local calendar date (`YYYY-MM-DD`) of a time in ms.
pub fn local_date(ms: i64, offset_s: i64) -> String {
    let days = (ms / 1000 + offset_s).div_euclid(86_400);
    // Civil from days (Howard Hinnant's algorithm).
    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    format!("{y:04}-{m:02}-{d:02}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offset_is_sane() {
        let o = local_utc_offset();
        assert!((-14 * 3600..=14 * 3600).contains(&o));
    }

    #[test]
    fn dates() {
        assert_eq!(local_date(0, 0), "1970-01-01");
        assert_eq!(local_date(1_791_072_000_000, 0), "2026-10-04");
        assert_eq!(local_date(1_791_072_000_000 - 1, 0), "2026-10-03");
        assert_eq!(local_date(1_791_072_000_000 - 1, 3600), "2026-10-04");
        assert_eq!(local_date(951_782_400_000, 0), "2000-02-29");
    }
}
