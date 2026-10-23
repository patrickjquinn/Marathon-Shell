//! The keyboard's words: completions as a word is typed, autocorrection,
//! learnt words, phrase completions and address suggestions. The language's
//! Hunspell dictionary (spellbook) loads on first use and every lookup runs on
//! the blocking pool; QML reads the predictions once they are in.

use std::cmp::Reverse;
use std::collections::HashMap;
use std::fmt::Write as _;
use std::fs::OpenOptions;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QStringList};

use crate::log;

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qstringlist.h");
        type QStringList = cxx_qt_lib::QStringList;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(
            QStringList,
            cached_predictions,
            cxx_name = "cachedPredictions",
            READ,
            NOTIFY
        )]
        #[qproperty(
            QString,
            last_prediction_prefix,
            cxx_name = "lastPredictionPrefix",
            READ,
            NOTIFY
        )]
        type Dictionary = super::DictionaryRust;

        /// The predictions for `prefix` so far; cachedPredictions has the
        /// rest once they are in.
        #[qinvokable]
        fn predict(self: Pin<&mut Dictionary>, prefix: &QString) -> QStringList;
        /// What usually follows the last words typed.
        #[qinvokable]
        #[cxx_name = "getPhraseCompletions"]
        fn phrase_completions(self: &Dictionary, context: &QString) -> QStringList;
        #[qinvokable]
        #[cxx_name = "learnWord"]
        fn learn_word(self: &Dictionary, word: &QString);
        /// The word as autocorrection would leave it, in the capitals typed.
        #[qinvokable]
        fn correct(self: &Dictionary, word: &QString) -> QString;
        /// A Hunspell name, "en_US": the dictionary loads on next use.
        #[qinvokable]
        #[cxx_name = "setLanguage"]
        fn set_language(self: &Dictionary, language: &QString);
    }

    extern "RustQt" {
        #[qobject]
        type DomainSuggestions = super::DomainSuggestionsRust;

        #[qinvokable]
        #[cxx_name = "getSuggestions"]
        fn suggestions(self: &DomainSuggestions, text: &QString, is_email: bool) -> QStringList;
        #[qinvokable]
        #[cxx_name = "shouldShowDomainSuggestions"]
        fn should_show(
            self: &DomainSuggestions,
            text: &QString,
            is_email: bool,
            is_url: bool,
        ) -> bool;
    }

    impl cxx_qt::Threading for Dictionary {}
}

use qobject::Dictionary;

const PREDICTIONS: usize = 5;
const DICTIONARIES: [&str; 3] = [
    "/usr/share/hunspell",
    "/usr/share/myspell/dicts",
    "/usr/local/share/hunspell",
];

const TYPOS: &[(&str, &str)] = &[
    ("teh", "the"),
    ("adn", "and"),
    ("youre", "you're"),
    ("dont", "don't"),
    ("cant", "can't"),
    ("wont", "won't"),
    ("didnt", "didn't"),
    ("doesnt", "doesn't"),
    ("hasnt", "hasn't"),
    ("havent", "haven't"),
    ("isnt", "isn't"),
    ("wasnt", "wasn't"),
    ("werent", "weren't"),
    ("shouldnt", "shouldn't"),
    ("wouldnt", "wouldn't"),
    ("couldnt", "couldn't"),
    ("thats", "that's"),
    ("whats", "what's"),
    ("hes", "he's"),
    ("shes", "she's"),
    ("its", "it's"),
    ("im", "I'm"),
    ("youve", "you've"),
    ("theyve", "they've"),
    ("weve", "we've"),
    ("ive", "I've"),
    ("recieve", "receive"),
    ("beleive", "believe"),
    ("neccessary", "necessary"),
    ("seperate", "separate"),
    ("definately", "definitely"),
    ("occured", "occurred"),
    ("begining", "beginning"),
    ("tommorrow", "tomorrow"),
    ("untill", "until"),
    ("alot", "a lot"),
];

