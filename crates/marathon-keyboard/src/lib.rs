//! The on-screen keyboard's words. A word tapped is read as the keys the
//! taps landed nearest and as the words those taps could spell, weighed by
//! how common each word is, what came before it and what this person types;
//! a word swiped is the word whose keys the finger's path runs through.

pub mod fold;
pub mod history;
pub mod layout;
pub mod lexicon;
mod swipe;
mod taps;

use std::collections::HashSet;

use fold::fold;
use history::History;
use layout::Layout;
use lexicon::{Lexicon, WordId};

/// The score of one step of the lexicon's frequency scale (0-255, log).
const PER_FREQ: f32 = 0.05;
/// The frequency a word nobody knows, typed in full, is taken to have.
const UNKNOWN_FREQ: f32 = 45.0;
/// A word this person has typed before.
const LEARNT: f32 = 0.9;
const NEXT_WORD: f32 = 2.5;
const LEARNT_PAIR: f32 = 1.5;
/// A completion's price for the letters still to type.
const COMPLETING: f32 = 1.0;
/// How much likelier a correction must be to replace a real word typed.
const KEEP_REAL_WORD: f32 = 7.0;
/// Real words this common are never corrected.
const ALWAYS_REAL: u8 = 90;
const SHOWN: usize = 5;
/// A capitalised word, a name or an acronym, offered for a word typed in
/// lowercase.
const CAPITALISED: f32 = 1.5;
/// How much commoner an apostrophe's spelling must be to replace the word
/// typed without it: "cant" is "can't", "ill" stays.
const APOSTROPHE: u8 = 60;
/// How many swipe readings are checked for where the finger strayed.
const RERANKED: usize = 25;

#[derive(Debug, Default, PartialEq)]
pub struct Suggestions {
    /// The likeliest first; the word typed is among them.
    pub words: Vec<String>,
    /// What a space should leave instead of the word typed.
    pub correction: Option<String>,
}

#[derive(Default)]
pub struct Engine {
    pub lexicon: Lexicon,
    pub layout: Layout,
    pub history: History,
}

struct Scored {
    word: String,
    score: f32,
    complete: bool,
}

impl Engine {
    pub fn new(lexicon: Lexicon, layout: Layout, history: History) -> Self {
        Self {
            lexicon,
            layout,
            history,
        }
    }

    /// How likely `word` (as history keys it) is here, apart from its keys.
    fn likelihood(&self, id: Option<WordId>, word: &str, before: Option<&str>) -> f32 {
        let freq = id.map_or(UNKNOWN_FREQ, |id| f32::from(self.lexicon.freq(id)));
        let mut score = PER_FREQ * freq;
        let learnt = self.history.count(word);
        if learnt > 0 {
            score += LEARNT * (1.0 + small(learnt)).ln();
        }
        if let Some(before) = before {
            let before_key = history::key(&self.lexicon, before);
            if let (Some(id), Some(head)) = (id, self.lexicon.lookup(&before_key)) {
                if let Some(rank) = self.lexicon.next(head).iter().position(|&n| n == id) {
                    score += NEXT_WORD - 0.3 * small(u32::try_from(rank).unwrap_or(u32::MAX));
                }
            }
            let pair = self.history.pair(&before_key, word);
            if pair > 0 {
                score += LEARNT_PAIR * (1.0 + small(pair)).ln();
            }
        }
        score
    }

    fn letters(&self, id: WordId, buffer: &mut Vec<char>) {
        buffer.clear();
        buffer.extend(self.lexicon.folded(id).chars());
    }

    /// The suggestions for the word being typed, `typed`, from its taps (in
    /// pixels, one per character typed), after the words `before`.
    pub fn suggest(&self, typed: &str, taps: &[(f32, f32)], before: Option<&str>) -> Suggestions {
        let folded = fold(typed);
        if folded.is_empty() {
            return Suggestions::default();
        }
        let points = self.tap_points(&folded, taps);
        let taps = taps::Taps::new(&self.layout, &points);
        let letters: Vec<char> = folded.chars().collect();
        let typed_score = taps.spell(&self.layout, &letters, false);
        let scored = self.candidates(&taps, &points, &letters, typed_score, before);
        let commit = with_case_of(
            typed,
            &self.commit(typed, &folded, typed_score, &scored, before),
        );

        let mut words = vec![commit.clone()];
        if commit != typed {
            words.push(typed.to_owned());
        }
        let mut seen: HashSet<String> = words.iter().map(|w| w.to_lowercase()).collect();
        for s in &scored {
            if words.len() >= SHOWN {
                break;
            }
            let word = with_case_of(typed, &s.word);
            if seen.insert(word.to_lowercase()) {
                words.push(word);
            }
        }
        Suggestions {
            correction: (commit != typed).then_some(commit),
            words,
        }
    }

