//! The keyboard's words, from marathon-keyboard: suggestions as a word is
//! tapped, the word a swipe spells, what usually comes next, and what this
//! person types, learnt. A language's word list loads off the GUI thread;
//! suggestions for each letter are worked out on the blocking pool and land
//! in `suggestions` once in.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{QString, QStringList};
use marathon_keyboard::history::History;
use marathon_keyboard::layout::Layout;
use marathon_keyboard::lexicon::Lexicon;
use marathon_keyboard::Engine;

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
        #[qproperty(QStringList, suggestions, READ, NOTIFY)]
        #[qproperty(QString, correction, READ, NOTIFY)]
        #[qproperty(QString, suggested_for, cxx_name = "suggestedFor", READ, NOTIFY)]
        type Dictionary = super::DictionaryRust;

        /// Works out the suggestions for `typed`, tapped at `taps` ("x,y;x,y"
        /// in the keyboard's pixels) after the word `before`: `suggestions`,
        /// the likeliest first, and `correction`, what a space should leave,
        /// once in.
        #[qinvokable]
        fn suggest(self: Pin<&mut Dictionary>, typed: &QString, taps: &QString, before: &QString);
        /// What a space should leave for `typed`: the correction, or `typed`.
        #[qinvokable]
        #[cxx_name = "correctionFor"]
        fn correction_for(
            self: &Dictionary,
            typed: &QString,
            taps: &QString,
            before: &QString,
        ) -> QString;
        /// The words a swipe through `points` ("x,y;x,y") could be.
        #[qinvokable]
        fn swipe(self: &Dictionary, points: &QString, before: &QString) -> QStringList;
        #[qinvokable]
        #[cxx_name = "nextWords"]
        fn next_words(self: &Dictionary, before: &QString) -> QStringList;
        /// `word` was typed after `before` (empty at a sentence's start).
        #[qinvokable]
        fn learn(self: &Dictionary, before: &QString, word: &QString);
        /// The letter keys: "q x y;w x y;..." their centres in the keyboard's
        /// pixels, and a letter key's width.
        #[qinvokable]
        #[cxx_name = "setKeys"]
        fn set_keys(self: &Dictionary, keys: &QString, pitch: f64);
        /// A layout's dictionary name, "en_US": its words load in the background.
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

const WORD_LISTS: &str = "/usr/share/marathon/keyboard";
const HUNSPELL: [&str; 3] = [
    "/usr/share/hunspell",
    "/usr/share/myspell/dicts",
    "/usr/local/share/hunspell",
];
const SAVE_EVERY: u32 = 5;

struct State {
    engine: Engine,
    language: String,
    // Whether `language`'s words are in `engine`.
    loaded: bool,
    config: PathBuf,
    unsaved: u32,
}

impl State {
    fn load(&mut self) {
        let lexicon = Lexicon::parse(&word_list(&self.language));
        let history = History::parse(&history_text(&self.config), &lexicon);
        self.install(lexicon, history);
    }

    fn install(&mut self, lexicon: Lexicon, history: History) {
        if self.unsaved > 0 {
            self.save();
        }
        self.engine.lexicon = lexicon;
        self.engine.history = history;
        self.loaded = true;
    }

    fn history_file(&self) -> PathBuf {
        self.config.join("keyboard_history.txt")
    }

    fn save(&mut self) {
        self.unsaved = 0;
        let path = self.history_file();
        let written = std::fs::create_dir_all(&self.config)
            .and_then(|()| std::fs::write(&path, self.engine.history.to_text()));
        if let Err(e) = written {
            log::warn("words", format_args!("{}: {e}", path.display()));
        }
    }
}

pub struct DictionaryRust {
    suggestions: QStringList,
    correction: QString,
    suggested_for: QString,
    state: Arc<Mutex<State>>,
    // The newest suggestions asked for; older ones still queued are skipped.
    asked: Arc<AtomicU64>,
    // The taps and word before of the suggestions in, for correctionFor.
    suggested_with: (String, String),
}

impl Default for DictionaryRust {
    fn default() -> Self {
        Self {
            suggestions: QStringList::default(),
            correction: QString::default(),
            suggested_for: QString::default(),
            state: Arc::new(Mutex::new(State {
                // QWERTY until the keyboard reports where its keys are.
                engine: Engine::new(Lexicon::default(), Layout::qwerty(), History::default()),
                language: String::new(),
                loaded: false,
                config: marathon_rt::dirs::config().join("marathon-os"),
                unsaved: 0,
            })),
            asked: Arc::default(),
            suggested_with: (String::new(), String::new()),
        }
    }
}