const PHRASES: &[(&str, &[&str])] = &[
    ("how are", &["you", "you doing", "things"]),
    ("how is", &["it going", "everything", "your day"]),
    ("what are", &["you doing", "you up to", "your plans"]),
    ("what is", &["up", "going on", "your name"]),
    ("where are", &["you", "we going", "we meeting"]),
    ("where is", &["it", "that", "everyone"]),
    ("when are", &["you coming", "we meeting", "you free"]),
    ("when is", &["it", "the meeting", "your birthday"]),
    ("i am", &["here", "coming", "on my way", "good", "fine"]),
    ("i will", &["be there", "call you", "let you know", "do it"]),
    ("i have", &["to go", "a question", "an idea", "time"]),
    ("i think", &["so", "that", "it's good", "we should"]),
    ("i need", &["to", "help", "more time", "your help"]),
    ("i want", &["to", "that", "it", "one"]),
    ("i hope", &["so", "you're well", "it works", "to see you"]),
    ("i love", &["you", "it", "this", "that"]),
    ("i like", &["it", "that", "this", "your idea"]),
    ("can you", &["help", "do it", "send me", "call me"]),
    ("can i", &["help", "ask you", "call you", "come"]),
    ("do you", &["know", "have", "want", "think"]),
    ("did you", &["get it", "see that", "hear", "know"]),
    ("are you", &["there", "coming", "ok", "sure", "free"]),
    ("is it", &["ok", "possible", "working", "done"]),
    ("let me", &["know", "think", "check", "see"]),
    ("thank you", &["so much", "very much", "for everything"]),
    (
        "thanks for",
        &["your help", "letting me know", "everything"],
    ),
    ("looking forward", &["to it", "to hearing", "to seeing you"]),
    ("nice to", &["meet you", "see you", "hear from you"]),
    ("have a", &["good day", "nice day", "great day", "good one"]),
    ("see you", &["later", "soon", "tomorrow", "there"]),
    ("talk to", &["you later", "you soon", "me"]),
    ("on my", &["way", "phone", "computer", "mind"]),
    ("be right", &["back", "there", "over"]),
    ("going to", &["be", "do", "the", "try"]),
    ("want to", &["go", "do", "see", "try", "know"]),
    ("need to", &["go", "do", "talk", "know", "finish"]),
    ("have to", &["go", "do", "leave", "work"]),
    ("got to", &["go", "run", "do"]),
    ("good to", &["know", "see you", "hear"]),
    ("great to", &["see you", "hear", "meet you"]),
    ("happy to", &["help", "hear", "see you", "know"]),
    ("sorry for", &["the delay", "the wait", "bothering you"]),
    ("sorry i", &["missed", "forgot", "can't", "didn't"]),
    ("no problem", &["at all", "happy to help"]),
    ("sounds good", &["to me", "let's do it"]),
    ("that sounds", &["good", "great", "perfect", "fun"]),
    ("that's a", &["good idea", "great idea", "good point"]),
    ("that's great", &["news", "to hear"]),
    ("the best", &["way", "thing", "option", "part"]),
    ("a lot", &["of", "more", "better"]),
    ("of course", &["not", "I will", "you can"]),
    ("by the", &["way", "time", "end"]),
    ("at the", &["moment", "end", "same time"]),
    ("in the", &["morning", "afternoon", "evening", "end"]),
    ("on the", &["way", "phone", "other hand"]),
];

pub struct DictionaryRust {
    cached_predictions: QStringList,
    last_prediction_prefix: QString,
    engine: Arc<Mutex<Engine>>,
    // The newest prediction asked for; older ones still queued are skipped.
    asked: Arc<AtomicU64>,
    // A word typed so far and its correction, made with its predictions.
    correction: Option<(String, String)>,
}

impl Default for DictionaryRust {
    fn default() -> Self {
        let config = marathon_rt::dirs::config().join("marathon-os");
        Self {
            cached_predictions: QStringList::default(),
            last_prediction_prefix: QString::default(),
            engine: Arc::new(Mutex::new(Engine::new(config, "en_US"))),
            asked: Arc::default(),
            correction: None,
        }
    }
}