    /// The words the taps could be, the likeliest first: whole words a stray
    /// tap or a missed letter away, and words that start as typed.
    fn candidates(
        &self,
        taps: &taps::Taps,
        points: &[(f32, f32)],
        typed: &[char],
        typed_score: f32,
        before: Option<&str>,
    ) -> Vec<Scored> {
        let folded: String = typed.iter().collect();
        let n = typed.len();
        let mut firsts = self.layout.near(points[0], 1.6);
        firsts.truncate(5);
        for c in std::iter::once(typed[0])
            .chain(points.get(1).map_or_default(|&p| self.layout.near(p, 1.0)))
        {
            if !firsts.contains(&c) {
                firsts.push(c);
            }
        }
        let mut scored: Vec<Scored> = Vec::new();
        let mut letters = Vec::new();
        for len in n.saturating_sub(1).max(1)..=n + 1 {
            for &first in &firsts {
                for &id in self.lexicon.starting(first, len) {
                    if self.lexicon.offensive(id) && self.lexicon.folded(id) != folded {
                        continue;
                    }
                    self.letters(id, &mut letters);
                    let keys = taps.spell(&self.layout, &letters, false);
                    if keys < -12.0 {
                        continue;
                    }
                    let word = self.lexicon.word(id);
                    scored.push(Scored {
                        word: word.to_owned(),
                        score: keys + self.likelihood(Some(id), word, before) - capitalised(word),
                        complete: true,
                    });
                }
            }
        }
        let mut completions: Vec<(f32, WordId)> = self
            .lexicon
            .prefix(&folded)
            .filter(|&id| self.lexicon.letters(id) > n && !self.lexicon.offensive(id))
            .map(|id| (self.likelihood(Some(id), self.lexicon.word(id), before), id))
            .collect();
        completions.sort_by(|a, b| b.0.total_cmp(&a.0));
        for &(likely, id) in completions.iter().take(SHOWN) {
            scored.push(Scored {
                word: self.lexicon.word(id).to_owned(),
                score: typed_score + likely - COMPLETING,
                complete: false,
            });
        }
        for (word, word_letters) in self.history.extra() {
            let complete = word_letters.len() <= n + 1;
            let keys = taps.spell(&self.layout, word_letters, !complete);
            if keys > -12.0 {
                scored.push(Scored {
                    word: word.clone(),
                    score: keys + self.likelihood(None, word, before)
                        - if complete { 0.0 } else { COMPLETING },
                    complete,
                });
            }
        }
        scored.sort_by(|a, b| b.score.total_cmp(&a.score));
        scored
    }

    /// What a space leaves for `typed`: a real word stays unless something
    /// far likelier was meant; anything else becomes the likeliest word.
    fn commit(
        &self,
        typed: &str,
        folded: &str,
        typed_score: f32,
        scored: &[Scored],
        before: Option<&str>,
    ) -> String {
        let real = self
            .lexicon
            .lookup(typed)
            .filter(|&id| !self.lexicon.offensive(id) || self.lexicon.folded(id) == folded)
            .map(|id| self.spelling(id, typed));
        let known = real.is_some() || self.history.knows(typed);
        let typed_key = history::key(&self.lexicon, typed);
        let typed_likely = self.likelihood(real, &typed_key, before);
        let best = scored.iter().find(|s| s.complete);
        match (real, best) {
            (Some(id), Some(best))
                if self.lexicon.freq(id) < ALWAYS_REAL
                    && best.score > typed_score + typed_likely + KEEP_REAL_WORD =>
            {
                best.word.clone()
            }
            (Some(id), _) => {
                let word = self.lexicon.word(id);
                // "ok" stays ok; "i" is I.
                if word.chars().count() > 1
                    && word == word.to_uppercase()
                    && typed != typed.to_uppercase()
                {
                    typed.to_owned()
                } else {
                    word.to_owned()
                }
            }
            (None, Some(best)) if !known && best.score > typed_score + typed_likely => {
                best.word.clone()
            }
            _ => typed.to_owned(),
        }
    }

    /// Among the words `typed` folds to, the one to keep: its own spelling,
    /// unless another (an apostrophe's) is far commoner.
    fn spelling(&self, id: WordId, typed: &str) -> WordId {
        let group = self.lexicon.find(self.lexicon.folded(id));
        let commonest = group.max_by_key(|&g| self.lexicon.freq(g)).unwrap_or(id);
        if self.lexicon.word(id) == typed
            && self.lexicon.freq(commonest) >= self.lexicon.freq(id).saturating_add(APOSTROPHE)
            && !self.lexicon.offensive(commonest)
        {
            commonest
        } else {
            id
        }
    }