fn list<S: AsRef<str>>(items: &[S]) -> QStringList {
    items.iter().map(|s| QString::from(s.as_ref())).collect()
}

/// "x,y;x,y" as points.
fn points(text: &QString) -> Vec<(f32, f32)> {
    text.to_string()
        .split(';')
        .filter_map(|p| {
            let (x, y) = p.split_once(',')?;
            Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
        })
        .collect()
}

fn before(text: &QString) -> Option<String> {
    let text = text.to_string();
    (!text.is_empty()).then_some(text)
}

impl Dictionary {
    /// The state with its words in: loaded now when the background load
    /// hasn't finished, or no language was set (its region's English).
    fn state(&self) -> std::sync::MutexGuard<'_, State> {
        let mut state = self.state.lock().unwrap_or_else(|_| std::process::abort());
        if state.language.is_empty() {
            state.language = word_list_for("en_US");
        }
        if !state.loaded {
            state.load();
        }
        state
    }

    fn suggest(mut self: Pin<&mut Self>, typed: &QString, taps: &QString, before_word: &QString) {
        let with = (taps.to_string(), before_word.to_string());
        if self.suggested_for == *typed && self.suggested_with == with {
            return;
        }
        set!(self, suggested_for, suggested_for_changed, typed.clone());
        self.as_mut().rust_mut().suggested_with = with;
        set!(
            self,
            suggestions,
            suggestions_changed,
            QStringList::default()
        );
        set!(self, correction, correction_changed, typed.clone());
        if typed.is_empty() {
            return;
        }
        drop(self.state());
        let (state, asked, qt) = (
            Arc::clone(&self.state),
            Arc::clone(&self.asked),
            self.qt_thread(),
        );
        let ask = asked.fetch_add(1, Ordering::Relaxed) + 1;
        let (typed, taps, before_word) = (typed.to_string(), points(taps), before(before_word));
        crate::io::spawn(async move {
            let made = blocking::unblock(move || {
                (asked.load(Ordering::Relaxed) == ask).then(|| {
                    let state = state.lock().unwrap_or_else(|_| std::process::abort());
                    if !state.loaded {
                        return (marathon_keyboard::Suggestions::default(), typed);
                    }
                    let got = state.engine.suggest(&typed, &taps, before_word.as_deref());
                    (got, typed)
                })
            });
            let Some((got, typed)) = made.await else {
                return;
            };
            if got.words.is_empty() {
                return;
            }
            qt.queue(move |mut obj| {
                if obj.suggested_for.to_string() == typed {
                    let correction = got.correction.unwrap_or(typed);
                    set!(
                        obj,
                        correction,
                        correction_changed,
                        QString::from(&correction)
                    );
                    set!(obj, suggestions, suggestions_changed, list(&got.words));
                }
            })
            .ok();
        });
    }

    fn correction_for(&self, typed: &QString, taps: &QString, before_word: &QString) -> QString {
        let with = (taps.to_string(), before_word.to_string());
        if self.suggested_for == *typed
            && self.suggested_with == with
            && !self.suggestions.is_empty()
        {
            return self.correction.clone();
        }
        let typed = typed.to_string();
        let got =
            self.state()
                .engine
                .suggest(&typed, &points(taps), before(before_word).as_deref());
        QString::from(&got.correction.unwrap_or(typed))
    }

    fn swipe(&self, path: &QString, before_word: &QString) -> QStringList {
        list(
            &self
                .state()
                .engine
                .swipe(&points(path), before(before_word).as_deref()),
        )
    }

    fn next_words(&self, before_word: &QString) -> QStringList {
        list(&self.state().engine.next_words(&before_word.to_string()))
    }

    fn learn(&self, before_word: &QString, word: &QString) {
        let word = word.to_string();
        if word.trim().is_empty() {
            return;
        }
        let before_word = before(before_word);
        let mut state = self.state();
        state.engine.learn(before_word.as_deref(), &word);
        state.unsaved += 1;
        if state.unsaved >= SAVE_EVERY {
            let state = Arc::clone(&self.state);
            crate::io::spawn(async move {
                blocking::unblock(move || {
                    state
                        .lock()
                        .unwrap_or_else(|_| std::process::abort())
                        .save();
                })
                .await;
            });
        }
    }

    fn set_keys(&self, keys: &QString, pitch: f64) {
        #[allow(clippy::cast_possible_truncation, reason = "a key's width in pixels")]
        let layout = Layout::parse(&keys.to_string(), pitch as f32);
        if !layout.is_empty() {
            self.state
                .lock()
                .unwrap_or_else(|_| std::process::abort())
                .engine
                .layout = layout;
        }
    }

    fn set_language(&self, language: &QString) {
        let language = word_list_for(&language.to_string());
        {
            let mut state = self.state.lock().unwrap_or_else(|_| std::process::abort());
            if state.language == language {
                return;
            }
            language.clone_into(&mut state.language);
            state.loaded = false;
        }
        let state = Arc::clone(&self.state);
        crate::io::spawn(async move {
            blocking::unblock(move || {
                let lock = || state.lock().unwrap_or_else(|_| std::process::abort());
                let config = lock().config.clone();
                // Parsed unlocked: the keyboard keeps working meanwhile.
                let lexicon = Lexicon::parse(&word_list(&language));
                let history = History::parse(&history_text(&config), &lexicon);
                let mut state = lock();
                if state.language == language && !state.loaded {
                    state.install(lexicon, history);
                }
            })
            .await;
        });
    }
}