fn list<S: AsRef<str>>(items: &[S]) -> QStringList {
    items.iter().map(|s| QString::from(s.as_ref())).collect()
}

impl Dictionary {
    fn engine(&self) -> std::sync::MutexGuard<'_, Engine> {
        self.engine.lock().unwrap_or_else(|_| std::process::abort())
    }

    fn predict(mut self: Pin<&mut Self>, prefix: &QString) -> QStringList {
        if prefix.is_empty() {
            return QStringList::default();
        }
        if self.last_prediction_prefix != *prefix {
            set!(
                self,
                last_prediction_prefix,
                last_prediction_prefix_changed,
                prefix.clone()
            );
            set!(
                self,
                cached_predictions,
                cached_predictions_changed,
                QStringList::default()
            );
            let (engine, asked, qt) = (
                Arc::clone(&self.engine),
                Arc::clone(&self.asked),
                self.qt_thread(),
            );
            let ask = asked.fetch_add(1, Ordering::Relaxed) + 1;
            let prefix = prefix.to_string();
            crate::io::spawn(async move {
                let made = blocking::unblock(move || {
                    let mut engine = engine.lock().unwrap_or_else(|_| std::process::abort());
                    (asked.load(Ordering::Relaxed) == ask).then(|| {
                        (
                            engine.completions(&prefix),
                            engine.correction(&prefix),
                            prefix,
                        )
                    })
                });
                let Some((completions, correction, prefix)) = made.await else {
                    return;
                };
                qt.queue(move |mut obj| {
                    if obj.last_prediction_prefix.to_string() == prefix {
                        obj.as_mut().rust_mut().correction =
                            correction.map(|c| (prefix.to_lowercase(), c));
                        set!(
                            obj,
                            cached_predictions,
                            cached_predictions_changed,
                            list(&completions)
                        );
                    }
                })
                .ok();
            });
        }
        self.cached_predictions.clone()
    }

    #[allow(clippy::unused_self, reason = "an invokable")]
    fn phrase_completions(&self, context: &QString) -> QStringList {
        list(phrases(&context.to_string()))
    }

    fn learn_word(&self, word: &QString) {
        let word = word.to_string();
        if word.chars().count() < 2 {
            return;
        }
        let engine = Arc::clone(&self.engine);
        crate::io::spawn(async move {
            blocking::unblock(move || {
                engine
                    .lock()
                    .unwrap_or_else(|_| std::process::abort())
                    .learn(&word);
            })
            .await;
        });
    }

    fn correct(&self, word: &QString) -> QString {
        let typed = word.to_string();
        let lower = typed.to_lowercase();
        let correction = TYPOS
            .iter()
            .find(|(typo, _)| *typo == lower)
            .map(|(_, c)| *c)
            .or_else(|| {
                let (word, correction) = self.correction.as_ref()?;
                (*word == lower).then_some(correction.as_str())
            });
        correction.map_or_else(|| word.clone(), |c| QString::from(&with_case_of(&typed, c)))
    }

    fn set_language(&self, language: &QString) {
        self.engine().set_language(&language.to_string());
    }
}

/// A correction keeps the capitals of the word typed: Teh, The; TEH, THE.
fn with_case_of(typed: &str, correction: &str) -> String {
    if typed.chars().count() > 1 && typed == typed.to_uppercase() && typed != typed.to_lowercase() {
        return correction.to_uppercase();
    }
    let mut chars = correction.chars();
    match (
        typed.chars().next().is_some_and(char::is_uppercase),
        chars.next(),
    ) {
        (true, Some(first)) => first.to_uppercase().chain(chars).collect(),
        _ => correction.to_owned(),
    }
}

fn phrases(context: &str) -> &'static [&'static str] {
    let key = context.trim().to_lowercase();
    let words: Vec<&str> = key.split_whitespace().collect();
    let last_two = words
        .get(words.len().saturating_sub(2)..)
        .map(|w| w.join(" "))
        .unwrap_or_default();
    PHRASES
        .iter()
        .find(|(k, _)| *k == key)
        .or_else(|| {
            PHRASES
                .iter()
                .find(|(k, _)| words.len() >= 2 && *k == last_two)
        })
        .map_or(&[], |(_, p)| p)
}

