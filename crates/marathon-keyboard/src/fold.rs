//! The form words are matched in: lowercase, unaccented, without apostrophes
//! or hyphens, so "dont" finds "don't" and "cafe" finds "café".

pub fn fold(word: &str) -> String {
    word.chars().filter_map(fold_char).collect()
}

pub fn fold_char(c: char) -> Option<char> {
    let c = c.to_lowercase().next().unwrap_or(c);
    Some(match c {
        '\'' | '’' | '-' | '.' => return None,
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' | 'ā' | 'ă' | 'ą' => 'a',
        'ç' | 'ć' | 'č' | 'ĉ' => 'c',
        'ď' | 'đ' | 'ð' => 'd',
        'è' | 'é' | 'ê' | 'ë' | 'ē' | 'ė' | 'ę' | 'ě' => 'e',
        'ğ' | 'ģ' => 'g',
        'ì' | 'í' | 'î' | 'ï' | 'ī' | 'į' | 'ı' => 'i',
        'ķ' => 'k',
        'ł' | 'ľ' | 'ļ' | 'ĺ' => 'l',
        'ñ' | 'ń' | 'ň' | 'ņ' => 'n',
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' | 'ø' | 'ō' | 'ő' => 'o',
        'ř' | 'ŕ' => 'r',
        'ś' | 'š' | 'ş' | 'ș' => 's',
        'ť' | 'ţ' | 'ț' | 'þ' => 't',
        'ù' | 'ú' | 'û' | 'ü' | 'ū' | 'ů' | 'ű' | 'ų' => 'u',
        'ý' | 'ÿ' => 'y',
        'ź' | 'ż' | 'ž' => 'z',
        c => c,
    })
}

#[cfg(test)]
mod tests {
    use super::fold;

    #[test]
    fn folding_drops_case_accents_and_apostrophes() {
        assert_eq!(fold("Don't"), "dont");
        assert_eq!(fold("café"), "cafe");
        assert_eq!(fold("I'm"), "im");
        assert_eq!(fold("e-mail"), "email");
    }
}