    /// One point per letter: a tap where there is one, else the key's centre.
    fn tap_points(&self, folded: &str, taps: &[(f32, f32)]) -> Vec<(f32, f32)> {
        folded
            .chars()
            .enumerate()
            .map(|(i, c)| match taps.get(i) {
                Some(&tap) if taps.len() == folded.chars().count() => self.layout.to_keys(tap),
                _ => self.layout.centre(c).unwrap_or((-10.0, -10.0)),
            })
            .collect()
    }

    /// The words likeliest to come next after `before`.
    pub fn next_words(&self, before: &str) -> Vec<String> {
        let key = history::key(&self.lexicon, before);
        let mut out: Vec<String> = self
            .history
            .after(&key)
            .into_iter()
            .filter(|&(_, n)| n >= 2)
            .map(|(w, _)| w.to_owned())
            .collect();
        if let Some(head) = self.lexicon.lookup(&key) {
            for &id in self.lexicon.next(head) {
                let word = self.lexicon.word(id);
                if !self.lexicon.offensive(id) && !out.iter().any(|w| w == word) {
                    out.push(word.to_owned());
                }
            }
        }
        out.truncate(3);
        out
    }

    /// The words a swipe through `points` (pixels) could be, likeliest first.
    pub fn swipe(&self, points: &[(f32, f32)], before: Option<&str>) -> Vec<String> {
        let points: Vec<(f32, f32)> = points.iter().map(|&p| self.layout.to_keys(p)).collect();
        if points.len() < 2 {
            return Vec::new();
        }
        let path = swipe::Path::new(&points);
        let mut starts = self.layout.near(path.start(), 1.4);
        starts.truncate(4);
        let mut ends = self.layout.near(path.end(), 1.4);
        ends.truncate(4);
        let mut scored: Vec<(f32, String)> = Vec::new();
        let mut letters = Vec::new();
        for &s in &starts {
            for &e in &ends {
                for &id in self.lexicon.ending(s, e) {
                    if self.lexicon.offensive(id) || self.lexicon.letters(id) < 2 {
                        continue;
                    }
                    self.letters(id, &mut letters);
                    if let Some(keys) = path.spell(&self.layout, &letters) {
                        let word = self.lexicon.word(id);
                        scored.push((
                            keys + self.likelihood(Some(id), word, before) - capitalised(word),
                            word.to_owned(),
                        ));
                    }
                }
            }
        }
        for (word, word_letters) in self.history.extra() {
            if let Some(keys) = path.spell(&self.layout, word_letters) {
                scored.push((keys + self.likelihood(None, word, before), word.clone()));
            }
        }
        scored.sort_by(|a, b| b.0.total_cmp(&a.0));
        scored.truncate(RERANKED);
        for (score, word) in &mut scored {
            let letters: Vec<char> = fold(word).chars().collect();
            *score += path.straying(&self.layout, &letters);
        }
        scored.sort_by(|a, b| b.0.total_cmp(&a.0));
        let mut seen = HashSet::new();
        scored
            .into_iter()
            .map(|(_, w)| w)
            .filter(|w| seen.insert(w.to_lowercase()))
            .take(SHOWN)
            .collect()
    }

    pub fn learn(&mut self, before: Option<&str>, word: &str) {
        self.history.learn(&self.lexicon, before, word);
    }
}

fn small(n: u32) -> f32 {
    f32::from(u16::try_from(n).unwrap_or(u16::MAX))
}

fn capitalised(word: &str) -> f32 {
    let mut chars = word.chars();
    let first_upper = chars.next().is_some_and(char::is_uppercase);
    let is_i = word == "I" || word.starts_with("I'");
    if first_upper && !is_i {
        CAPITALISED
    } else {
        0.0
    }
}

/// A word in the capitals typed: Teh, The; TEH, THE. A word the lexicon
/// capitalises (I, Dublin) keeps its capitals.
pub fn with_case_of(typed: &str, word: &str) -> String {
    if typed.chars().count() > 1 && typed == typed.to_uppercase() && typed != typed.to_lowercase() {
        return word.to_uppercase();
    }
    let mut chars = word.chars();
    match (
        typed.chars().next().is_some_and(char::is_uppercase),
        chars.next(),
    ) {
        (true, Some(first)) => first.to_uppercase().chain(chars).collect(),
        _ => word.to_owned(),
    }
}
