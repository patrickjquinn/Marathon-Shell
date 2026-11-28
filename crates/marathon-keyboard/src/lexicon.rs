//! A language's words with how common they are and what tends to follow
//! them, read from the `.lex` files packaging/packages/marathon-keyboard-words/build-lexicon.py writes.

use std::collections::HashMap;
use std::ops::Range;

use crate::fold::fold;

#[derive(Clone, Copy)]
struct Entry {
    word: (u32, u32),
    folded: (u32, u32),
    letters: u8,
    freq: u8,
    offensive: bool,
}

pub type WordId = u32;

#[derive(Default)]
pub struct Lexicon {
    arena: String,
    // Sorted by the folded form.
    entries: Vec<Entry>,
    by_start_len: HashMap<(char, u8), Vec<WordId>>,
    by_ends: HashMap<(char, char), Vec<WordId>>,
    // (head, start in `next_words`, count), sorted by head.
    next_index: Vec<(WordId, u32, u8)>,
    next_words: Vec<WordId>,
}

impl Lexicon {
    pub fn parse(text: &str) -> Self {
        let mut lines = text.lines();
        let mut raw: Vec<(String, &str, u8, bool)> = Vec::new();
        for line in lines.by_ref() {
            if line == "%next" {
                break;
            }
            let Some((word, f)) = line.split_once('\t') else {
                continue;
            };
            let offensive = f.ends_with('!');
            let freq = f.trim_end_matches('!').parse().unwrap_or(0);
            let folded = fold(word);
            if !folded.is_empty() {
                raw.push((folded, word, freq, offensive));
            }
        }
        raw.sort_by(|a, b| a.0.cmp(&b.0).then(b.2.cmp(&a.2)));

        let mut lex = Self::default();
        let mut ids: HashMap<&str, WordId> = HashMap::with_capacity(raw.len());
        for (folded, word, freq, offensive) in &raw {
            let id = WordId::try_from(lex.entries.len()).unwrap_or(WordId::MAX);
            let word_at = lex.push(word);
            let folded_at = lex.push(folded);
            let letters = u8::try_from(folded.chars().count()).unwrap_or(u8::MAX);
            lex.entries.push(Entry {
                word: word_at,
                folded: folded_at,
                letters,
                freq: *freq,
                offensive: *offensive,
            });
            ids.insert(word, id);
            let mut chars = folded.chars();
            if let Some(first) = chars.next() {
                let last = chars.next_back().unwrap_or(first);
                lex.by_start_len
                    .entry((first, letters))
                    .or_default()
                    .push(id);
                lex.by_ends.entry((first, last)).or_default().push(id);
            }
        }

        for line in lines {
            let Some((head, follow)) = line.split_once('\t') else {
                continue;
            };
            let Some(&head) = ids.get(head) else {
                continue;
            };
            let start = u32::try_from(lex.next_words.len()).unwrap_or(u32::MAX);
            lex.next_words
                .extend(follow.split(' ').filter_map(|w| ids.get(w).copied()));
            let count = lex.next_words.len() - start as usize;
            lex.next_index
                .push((head, start, u8::try_from(count).unwrap_or(u8::MAX)));
        }
        lex.next_index.sort_unstable();
        lex
    }

    fn push(&mut self, s: &str) -> (u32, u32) {
        let start = u32::try_from(self.arena.len()).unwrap_or(u32::MAX);
        self.arena.push_str(s);
        (start, u32::try_from(s.len()).unwrap_or(u32::MAX))
    }

    fn slice(&self, (start, len): (u32, u32)) -> &str {
        &self.arena[start as usize..(start + len) as usize]
    }

    fn entry(&self, id: WordId) -> &Entry {
        &self.entries[id as usize]
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn word(&self, id: WordId) -> &str {
        self.slice(self.entry(id).word)
    }

    pub fn folded(&self, id: WordId) -> &str {
        self.slice(self.entry(id).folded)
    }

    pub fn freq(&self, id: WordId) -> u8 {
        self.entry(id).freq
    }

    pub fn offensive(&self, id: WordId) -> bool {
        self.entry(id).offensive
    }

    /// The words that fold to `folded`, the most common first.
    pub fn find(&self, folded: &str) -> Range<WordId> {
        let ids = self.prefix(folded);
        let end = (ids.start..ids.end)
            .find(|&id| self.folded(id) != folded)
            .unwrap_or(ids.end);
        ids.start..end
    }

    /// The words whose folded form starts with `prefix`.
    pub fn prefix(&self, prefix: &str) -> Range<WordId> {
        let start = self
            .entries
            .partition_point(|e| self.slice(e.folded) < prefix);
        let end = start
            + self.entries[start..].partition_point(|e| self.slice(e.folded).starts_with(prefix));
        to_id(start)..to_id(end)
    }

    /// `word` as the lexicon has it: its own entry, or the commonest one it
    /// folds to.
    pub fn lookup(&self, word: &str) -> Option<WordId> {
        let ids = self.find(&fold(word));
        ids.clone()
            .find(|&id| self.word(id) == word)
            .or_else(|| {
                ids.clone()
                    .find(|&id| self.word(id).eq_ignore_ascii_case(word))
            })
            .or_else(|| (!ids.is_empty()).then_some(ids.start))
    }

    pub fn starting(&self, first: char, letters: usize) -> &[WordId] {
        u8::try_from(letters)
            .ok()
            .and_then(|n| self.by_start_len.get(&(first, n)))
            .map_or(&[], Vec::as_slice)
    }

    pub fn ending(&self, first: char, last: char) -> &[WordId] {
        self.by_ends.get(&(first, last)).map_or(&[], Vec::as_slice)
    }

    pub fn letters(&self, id: WordId) -> usize {
        usize::from(self.entry(id).letters)
    }

    /// What usually follows `head`, the likeliest first.
    pub fn next(&self, head: WordId) -> &[WordId] {
        let Ok(at) = self.next_index.binary_search_by_key(&head, |&(h, _, _)| h) else {
            return &[];
        };
        let (_, start, count) = self.next_index[at];
        &self.next_words[start as usize..start as usize + usize::from(count)]
    }
}

fn to_id(i: usize) -> WordId {
    WordId::try_from(i).unwrap_or(WordId::MAX)
}

#[cfg(test)]
mod tests {
    use super::Lexicon;

    const TEXT: &str = "don't\t185\nI\t196\nI'm\t150\nIM\t40\nits\t160\nit's\t170\nthe\t222\nthen\t180\n%next\nthe\tthen its\nI\tI'm\n";

    #[test]
    fn words_are_found_by_their_folded_form() {
        let lex = Lexicon::parse(TEXT);
        let dont = lex.find("dont");
        assert_eq!(lex.word(dont.start), "don't");
        let im: Vec<&str> = lex.find("im").map(|id| lex.word(id)).collect();
        assert_eq!(im, ["I'm", "IM"]);
        assert_eq!(lex.lookup("its").map(|id| lex.word(id)), Some("its"));
        assert_eq!(lex.lookup("i").map(|id| lex.word(id)), Some("I"));
    }

    #[test]
    fn next_words_keep_their_order() {
        let lex = Lexicon::parse(TEXT);
        let the = lex.lookup("the").unwrap_or_default();
        let next: Vec<&str> = lex.next(the).iter().map(|&id| lex.word(id)).collect();
        assert_eq!(next, ["then", "its"]);
        assert_eq!(lex.prefix("th").len(), 2);
    }
}