/// English is spelt the way the phone's region spells it: American in the
/// Americas, by its time zone (the language setting is rarely more than
/// "English"), British elsewhere.
fn word_list_for(language: &str) -> String {
    if !language.starts_with("en") {
        return language.to_owned();
    }
    let zone = std::fs::read_link("/etc/localtime")
        .map_or_else(|_| String::new(), |p| p.to_string_lossy().into_owned());
    let american = if zone.contains("zoneinfo/") {
        zone.contains("zoneinfo/America/") || zone.contains("zoneinfo/US/")
    } else {
        language == "en_US"
    };
    if american { "en_US" } else { "en_GB" }.to_owned()
}

/// The language's word list (from `MARATHON_KEYBOARD_WORDS`, for tests), or
/// its Hunspell words, all equally common.
fn word_list(language: &str) -> String {
    let dir = std::env::var("MARATHON_KEYBOARD_WORDS").unwrap_or_else(|_| WORD_LISTS.to_owned());
    let path = PathBuf::from(dir).join(format!("{language}.lex"));
    if let Ok(text) = std::fs::read_to_string(&path) {
        return text;
    }
    log::warn(
        "words",
        format_args!("{} missing: Hunspell words instead", path.display()),
    );
    let dic = hunspell(language).unwrap_or_default();
    dic.lines()
        .skip(1)
        .filter_map(|l| l.split('/').next().map(str::trim))
        .filter(|w| !w.is_empty())
        .fold(String::new(), |mut out, w| {
            out.push_str(w);
            out.push_str("\t100\n");
            out
        })
}

/// The language's Hunspell word list, or any of its regions'.
fn hunspell(language: &str) -> Option<String> {
    let code = language.get(..2).unwrap_or(language);
    let ours = |p: &Path| {
        p.extension().is_some_and(|e| e.eq_ignore_ascii_case("dic"))
            && p.file_stem()
                .is_some_and(|s| s.to_string_lossy().starts_with(code))
    };
    let path = HUNSPELL.iter().map(Path::new).find_map(|dir| {
        let exact = dir.join(format!("{language}.dic"));
        if exact.exists() {
            return Some(exact);
        }
        std::fs::read_dir(dir)
            .ok()?
            .flatten()
            .map(|e| e.path())
            .find(|p| ours(p))
    })?;
    let bytes = std::fs::read(path).ok()?;
    Some(
        String::from_utf8(bytes)
            .unwrap_or_else(|e| e.into_bytes().iter().map(|&b| char::from(b)).collect()),
    )
}

/// What was learnt: the history, or the word lists the keyboard kept before.
fn history_text(config: &std::path::Path) -> String {
    if let Ok(text) = std::fs::read_to_string(config.join("keyboard_history.txt")) {
        return text;
    }
    [
        "keyboard_word_frequencies.txt",
        "keyboard_user_dictionary.txt",
    ]
    .iter()
    .filter_map(|f| std::fs::read_to_string(config.join(f)).ok())
    .collect::<Vec<_>>()
    .join("\n")
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
    fn taps_are_read_as_points() {
        assert_eq!(
            points(&QString::from("1.5,2;3,4.25; bad")),
            [(1.5, 2.0), (3.0, 4.25)]
        );
    }
}
