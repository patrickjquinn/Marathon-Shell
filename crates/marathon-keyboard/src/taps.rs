//! How well a run of taps spells a word: each tap scored against the key of
//! the letter it stands for, allowing a stray tap, a missed letter or two
//! letters swapped, at a price.

use crate::layout::Layout;

/// A tap's spread around the key aimed at, in key widths.
const SIGMA: f32 = 0.45;
/// The worst a tap can score against a letter: a key across the keyboard.
const FAR: f32 = -9.0;
const EXTRA_TAP: f32 = -4.5;
const MISSED_LETTER: f32 = -4.5;
const MISSED_DOUBLE: f32 = -1.5;
const SWAPPED: f32 = -2.5;

/// Each tap's score against every letter, worked out once per word typed.
pub struct Taps {
    scores: Vec<[f32; 26]>,
    other: Vec<(f32, f32)>,
}

impl Taps {
    pub fn new(layout: &Layout, taps: &[(f32, f32)]) -> Self {
        let scores = taps
            .iter()
            .map(|&tap| {
                let mut row = [FAR; 26];
                for (c, score) in ('a'..='z').zip(row.iter_mut()) {
                    *score = against(layout, tap, c);
                }
                row
            })
            .collect();
        Self {
            scores,
            other: taps.to_vec(),
        }
    }

    fn len(&self) -> usize {
        self.scores.len()
    }

    fn score(&self, layout: &Layout, tap: usize, c: char) -> f32 {
        if c.is_ascii_lowercase() {
            self.scores[tap][(c as u8 - b'a') as usize]
        } else {
            against(layout, self.other[tap], c)
        }
    }

    /// The taps against all of `letters`, or against their start when
    /// `prefix` (the rest of the word not typed yet).
    pub fn spell(&self, layout: &Layout, letters: &[char], prefix: bool) -> f32 {
        let (n, m) = (self.len(), letters.len());
        let width = m + 1;
        let mut dp = vec![f32::NEG_INFINITY; (n + 1) * width];
        dp[0] = 0.0;
        for i in 0..=n {
            for j in 0..=m {
                let mut best = dp[i * width + j];
                if i > 0 {
                    best = best.max(dp[(i - 1) * width + j] + EXTRA_TAP);
                }
                if j > 0 {
                    let missed = if j > 1 && letters[j - 1] == letters[j - 2] {
                        MISSED_DOUBLE
                    } else {
                        MISSED_LETTER
                    };
                    best = best.max(dp[i * width + j - 1] + missed);
                }
                if i > 0 && j > 0 {
                    best = best.max(
                        dp[(i - 1) * width + j - 1] + self.score(layout, i - 1, letters[j - 1]),
                    );
                }
                if i > 1 && j > 1 {
                    best = best.max(
                        dp[(i - 2) * width + j - 2]
                            + self.score(layout, i - 1, letters[j - 2])
                            + self.score(layout, i - 2, letters[j - 1])
                            + SWAPPED,
                    );
                }
                dp[i * width + j] = best;
            }
        }
        if prefix {
            (n.saturating_sub(1)..=m.min(n + 1))
                .map(|j| dp[n * width + j])
                .fold(f32::NEG_INFINITY, f32::max)
        } else {
            dp[n * width + m]
        }
    }
}

fn against(layout: &Layout, (x, y): (f32, f32), c: char) -> f32 {
    layout.centre(c).map_or(FAR, |(kx, ky)| {
        let d2 = (kx - x).powi(2) + (ky - y).powi(2);
        (-d2 / (2.0 * SIGMA * SIGMA)).max(FAR)
    })
}

#[cfg(test)]
mod tests {
    use super::Taps;
    use crate::layout::Layout;

    fn taps_on(layout: &Layout, word: &str) -> Vec<(f32, f32)> {
        word.chars().filter_map(|c| layout.centre(c)).collect()
    }

    #[test]
    fn the_word_tapped_scores_best() {
        let layout = Layout::qwerty();
        let taps = Taps::new(&layout, &taps_on(&layout, "thw"));
        let the: Vec<char> = "the".chars().collect();
        let tge: Vec<char> = "tge".chars().collect();
        let thw: Vec<char> = "thw".chars().collect();
        assert!(taps.spell(&layout, &thw, false) > taps.spell(&layout, &the, false));
        assert!(taps.spell(&layout, &the, false) > -3.0);
        assert!(taps.spell(&layout, &the, false) > taps.spell(&layout, &tge, false));
    }

    #[test]
    fn a_missed_double_letter_is_cheap() {
        let layout = Layout::qwerty();
        let taps = Taps::new(&layout, &taps_on(&layout, "leter"));
        let letter: Vec<char> = "letter".chars().collect();
        assert!(taps.spell(&layout, &letter, false) > -2.0);
    }

    #[test]
    fn swapped_letters_are_found() {
        let layout = Layout::qwerty();
        let taps = Taps::new(&layout, &taps_on(&layout, "hte"));
        let the: Vec<char> = "the".chars().collect();
        assert!(taps.spell(&layout, &the, false) > -3.0);
    }
}
