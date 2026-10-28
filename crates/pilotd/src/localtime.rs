// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Local wall-clock time from the C library (`localtime_r`), which follows
//! the system time zone the way the Clock app does. The `time` crate's
//! local offset is unavailable in a multi-threaded process.

/// A local time with its UTC offset.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LocalNow {
    /// Unix seconds.
    pub epoch: i64,
    pub year: i32,
    /// 1 to 12.
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    /// 0 is Sunday, as `struct tm` and timed.
    pub weekday: u32,
    /// Seconds east of UTC.
    pub utc_offset: i64,
    /// Whether the date and time are in UTC (`fixed_utc`, tests) rather
    /// than the system time zone, for the arithmetic below.
    pub utc: bool,
}

/// `days` days after the given date, at `hour:minute` local time, through
/// `mktime` (the system zone's rules, a DST change included). None if the
/// C library cannot represent it.
fn mktime_local(year: i32, month: u32, day: u32, days: i64, hour: u32, minute: u32) -> Option<i64> {
    let int = |v: i64| libc::c_int::try_from(v).ok();
    // SAFETY: a zeroed `struct tm` is a valid value; the fields mktime
    // reads are set below.
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    tm.tm_year = year - 1900;
    tm.tm_mon = int(i64::from(month) - 1)?;
    tm.tm_mday = int(i64::from(day) + days)?;
    tm.tm_hour = int(i64::from(hour))?;
    tm.tm_min = int(i64::from(minute))?;
    // Let the zone say whether DST is in force on that day.
    tm.tm_isdst = -1;
    // SAFETY: `tm` is a valid, owned `struct tm`; mktime normalises it in
    // place (a day of month past the end rolls into the next month).
    let t = unsafe { libc::mktime(&raw mut tm) };
    #[allow(clippy::useless_conversion, reason = "time_t is 32 bits on armv7hl")]
    let t = i64::from(t);
    (t != -1).then_some(t)
}

impl LocalNow {
    /// Unix seconds of local midnight starting this day: on the day a DST
    /// change happens, fewer or more than `hour` hours ago.
    pub fn midnight(&self) -> i64 {
        self.local_time(0, 0, 0)
    }

    /// Unix seconds of local `hour:minute`, `days` days from today (0
    /// today, 1 tomorrow), by the zone's rules for that day: 07:00 the day
    /// after the clocks change is 07:00 on the clock, not 06:00 or 08:00.
    pub fn local_time(&self, days: i64, hour: u32, minute: u32) -> i64 {
        let naive = || {
            let since_midnight = i64::from(self.hour) * 3600
                + i64::from(self.minute) * 60
                + self.epoch.rem_euclid(60);
            self.epoch - since_midnight
                + days * 86_400
                + i64::from(hour) * 3600
                + i64::from(minute) * 60
        };
        if self.utc {
            return naive();
        }
        mktime_local(self.year, self.month, self.day, days, hour, minute).unwrap_or_else(naive)
    }

    /// "18:42", as in the Jev state context (section 5.1).
    pub fn hhmm(&self) -> String {
        format!("{:02}:{:02}", self.hour, self.minute)
    }

    /// "Wednesday 7 October 2026", for the model.
    pub fn long_date(&self) -> String {
        const DAYS: [&str; 7] = [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday",
        ];
        const MONTHS: [&str; 12] = [
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December",
        ];
        let day = DAYS.get(self.weekday as usize).unwrap_or(&"");
        let month = MONTHS
            .get((self.month as usize).wrapping_sub(1))
            .unwrap_or(&"");
        format!("{day} {} {month} {}", self.day, self.year)
    }

