//! A swiped word: the finger's path against the path through each word's
//! keys, both cut into the same number of evenly spaced points.

use crate::layout::Layout;

const POINTS: usize = 40;
/// How far, in key widths, a path may run from a key and still have passed it.
const PASSED: f32 = 0.9;
const MISSED_KEY: f32 = -4.0;
const SPREAD: f32 = 7.0;
/// How far, in key widths, the finger may stray from a word's keys for free.
const STRAY: f32 = 0.6;
const STRAYING: f32 = 20.0;
/// The price of each key's width the finger travelled more or less than the
/// word needs, squared.
const LENGTH: f32 = 0.5;

pub struct Path {
    points: Vec<(f32, f32)>,
    // The path a tenth of a key apart, for finding the keys it passed.
    dense: Vec<(f32, f32)>,
    length: f32,
}

impl Path {
    pub fn new(points: &[(f32, f32)]) -> Self {
        let length = length(points);
        #[allow(
            clippy::cast_possible_truncation,
            clippy::cast_sign_loss,
            reason = "a path's length in tenths of a key"
        )]
        let dense = resample(points, ((length * 10.0) as usize).clamp(POINTS, 2000));
        Self {
            length,
            points: resample(points, POINTS),
            dense,
        }
    }

    pub fn start(&self) -> (f32, f32) {
        self.points.first().copied().unwrap_or_default()
    }

    pub fn end(&self) -> (f32, f32) {
        self.points.last().copied().unwrap_or_default()
    }

    /// How well the path spells `letters`, or None when it plainly doesn't.
    pub fn spell(&self, layout: &Layout, letters: &[char]) -> Option<f32> {
        let mut keys: Vec<(f32, f32)> = Vec::with_capacity(letters.len());
        for &c in letters {
            let key = layout.centre(c)?;
            if keys.last() != Some(&key) {
                keys.push(key);
            }
        }
        let ideal = length(&keys);
        if (ideal - self.length).abs() > 1.5_f32.max(0.45 * self.length) {
            return None;
        }
        let ideal_points = resample(&keys, POINTS);
        #[allow(clippy::cast_precision_loss, reason = "a few dozen points")]
        let distance = self
            .points
            .iter()
            .zip(&ideal_points)
            .map(|(a, b)| (a.0 - b.0).hypot(a.1 - b.1))
            .sum::<f32>()
            / POINTS as f32;
        if distance > 1.3 {
            return None;
        }
        // Each key in order: the first time the path comes near it.
        let mut from = 0;
        let mut missed = 0.0;
        for key in &keys {
            let near = |p: &(f32, f32)| (p.0 - key.0).hypot(p.1 - key.1);
            match self.dense[from..].iter().position(|p| near(p) <= PASSED) {
                Some(at) => {
                    let mut i = from + at;
                    while i + 1 < self.dense.len()
                        && near(&self.dense[i + 1]) < near(&self.dense[i])
                    {
                        i += 1;
                    }
                    from = i;
                }
                None => missed += MISSED_KEY,
            }
        }
        let longer = (self.length - ideal).abs();
        Some(-SPREAD * distance * distance - LENGTH * longer * longer + missed)
    }
}

impl Path {
    /// The price of the finger's furthest excursion from the path through
    /// `letters`: "the" doesn't explain a swipe out to the r of "there".
    pub fn straying(&self, layout: &Layout, letters: &[char]) -> f32 {
        let keys: Vec<(f32, f32)> = letters.iter().filter_map(|&c| layout.centre(c)).collect();
        let furthest = self
            .dense
            .iter()
            .map(|&p| match keys.as_slice() {
                [only] => (p.0 - only.0).hypot(p.1 - only.1),
                _ => keys
                    .windows(2)
                    .map(|w| to_segment(p, w[0], w[1]))
                    .fold(f32::INFINITY, f32::min),
            })
            .fold(0.0, f32::max);
        -STRAYING * (furthest - STRAY).max(0.0).powi(2)
    }
}

fn to_segment(p: (f32, f32), a: (f32, f32), b: (f32, f32)) -> f32 {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let len2 = dx * dx + dy * dy;
    let t = if len2 > 0.0 {
        (((p.0 - a.0) * dx + (p.1 - a.1) * dy) / len2).clamp(0.0, 1.0)
    } else {
        0.0
    };
    (p.0 - a.0 - t * dx).hypot(p.1 - a.1 - t * dy)
}

fn length(points: &[(f32, f32)]) -> f32 {
    points
        .windows(2)
        .map(|w| (w[1].0 - w[0].0).hypot(w[1].1 - w[0].1))
        .sum()
}

fn resample(points: &[(f32, f32)], n: usize) -> Vec<(f32, f32)> {
    let Some(&first) = points.first() else {
        return Vec::new();
    };
    let total = length(points);
    if total <= f32::EPSILON {
        return vec![first; n];
    }
    #[allow(clippy::cast_precision_loss, reason = "a few dozen points")]
    let step = total / (n - 1) as f32;
    let mut out = Vec::with_capacity(n);
    out.push(first);
    let mut carried = 0.0;
    for w in points.windows(2) {
        let (a, b) = (w[0], w[1]);
        let seg = (b.0 - a.0).hypot(b.1 - a.1);
        let mut at = step - carried;
        while at <= seg && out.len() < n {
            let t = at / seg;
            out.push((a.0 + t * (b.0 - a.0), a.1 + t * (b.1 - a.1)));
            at += step;
        }
        carried = (carried + seg) % step;
    }
    while out.len() < n {
        out.push(*points.last().unwrap_or(&first));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::{resample, Path};
    use crate::layout::Layout;

    #[test]
    fn resampling_spaces_points_evenly() {
        let r = resample(&[(0.0, 0.0), (3.0, 0.0)], 4);
        assert_eq!(r.len(), 4);
        assert!((r[1].0 - 1.0).abs() < 1e-4 && (r[3].0 - 3.0).abs() < 1e-4);
    }

    #[test]
    fn the_keys_swiped_spell_their_word_best() {
        let layout = Layout::qwerty();
        let keys: Vec<(f32, f32)> = "hello".chars().filter_map(|c| layout.centre(c)).collect();
        let path = Path::new(&keys);
        let hello: Vec<char> = "hello".chars().collect();
        let help: Vec<char> = "help".chars().collect();
        let good = path.spell(&layout, &hello).unwrap_or(f32::NEG_INFINITY);
        let worse = path.spell(&layout, &help).unwrap_or(f32::NEG_INFINITY);
        assert!(good > worse);
        assert!(good > -0.1);
    }
}
