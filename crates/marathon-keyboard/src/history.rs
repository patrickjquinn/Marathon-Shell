//! What this person types: how often each word, and each pair of words, so
//! the keyboard learns their words and their phrases.

use std::collections::HashMap;
use std::fmt::Write as _;

use crate::fold::fold;
use crate::lexicon::Lexicon;

/// A new word counts as a word once it has been typed this often, so one
/// typo left uncorrected doesn't become one.
pub const NEW_WORD_AFTER: u32 = 2;

#[derive(Default)]
pub struct History {
    words: HashMap<String, u32>,
    pairs: HashMap<(String, String), u32>,
    // Words not in the lexicon, as typed, with their folded letters.
    extra: Vec<(String, Vec<char>)>,
}

impl History {
    /// `w<TAB>word<TAB>count` and `p<TAB>word<TAB>next<TAB>count` lines.
    pub fn parse(text: &str, lexicon: &Lexicon) -> Self {
        let mut history = Self::default();
        for line in text.lines() {
            let fields: Vec<&str> = line.split('\t').collect();
            match fields.as_slice() {
                ["w", word, n] => {
                    let n = n.parse().unwrap_or(0);
                    history.words.insert((*word).to_owned(), n);
                }
                ["p", a, b, n] => {
                    let n = n.parse().unwrap_or(0);
                    history.pairs.insert(((*a).to_owned(), (*b).to_owned()), n);
                }
                // The keyboard's earlier format: a word and its count.
                [word, n] => {
                    let n = n.trim().parse().unwrap_or(1);
                    *history.words.entry((*word).to_owned()).or_default() += n;
                }
                [word] if !word.trim().is_empty() => {
                    let n = history.words.entry(word.trim().to_owned()).or_default();
                    *n = (*n).max(NEW_WORD_AFTER);
                }
                _ => {}
            }
        }
        history.reindex(lexicon);
        history
    }

    pub fn to_text(&self) -> String {
        let mut text = String::new();
        for (word, n) in &self.words {
            writeln!(text, "w\t{word}\t{n}").ok();
        }
        for ((a, b), n) in &self.pairs {
            writeln!(text, "p\t{a}\t{b}\t{n}").ok();
        }
        text
    }

    fn reindex(&mut self, lexicon: &Lexicon) {
        self.extra = self
            .words
            .iter()
            .filter(|&(w, &n)| n >= NEW_WORD_AFTER && lexicon.find(&fold(w)).is_empty())
            .map(|(w, _)| (w.clone(), fold(w).chars().collect()))
            .collect();
    }

    pub fn learn(&mut self, lexicon: &Lexicon, before: Option<&str>, word: &str) {
        let key = key(lexicon, word);
        let n = self.words.entry(key.clone()).or_default();
        *n += 1;
        if *n == NEW_WORD_AFTER && lexicon.find(&fold(word)).is_empty() {
            self.extra.push((key.clone(), fold(word).chars().collect()));
        }
        if let Some(before) = before {
            *self
                .pairs
                .entry((self::key(lexicon, before), key))
                .or_default() += 1;
        }
    }

    /// The word's own spelling when the lexicon has it lowercase, so "The"
    /// and "the" count together.
    pub fn count(&self, word: &str) -> u32 {
        self.words.get(word).copied().unwrap_or(0)
    }

    pub fn pair(&self, before: &str, word: &str) -> u32 {
        self.pairs
            .get(&(before.to_owned(), word.to_owned()))
            .copied()
            .unwrap_or(0)
    }

    /// What this person has typed after `before`, the most often first.
    pub fn after(&self, before: &str) -> Vec<(&str, u32)> {
        let mut after: Vec<(&str, u32)> = self
            .pairs
            .iter()
            .filter(|((a, _), _)| a == before)
            .map(|((_, b), &n)| (b.as_str(), n))
            .collect();
        after.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
        after
    }

    pub fn extra(&self) -> &[(String, Vec<char>)] {
        &self.extra
    }

    pub fn knows(&self, word: &str) -> bool {
        self.count(word) >= NEW_WORD_AFTER
    }
}

/// A word as history keeps it: as the lexicon spells it, or as typed.
pub fn key(lexicon: &Lexicon, word: &str) -> String {
    lexicon
        .lookup(word)
        .filter(|&id| lexicon.word(id).eq_ignore_ascii_case(word))
        .map_or_else(|| word.to_owned(), |id| lexicon.word(id).to_owned())
}