    /// The date in the person's language, as people write it there:
    /// "Montag, 12. Oktober 2026", "maanantai 12. lokakuuta 2026",
    /// "lunes, 12 de octubre de 2026". English for a language not listed.
    pub fn long_date_in(&self, locale: &crate::lang::Locale) -> String {
        let (days, months, pattern): (&[&str; 7], &[&str; 12], &str) =
            match locale.language.as_str() {
                "de" => (&DE_DAYS, &DE_MONTHS, "{w}, {d}. {m} {y}"),
                "fr" => (&FR_DAYS, &FR_MONTHS, "{w} {d} {m} {y}"),
                "es" => (&ES_DAYS, &ES_MONTHS, "{w}, {d} de {m} de {y}"),
                "it" => (&IT_DAYS, &IT_MONTHS, "{w} {d} {m} {y}"),
                "pt" => (&PT_DAYS, &PT_MONTHS, "{w}, {d} de {m} de {y}"),
                "nl" => (&NL_DAYS, &NL_MONTHS, "{w} {d} {m} {y}"),
                "sv" => (&SV_DAYS, &SV_MONTHS, "{w} {d} {m} {y}"),
                "fi" => (&FI_DAYS, &FI_MONTHS, "{w} {d}. {m} {y}"),
                "nb" | "no" | "nn" => (&NB_DAYS, &NB_MONTHS, "{w} {d}. {m} {y}"),
                "da" => (&NB_DAYS, &DA_MONTHS, "{w} {d}. {m} {y}"),
                "pl" => (&PL_DAYS, &PL_MONTHS, "{w}, {d} {m} {y}"),
                "cs" => (&CS_DAYS, &CS_MONTHS, "{w} {d}. {m} {y}"),
                _ => return self.long_date(),
            };
        let w = days.get(self.weekday as usize).copied().unwrap_or("");
        let m = months
            .get((self.month as usize).wrapping_sub(1))
            .copied()
            .unwrap_or("");
        pattern
            .replace("{w}", w)
            .replace("{d}", &self.day.to_string())
            .replace("{m}", m)
            .replace("{y}", &self.year.to_string())
    }

    /// [`long_date_in`](Self::long_date_in) without the year: "Montag,
    /// 12. Oktober".
    pub fn day_and_month_in(&self, locale: &crate::lang::Locale) -> String {
        let full = self.long_date_in(locale);
        let year = self.year.to_string();
        let cut = full
            .strip_suffix(&year)
            .map(|s| s.trim_end().trim_end_matches(" de").trim_end().to_owned());
        cut.unwrap_or(full)
    }

    /// The dates of this weekend ("Saturday 17 and Sunday 18 October"; on
    /// a Sunday, the one it ends), for the model: told only today's date,
    /// it put "this weekend" on a Wednesday and Thursday.
    ///
    /// The weekend is Saturday and Sunday everywhere: right for Europe and
    /// the Americas where Sailfish phones are sold, wrong where it is
    /// Friday and Saturday (much of the Middle East) or Friday alone.
    pub fn weekend(&self) -> String {
        let today = u8::try_from(self.month)
            .ok()
            .and_then(|m| time::Month::try_from(m).ok())
            .and_then(|m| {
                time::Date::from_calendar_date(self.year, m, u8::try_from(self.day).ok()?).ok()
            });
        let Some(today) = today else {
            return String::new();
        };
        let to_saturday = if self.weekday == 0 {
            -1
        } else {
            6 - i64::from(self.weekday)
        };
        let saturday = today + time::Duration::days(to_saturday);
        let sunday = saturday + time::Duration::days(1);
        if saturday.month() == sunday.month() {
            format!(
                "Saturday {} and Sunday {} {}",
                saturday.day(),
                sunday.day(),
                sunday.month()
            )
        } else {
            format!(
                "Saturday {} {} and Sunday {} {}",
                saturday.day(),
                saturday.month(),
                sunday.day(),
                sunday.month()
            )
        }
    }

    /// For tests: a fixed local time in UTC.
    pub fn fixed_utc(epoch: i64) -> LocalNow {
        let dt = time::OffsetDateTime::from_unix_timestamp(epoch)
            .unwrap_or(time::OffsetDateTime::UNIX_EPOCH);
        LocalNow {
            epoch,
            year: dt.year(),
            month: u32::from(u8::from(dt.month())),
            day: u32::from(dt.day()),
            hour: u32::from(dt.hour()),
            minute: u32::from(dt.minute()),
            weekday: u32::from(dt.weekday().number_days_from_sunday()),
            utc_offset: 0,
            utc: true,
        }
    }
}

