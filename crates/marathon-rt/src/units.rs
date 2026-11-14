//! Weather units: the choice in Settings > Date and time, and for
//! Automatic the custom of the time zone's country.

use std::path::Path;

/// °F with inches of rain, and mph.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct Units {
    pub fahrenheit: bool,
    pub miles_per_hour: bool,
}

impl Units {
    /// `choice` is "metric", "imperial" or anything else for Automatic.
    pub fn resolve(choice: &str, zone: &str) -> Units {
        match choice {
            "metric" => Units::default(),
            "imperial" => Units {
                fahrenheit: true,
                miles_per_hour: true,
            },
            _ => {
                let table =
                    std::fs::read_to_string("/usr/share/zoneinfo/zone.tab").unwrap_or_default();
                Units::for_country(country(&table, zone).unwrap_or_default())
            }
        }
    }

    /// What Settings holds and the system's zone, for a daemon.
    pub fn current() -> Units {
        let conf = crate::dirs::config().join("Marathon OS/Marathon Shell.conf");
        Units::resolve(&saved_choice(&conf), &local_zone())
    }

    /// Fahrenheit in the United States, Liberia and Myanmar; mph there and
    /// in the United Kingdom.
    fn for_country(country: &str) -> Units {
        let fahrenheit = matches!(country, "US" | "LR" | "MM");
        Units {
            fahrenheit,
            miles_per_hour: fahrenheit || country == "GB",
        }
    }
}

/// The zone `/etc/localtime` names, else `TZ`'s.
pub fn local_zone() -> String {
    let target = std::fs::read_link("/etc/localtime").unwrap_or_default();
    let target = target.to_string_lossy();
    target.split_once("zoneinfo/").map_or_else(
        || {
            std::env::var("TZ")
                .unwrap_or_default()
                .trim_start_matches(':')
                .to_owned()
        },
        |(_, z)| z.to_owned(),
    )
}

/// The country `zone.tab` gives `zone`.
fn country<'a>(table: &'a str, zone: &str) -> Option<&'a str> {
    table
        .lines()
        .filter(|l| !l.starts_with('#'))
        .map(|l| l.split('\t'))
        .find_map(|mut f| {
            let cc = f.next()?;
            (f.nth(1)? == zone).then_some(cc)
        })
}

/// `units` in the shell settings' `[system]` group.
fn saved_choice(conf: &Path) -> String {
    let text = std::fs::read_to_string(conf).unwrap_or_default();
    text.lines()
        .skip_while(|l| l.trim() != "[system]")
        .skip(1)
        .take_while(|l| !l.starts_with('['))
        .find_map(|l| l.strip_prefix("units="))
        .map_or_default(|v| v.trim().trim_matches('"').to_owned())
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    const TABLE: &str = "# comment\nIE\t+5320-00615\tEurope/Dublin\nUS\t+404251-0740023\tAmerica/New_York\tEastern (most areas)\nGB\t+513030-0000731\tEurope/London\n";

    #[test]
    fn automatic_follows_the_zone_s_country() {
        assert_eq!(country(TABLE, "Europe/Dublin"), Some("IE"));
        assert_eq!(country(TABLE, "America/New_York"), Some("US"));
        assert_eq!(country(TABLE, "UTC"), None);
        assert_eq!(Units::for_country("IE"), Units::default());
        assert_eq!(Units::for_country(""), Units::default());
        assert!(Units::for_country("US").fahrenheit);
        let uk = Units::for_country("GB");
        assert!(!uk.fahrenheit && uk.miles_per_hour);
    }

    #[test]
    fn a_choice_overrides_the_zone() {
        assert_eq!(
            Units::resolve("metric", "America/New_York"),
            Units::default()
        );
        let imperial = Units::resolve("imperial", "Europe/Dublin");
        assert!(imperial.fahrenheit && imperial.miles_per_hour);
    }

    #[test]
    fn the_choice_is_read_from_the_system_group() {
        let dir = std::env::temp_dir().join(format!("marathon-rt-units-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let conf = dir.join("Marathon Shell.conf");
        std::fs::write(
            &conf,
            "[audio]\nunits=imperial\n\n[system]\ntimeFormat=24h\nunits=metric\n",
        )
        .unwrap();
        assert_eq!(saved_choice(&conf), "metric");
        assert_eq!(saved_choice(&dir.join("missing")), "");
        std::fs::remove_dir_all(&dir).unwrap();
    }
}