struct Engine {
    config: PathBuf,
    language: String,
    loaded: Option<String>,
    spell: Option<spellbook::Dictionary>,
    // The dictionary's stems and the words learnt, lowercased and sorted.
    words: Vec<String>,
    frequencies: HashMap<String, u32>,
    unsaved: u32,
}

impl Engine {
    fn new(config: PathBuf, language: &str) -> Self {
        Self {
            config,
            language: language.to_owned(),
            loaded: None,
            spell: None,
            words: Vec::new(),
            frequencies: HashMap::new(),
            unsaved: 0,
        }
    }

    fn user_words(&self) -> PathBuf {
        self.config.join("keyboard_user_dictionary.txt")
    }

    fn frequency_file(&self) -> PathBuf {
        self.config.join("keyboard_word_frequencies.txt")
    }

    fn set_language(&mut self, language: &str) {
        language.clone_into(&mut self.language);
    }

    fn ensure_loaded(&mut self) {
        if self.loaded.as_deref() == Some(self.language.as_str()) {
            return;
        }
        self.loaded = Some(self.language.clone());
        let (spell, mut words) = match find_dictionary(&self.language) {
            Some(base) => load(&base),
            None => (None, Vec::new()),
        };
        self.spell = spell;
        if self.frequencies.is_empty() {
            let text = std::fs::read_to_string(self.frequency_file()).unwrap_or_default();
            self.frequencies = text
                .lines()
                .filter_map(|l| l.split_once('\t'))
                .filter_map(|(w, n)| Some((w.to_owned(), n.trim().parse().ok()?)))
                .collect();
        }
        for word in std::fs::read_to_string(self.user_words())
            .unwrap_or_default()
            .lines()
            .map(str::trim)
            .filter(|w| !w.is_empty())
        {
            if let Some(spell) = &mut self.spell {
                spell.add(word).ok();
            }
            words.push(word.to_lowercase());
        }
        words.sort_unstable();
        words.dedup();
        self.words = words;
    }

    /// The known words starting with `prefix`, the most used and then the
    /// shortest first.
    fn completions(&mut self, prefix: &str) -> Vec<String> {
        self.ensure_loaded();
        let prefix = prefix.to_lowercase();
        let start = self.words.partition_point(|w| w.as_str() < prefix.as_str());
        let mut hits: Vec<&String> = self
            .words
            .iter()
            .skip(start)
            .take_while(|w| w.starts_with(&prefix))
            .collect();
        hits.sort_by_key(|w| {
            (
                Reverse(self.frequencies.get(w.as_str()).copied().unwrap_or(0)),
                w.len(),
            )
        });
        hits.into_iter().take(PREDICTIONS).cloned().collect()
    }

    /// The dictionary's nearest word to a misspelt one, at most two edits away.
    fn correction(&mut self, word: &str) -> Option<String> {
        let spell = self.spell.as_ref()?;
        let lower = word.to_lowercase();
        if lower.chars().count() < 3 || spell.check(word) || spell.check(&lower) {
            return None;
        }
        let mut suggestions = Vec::new();
        spell.suggest(&lower, &mut suggestions);
        suggestions
            .into_iter()
            .find(|s| levenshtein(&lower, &s.to_lowercase()) <= 2)
    }