// Day names (Sunday first, as `weekday`) and month names in the form a
// date takes (Finnish, Polish and Czech decline the month: "12.
// lokakuuta", "12 października", "12. října").
const DE_DAYS: [&str; 7] = [
    "Sonntag",
    "Montag",
    "Dienstag",
    "Mittwoch",
    "Donnerstag",
    "Freitag",
    "Samstag",
];
const DE_MONTHS: [&str; 12] = [
    "Januar",
    "Februar",
    "März",
    "April",
    "Mai",
    "Juni",
    "Juli",
    "August",
    "September",
    "Oktober",
    "November",
    "Dezember",
];
const FR_DAYS: [&str; 7] = [
    "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi",
];
const FR_MONTHS: [&str; 12] = [
    "janvier",
    "février",
    "mars",
    "avril",
    "mai",
    "juin",
    "juillet",
    "août",
    "septembre",
    "octobre",
    "novembre",
    "décembre",
];
const ES_DAYS: [&str; 7] = [
    "domingo",
    "lunes",
    "martes",
    "miércoles",
    "jueves",
    "viernes",
    "sábado",
];
const ES_MONTHS: [&str; 12] = [
    "enero",
    "febrero",
    "marzo",
    "abril",
    "mayo",
    "junio",
    "julio",
    "agosto",
    "septiembre",
    "octubre",
    "noviembre",
    "diciembre",
];
const IT_DAYS: [&str; 7] = [
    "domenica",
    "lunedì",
    "martedì",
    "mercoledì",
    "giovedì",
    "venerdì",
    "sabato",
];
const IT_MONTHS: [&str; 12] = [
    "gennaio",
    "febbraio",
    "marzo",
    "aprile",
    "maggio",
    "giugno",
    "luglio",
    "agosto",
    "settembre",
    "ottobre",
    "novembre",
    "dicembre",
];
const PT_DAYS: [&str; 7] = [
    "domingo",
    "segunda-feira",
    "terça-feira",
    "quarta-feira",
    "quinta-feira",
    "sexta-feira",
    "sábado",
];
const PT_MONTHS: [&str; 12] = [
    "janeiro",
    "fevereiro",
    "março",
    "abril",
    "maio",
    "junho",
    "julho",
    "agosto",
    "setembro",
    "outubro",
    "novembro",
    "dezembro",
];
const NL_DAYS: [&str; 7] = [
    "zondag",
    "maandag",
    "dinsdag",
    "woensdag",
    "donderdag",
    "vrijdag",
    "zaterdag",
];
const NL_MONTHS: [&str; 12] = [
    "januari",
    "februari",
    "maart",
    "april",
    "mei",
    "juni",
    "juli",
    "augustus",
    "september",
    "oktober",
    "november",
    "december",
];
const SV_DAYS: [&str; 7] = [
    "söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag",
];
const SV_MONTHS: [&str; 12] = [
    "januari",
    "februari",
    "mars",
    "april",
    "maj",
    "juni",
    "juli",
    "augusti",
    "september",
    "oktober",
    "november",
    "december",
];
const FI_DAYS: [&str; 7] = [
    "sunnuntai",
    "maanantai",
    "tiistai",
    "keskiviikko",
    "torstai",
    "perjantai",
    "lauantai",
];
const FI_MONTHS: [&str; 12] = [
    "tammikuuta",
    "helmikuuta",
    "maaliskuuta",
    "huhtikuuta",
    "toukokuuta",
    "kesäkuuta",
    "heinäkuuta",
    "elokuuta",
    "syyskuuta",
    "lokakuuta",
    "marraskuuta",
    "joulukuuta",
];
const NB_DAYS: [&str; 7] = [
    "søndag", "mandag", "tirsdag", "onsdag", "torsdag", "fredag", "lørdag",
];
const NB_MONTHS: [&str; 12] = [
    "januar",
    "februar",
    "mars",
    "april",
    "mai",
    "juni",
    "juli",
    "august",
    "september",
    "oktober",
    "november",
    "desember",
];
const DA_MONTHS: [&str; 12] = [
    "januar",
    "februar",
    "marts",
    "april",
    "maj",
    "juni",
    "juli",
    "august",
    "september",
    "oktober",
    "november",
    "december",
];
const PL_DAYS: [&str; 7] = [
    "niedziela",
    "poniedziałek",
    "wtorek",
    "środa",
    "czwartek",
    "piątek",
    "sobota",
];
const PL_MONTHS: [&str; 12] = [
    "stycznia",
    "lutego",
    "marca",
    "kwietnia",
    "maja",
    "czerwca",
    "lipca",
    "sierpnia",
    "września",
    "października",
    "listopada",
    "grudnia",
];
const CS_DAYS: [&str; 7] = [
    "neděle",
    "pondělí",
    "úterý",
    "středa",
    "čtvrtek",
    "pátek",
    "sobota",
];
const CS_MONTHS: [&str; 12] = [
    "ledna",
    "února",
    "března",
    "dubna",
    "května",
    "června",
    "července",
    "srpna",
    "září",
    "října",
    "listopadu",
    "prosince",
];

