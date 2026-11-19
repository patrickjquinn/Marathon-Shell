//! Which internet station is also on FM here: the frequency in its name
//! ("92.5 Phoenix FM"), or the station name FM's RDS sends ("NOVA" for
//! "Radio Nova").

/// The words of a name, lowercase and without accents or punctuation.
pub fn words(name: &str) -> Vec<String> {
    let folded: String = name
        .chars()
        .map(|c| match c {
            'á' | 'à' | 'â' | 'ä' | 'Á' | 'À' | 'Â' | 'Ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' | 'É' | 'È' | 'Ê' | 'Ë' => 'e',
            'í' | 'ì' | 'î' | 'ï' | 'Í' | 'Ì' | 'Î' | 'Ï' => 'i',
            'ó' | 'ò' | 'ô' | 'ö' | 'Ó' | 'Ò' | 'Ô' | 'Ö' => 'o',
            'ú' | 'ù' | 'û' | 'ü' | 'Ú' | 'Ù' | 'Û' | 'Ü' => 'u',
            c if c.is_alphanumeric() || c == '.' => c,
            _ => ' ',
        })
        .collect();
    folded
        .to_lowercase()
        .split_whitespace()
        .map(|w| w.trim_matches('.').to_owned())
        .filter(|w| !w.is_empty())
        .collect()
}

/// Words that say nothing about which station it is.
fn generic(word: &str) -> bool {
    matches!(word, "fm" | "radio" | "the" | "am" | "dab")
}

/// The FM frequency (10 kHz) written in a name: "96.4" or "FM104" (104.0
/// to 104.9 cannot be told apart, so only the exact "104.x" counts).
pub fn frequency_in(name: &str) -> Option<u16> {
    words(name).iter().find_map(|w| {
        let (whole, frac) = w.split_once('.')?;
        if frac.len() != 1 {
            return None;
        }
        let khz10: u16 = whole.parse::<u16>().ok()? * 100 + frac.parse::<u16>().ok()? * 10;
        (8750..=10800).contains(&khz10).then_some(khz10)
    })
}

/// Whether an RDS station name (`ps`, eight characters) names `station`:
/// each telling word of it is a word of the station's name, or two or three
/// of them run together (`RTElyric` for "RTÉ lyric fm").
pub fn rds_names(ps: &str, station: &str) -> bool {
    let ps_words: Vec<String> = words(ps).into_iter().filter(|w| !generic(w)).collect();
    if ps_words.is_empty() {
        return false;
    }
    let name = words(station);
    let joined: Vec<String> = (2..=3)
        .flat_map(|n| name.windows(n).map(<[String]>::concat))
        .collect();
    ps_words
        .iter()
        .all(|w| name.contains(w) || joined.contains(w))
}

/// An RDS name as a station's name: "SUNSHINE" as "Sunshine", but short
/// all-capital words ("RTE", "FM") are acronyms and stay.
pub fn title_case(ps: &str) -> String {
    ps.split_whitespace()
        .map(|w| {
            let letters = w.chars().filter(|c| c.is_alphabetic()).count();
            if letters > 3 && w.chars().all(|c| !c.is_lowercase()) {
                let mut chars = w.chars();
                chars.next().map_or_else(String::new, |first| {
                    first
                        .to_uppercase()
                        .chain(chars.flat_map(char::to_lowercase))
                        .collect()
                })
            } else {
                w.to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
        .trim_end_matches('.')
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_frequency_in_a_name_is_found() {
        assert_eq!(frequency_in("92.5 Phoenix FM"), Some(9250));
        assert_eq!(frequency_in("Liffey Sound 96.4 FM"), Some(9640));
        assert_eq!(frequency_in("Dublin's FM104"), None);
        assert_eq!(frequency_in("Radio 1.5"), None);
    }

    #[test]
    fn rds_names_match_stations() {
        assert!(rds_names("  NOVA  ", "Radio Nova"));
        assert!(rds_names("FM104", "Dublin's FM104"));
        assert!(rds_names("RTE 2FM", "RTÉ 2FM"));
        assert!(!rds_names("NOVA", "Newstalk Ireland"));
        assert!(!rds_names("  FM    ", "Any FM"));
        assert!(rds_names("RTElyric", "RTÉ lyric fm"));
        assert!(rds_names("98FM", "Dublin's 98FM"));
        assert!(!rds_names("CLASSIC.", "Onic Classical"));
    }

    #[test]
    fn rds_names_read_as_names() {
        assert_eq!(title_case("SUNSHINE"), "Sunshine");
        assert_eq!(title_case("RNA LIFE"), "RNA Life");
        assert_eq!(title_case("RTE 2FM"), "RTE 2FM");
        assert_eq!(title_case("CLASSIC."), "Classic");
        assert_eq!(title_case("Today FM"), "Today FM");
    }
}