    fn learn(&mut self, word: &str) {
        self.ensure_loaded();
        let lower = word.to_lowercase();
        if let Err(at) = self.words.binary_search(&lower) {
            self.words.insert(at, lower.clone());
            if let Some(spell) = &mut self.spell {
                spell.add(word).ok();
            }
            let path = self.user_words();
            let appended = std::fs::create_dir_all(&self.config)
                .and_then(|()| OpenOptions::new().create(true).append(true).open(&path))
                .and_then(|mut file| writeln!(file, "{word}"));
            if let Err(e) = appended {
                log::warn("words", format_args!("{}: {e}", path.display()));
            }
        }
        *self.frequencies.entry(lower).or_default() += 1;
        self.unsaved += 1;
        if self.unsaved >= 10 {
            self.unsaved = 0;
            let text = self
                .frequencies
                .iter()
                .fold(String::new(), |mut text, (w, n)| {
                    writeln!(text, "{w}\t{n}").ok();
                    text
                });
            if let Err(e) = std::fs::write(self.frequency_file(), text) {
                log::warn("words", format_args!("saving frequencies: {e}"));
            }
        }
    }
}

/// `<dir>/<language>` with its .aff and .dic, or any of the language's
/// regions (`en_GB` for `en_US`).
fn find_dictionary(language: &str) -> Option<PathBuf> {
    let dirs = DICTIONARIES.iter().map(Path::new);
    dirs.clone()
        .map(|d| d.join(language))
        .find(|b| b.with_extension("dic").exists())
        .or_else(|| {
            let code = language.get(..2)?;
            dirs.filter_map(|d| std::fs::read_dir(d).ok())
                .flatten()
                .flatten()
                .map(|e| e.path())
                .find(|p| {
                    p.extension().is_some_and(|e| e == "dic")
                        && p.file_name()
                            .is_some_and(|n| n.to_string_lossy().starts_with(code))
                })
                .map(|p| p.with_extension(""))
        })
}

/// Hunspell files are UTF-8 or, in older dictionaries, ISO 8859-1.
fn text(path: &Path) -> Option<String> {
    let bytes = std::fs::read(path).ok()?;
    Some(
        String::from_utf8(bytes)
            .unwrap_or_else(|e| e.into_bytes().iter().map(|&b| char::from(b)).collect()),
    )
}

fn load(base: &Path) -> (Option<spellbook::Dictionary>, Vec<String>) {
    let (Some(aff), Some(dic)) = (
        text(&base.with_extension("aff")),
        text(&base.with_extension("dic")),
    ) else {
        return (None, Vec::new());
    };
    let words = dic
        .lines()
        .skip(1)
        .filter_map(|l| l.split('/').next().map(str::trim))
        .filter(|w| (3..=20).contains(&w.chars().count()))
        .map(str::to_lowercase)
        .collect();
    let spell = spellbook::Dictionary::new(&aff, &dic)
        .map_err(|e| log::warn("words", format_args!("{}: {e}", base.display())))
        .ok();
    (spell, words)
}

fn levenshtein(a: &str, b: &str) -> usize {
    let b: Vec<char> = b.chars().collect();
    let mut previous: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.chars().enumerate() {
        let mut current = vec![i + 1];
        for (j, cb) in b.iter().enumerate() {
            let replace = previous[j] + usize::from(ca != *cb);
            current.push(replace.min(previous[j + 1] + 1).min(current[j] + 1));
        }
        previous = current;
    }
    previous[b.len()]
}

#[derive(Default)]
pub struct DomainSuggestionsRust;

const TLDS: [&str; 20] = [
    "com", "org", "net", "edu", "gov", "co.uk", "co", "io", "app", "dev", "uk", "ca", "au", "de",
    "fr", "jp", "cn", "in", "br", "ru",
];
const MAIL_DOMAINS: [&str; 9] = [
    "gmail.com",
    "outlook.com",
    "yahoo.com",
    "hotmail.com",
    "icloud.com",
    "protonmail.com",
    "me.com",
    "live.com",
    "msn.com",
];

impl qobject::DomainSuggestions {
    #[allow(clippy::unused_self, reason = "an invokable")]
    fn suggestions(&self, text: &QString, is_email: bool) -> QStringList {
        list(&domains(&text.to_string().to_lowercase(), is_email))
    }

    #[allow(clippy::unused_self, reason = "an invokable")]
    fn should_show(&self, text: &QString, is_email: bool, is_url: bool) -> bool {
        let text = text.to_string();
        let long = text.chars().count() >= 2;
        !text.is_empty()
            && ((is_email && (text.contains('@') || long))
                || (!is_email && is_url && (text.contains('.') || (long && !text.contains("://")))))
    }
}