/// The system time zone's name ("Europe/Dublin"), from where
/// `/etc/localtime` points in the end (on Sailfish OS through timed's
/// `/var/lib/timed/localtime`).
pub fn zone_name() -> Option<String> {
    let target = std::fs::canonicalize("/etc/localtime").ok()?;
    let s = target.to_string_lossy();
    let i = s.find("zoneinfo/")?;
    Some(s[i + "zoneinfo/".len()..].to_owned()).filter(|z| z.contains('/'))
}

/// `Europe/Dublin` → `Dublin`, `America/New_York` → `New York`.
pub fn zone_city(zone: &str) -> String {
    zone.rsplit('/').next().unwrap_or(zone).replace('_', " ")
}

/// Now, in the system time zone.
pub fn now() -> LocalNow {
    let epoch = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| i64::try_from(d.as_secs()).unwrap_or(0));
    at(epoch)
}

/// `epoch` in the system time zone.
pub fn at(epoch: i64) -> LocalNow {
    let t: libc::time_t = epoch as libc::time_t;
    // SAFETY: localtime_r writes only into `tm`, which we own; a zeroed
    // `struct tm` is a valid value for it to overwrite.
    let mut tm: libc::tm = unsafe { std::mem::zeroed() };
    // SAFETY: both pointers are valid for the duration of the call.
    let ok = unsafe { !libc::localtime_r(&raw const t, &raw mut tm).is_null() };
    if !ok {
        return LocalNow::fixed_utc(epoch);
    }
    let u = |v: libc::c_int| u32::try_from(v).unwrap_or(0);
    LocalNow {
        epoch,
        year: tm.tm_year + 1900,
        month: u(tm.tm_mon + 1),
        day: u(tm.tm_mday),
        hour: u(tm.tm_hour),
        minute: u(tm.tm_min),
        weekday: u(tm.tm_wday),
        utc_offset: tm.tm_gmtoff,
        utc: false,
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::print_stderr, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn zone_city_is_readable() {
        assert_eq!(zone_city("Europe/Dublin"), "Dublin");
        assert_eq!(zone_city("America/New_York"), "New York");
    }

    #[test]
    fn long_date_names_the_day() {
        // 2026-10-07 12:00 UTC, a Wednesday.
        assert_eq!(
            LocalNow::fixed_utc(1_791_374_400).long_date(),
            "Wednesday 7 October 2026"
        );
    }

    #[test]
    fn weekend_dates() {
        let day = 86_400;
        // Wednesday 7 October 2026.
        let wed = 1_791_374_400;
        assert_eq!(
            LocalNow::fixed_utc(wed).weekend(),
            "Saturday 10 and Sunday 11 October"
        );
        assert_eq!(
            LocalNow::fixed_utc(wed + 3 * day).weekend(),
            "Saturday 10 and Sunday 11 October"
        );
        assert_eq!(
            LocalNow::fixed_utc(wed + 4 * day).weekend(),
            "Saturday 10 and Sunday 11 October"
        );
        assert_eq!(
            LocalNow::fixed_utc(wed + 5 * day).weekend(),
            "Saturday 17 and Sunday 18 October"
        );
        // Thursday 29 October: the weekend crosses into November.
        assert_eq!(
            LocalNow::fixed_utc(wed + 22 * day).weekend(),
            "Saturday 31 October and Sunday 1 November"
        );
    }

    #[test]
    fn fixed_and_midnight() {
        // 2026-10-02 18:42:30 UTC, a Friday.
        let n = LocalNow::fixed_utc(1_790_966_550);
        assert_eq!(
            (n.year, n.month, n.day, n.hour, n.minute),
            (2026, 10, 2, 18, 42)
        );
        assert_eq!(n.weekday, 5);
        assert_eq!(n.hhmm(), "18:42");
        assert_eq!(n.midnight(), 1_790_966_550 - (18 * 3600 + 42 * 60 + 30));
    }

    #[test]
    fn long_date_in_the_persons_language() {
        let l = |name: &str| crate::lang::Locale::parse(name).unwrap();
        // Monday 12 October 2026.
        let n = LocalNow::fixed_utc(1_791_806_400);
        assert_eq!(n.long_date_in(&l("de_DE")), "Montag, 12. Oktober 2026");
        assert_eq!(n.long_date_in(&l("fi_FI")), "maanantai 12. lokakuuta 2026");
        assert_eq!(n.long_date_in(&l("es_ES")), "lunes, 12 de octubre de 2026");
        assert_eq!(
            n.long_date_in(&l("pt_PT")),
            "segunda-feira, 12 de outubro de 2026"
        );
        assert_eq!(
            n.long_date_in(&l("pl_PL")),
            "poniedziałek, 12 października 2026"
        );
        assert_eq!(n.long_date_in(&l("cs_CZ")), "pondělí 12. října 2026");
        assert_eq!(n.long_date_in(&l("da_DK")), "mandag 12. oktober 2026");
        assert_eq!(n.long_date_in(&l("en_US")), "Monday 12 October 2026");
        assert_eq!(n.long_date_in(&l("ja_JP")), "Monday 12 October 2026");
        assert_eq!(n.day_and_month_in(&l("de_DE")), "Montag, 12. Oktober");
        assert_eq!(n.day_and_month_in(&l("es_ES")), "lunes, 12 de octubre");
        assert_eq!(n.day_and_month_in(&l("en_GB")), "Monday 12 October");
    }

    /// Runs the ignored test `name` in a child process with `TZ=zone`
    /// (the zone is read once per process, so it cannot change here).
    pub(crate) fn run_in_zone(zone: &str, name: &str) {
        if !std::path::Path::new("/usr/share/zoneinfo")
            .join(zone)
            .exists()
        {
            eprintln!("no zoneinfo for {zone}: skipped");
            return;
        }
        let out = std::process::Command::new(std::env::current_exe().unwrap())
            .args([name, "--exact", "--ignored", "--test-threads=1"])
            .env("TZ", zone)
            .output()
            .unwrap();
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(
            out.status.success() && stdout.contains("1 passed"),
            "{stdout}{}",
            String::from_utf8_lossy(&out.stderr)
        );
    }

    fn utc(y: i32, m: u8, d: u8, h: u8) -> i64 {
        time::Date::from_calendar_date(y, time::Month::try_from(m).unwrap(), d)
            .unwrap()
            .with_hms(h, 0, 0)
            .unwrap()
            .assume_utc()
            .unix_timestamp()
    }

    #[test]
    fn midnight_and_times_across_dst_changes() {
        run_in_zone("Europe/Helsinki", "localtime::tests::dst_in_helsinki");
    }

    #[test]
    #[ignore = "run by midnight_and_times_across_dst_changes with TZ=Europe/Helsinki"]
    fn dst_in_helsinki() {
        // Sunday 25 October 2026: clocks go back at 04:00 EEST (01:00
        // UTC). At 12:00 EET (10:00 UTC), midnight was 13 hours ago:
        // 00:00 EEST, 21:00 UTC the day before.
        let n = at(utc(2026, 10, 25, 10));
        assert_eq!((n.day, n.hour, n.utc_offset), (25, 12, 2 * 3600));
        assert_eq!(n.midnight(), utc(2026, 10, 24, 21));
        // Tomorrow 07:00 is 07:00 EET.
        assert_eq!(n.local_time(1, 7, 0), utc(2026, 10, 26, 5));
        // Saturday 24 October at 20:00 EEST: tomorrow 09:00 is EET.
        let sat = at(utc(2026, 10, 24, 17));
        assert_eq!(sat.local_time(1, 9, 0), utc(2026, 10, 25, 7));
        assert_eq!(sat.local_time(0, 0, 0), utc(2026, 10, 23, 21));
        // Sunday 29 March 2026: clocks go forward at 03:00 EET (01:00
        // UTC). At 12:00 EEST (09:00 UTC), midnight was 00:00 EET.
        let n = at(utc(2026, 3, 29, 9));
        assert_eq!((n.hour, n.utc_offset), (12, 3 * 3600));
        assert_eq!(n.midnight(), utc(2026, 3, 28, 22));
        assert_eq!(n.local_time(1, 0, 0), utc(2026, 3, 29, 21));
        // A month end rolls over: 31 October + 1 day.
        let n = at(utc(2026, 10, 31, 10));
        assert_eq!(n.local_time(1, 0, 0), utc(2026, 10, 31, 22));
    }

    #[test]
    fn libc_path_is_consistent() {
        let n = now();
        assert!(n.month >= 1 && n.month <= 12);
        assert!(n.hour < 24);
    }
}