/// Up to three: the mail domains for an address, the endings for a web one.
fn domains(text: &str, is_email: bool) -> Vec<String> {
    let long = text.chars().count() >= 2;
    let found: Vec<String> = if is_email {
        match text.split_once('@') {
            Some((user, domain)) if !domain.contains('@') => MAIL_DOMAINS
                .iter()
                .filter(|d| d.starts_with(domain) && **d != domain)
                .map(|d| format!("{user}@{d}"))
                .collect(),
            None if long => MAIL_DOMAINS.iter().map(|d| format!("{text}@{d}")).collect(),
            _ => Vec::new(),
        }
    } else if let Some((host, ending)) = text.rsplit_once('.') {
        TLDS.iter()
            .filter(|t| t.starts_with(ending) && **t != ending)
            .map(|t| format!("{host}.{t}"))
            .collect()
    } else if long && !text.contains("://") {
        TLDS.iter().map(|t| format!("{text}.{t}")).collect()
    } else {
        Vec::new()
    };
    found.into_iter().take(3).collect()
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    #[test]
    fn corrections_keep_the_capitals_typed() {
        assert_eq!(with_case_of("Teh", "the"), "The");
        assert_eq!(with_case_of("TEH", "the"), "THE");
        assert_eq!(with_case_of("teh", "the"), "the");
        assert_eq!(with_case_of("Im", "I'm"), "I'm");
    }

    #[test]
    fn completions_rank_learnt_words_first() {
        let dir = tempfile::tempdir().unwrap();
        let mut engine = Engine::new(dir.path().join("config"), "xx_XX");
        engine.learn("hello");
        engine.learn("help");
        engine.learn("helicopter");
        engine.learn("helicopter");
        assert_eq!(engine.completions("Hel"), ["helicopter", "help", "hello"]);
        assert_eq!(
            std::fs::read_to_string(engine.user_words()).unwrap(),
            "hello\nhelp\nhelicopter\n"
        );
        let mut again = Engine::new(dir.path().join("config"), "xx_XX");
        assert_eq!(again.completions("he").len(), 3);
    }

    #[test]
    fn a_misspelling_gets_the_nearest_word() {
        let dir = tempfile::tempdir().unwrap();
        let base = dir.path().join("xx_XX");
        std::fs::write(
            base.with_extension("aff"),
            "SET UTF-8\nTRY esianrtolcdugmphbyfvkwz\n",
        )
        .unwrap();
        std::fs::write(base.with_extension("dic"), "3\nhello\nhelp\nreceive\n").unwrap();
        let mut engine = Engine::new(dir.path().join("config"), "xx_XX");
        engine.loaded = Some("xx_XX".into());
        (engine.spell, engine.words) = load(&base);
        assert_eq!(engine.correction("recieve").as_deref(), Some("receive"));
        assert_eq!(engine.correction("hello"), None);
        assert_eq!(engine.completions("he"), ["help", "hello"]);
    }

    #[test]
    fn phrases_follow_the_last_two_words() {
        assert_eq!(phrases("How are"), ["you", "you doing", "things"]);
        assert_eq!(phrases("so where is"), ["it", "that", "everyone"]);
        assert_eq!(phrases("nothing"), <&[&str]>::default());
    }

    #[test]
    fn addresses_get_their_endings() {
        assert_eq!(domains("jo@g", true), ["jo@gmail.com"]);
        assert_eq!(
            domains("jo", true),
            ["jo@gmail.com", "jo@outlook.com", "jo@yahoo.com"]
        );
        assert_eq!(
            domains("example.c", false),
            ["example.com", "example.co.uk", "example.co"]
        );
        assert_eq!(domains("https://x", false), Vec::<String>::new());
    }

    #[test]
    fn edits_are_counted() {
        assert_eq!(levenshtein("recieve", "receive"), 2);
        assert_eq!(levenshtein("", "abc"), 3);
    }
}
