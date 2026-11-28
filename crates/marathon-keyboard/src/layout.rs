//! Where the letters sit, in key widths, so a tap or a swipe can be read as
//! the keys it was near.

#[derive(Clone, Debug, Default)]
pub struct Layout {
    keys: Vec<(char, f32, f32)>,
    pitch: f32,
}

impl Layout {
    /// `q 54 1050;w 157 1050;…`: each letter and its key's centre in pixels;
    /// `pitch` is a letter key's width in the same pixels.
    pub fn parse(spec: &str, pitch: f32) -> Self {
        let keys = spec
            .split(';')
            .filter_map(|key| {
                let mut parts = key.split_whitespace();
                let c = parts.next()?.chars().next()?;
                let x: f32 = parts.next()?.parse().ok()?;
                let y: f32 = parts.next()?.parse().ok()?;
                Some((crate::fold::fold_char(c)?, x / pitch, y / pitch))
            })
            .collect();
        Self { keys, pitch }
    }

    /// A point in pixels, in key widths.
    pub fn to_keys(&self, (x, y): (f32, f32)) -> (f32, f32) {
        (x / self.pitch, y / self.pitch)
    }

    pub fn is_empty(&self) -> bool {
        self.keys.is_empty()
    }

    pub fn centre(&self, c: char) -> Option<(f32, f32)> {
        self.keys
            .iter()
            .find(|(k, _, _)| *k == c)
            .map(|&(_, x, y)| (x, y))
    }

    /// The letters within `radius` key widths of a point, nearest first.
    pub fn near(&self, (x, y): (f32, f32), radius: f32) -> Vec<char> {
        let mut near: Vec<(f32, char)> = self
            .keys
            .iter()
            .map(|&(c, kx, ky)| ((kx - x).hypot(ky - y), c))
            .filter(|&(d, _)| d <= radius)
            .collect();
        near.sort_by(|a, b| a.0.total_cmp(&b.0));
        near.into_iter().map(|(_, c)| c).collect()
    }

    /// QWERTY as a phone draws it: rows a key width and a half apart, the
    /// middle row in by half a key, the bottom by a key and a half.
    pub fn qwerty() -> Self {
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"];
        let mut keys = Vec::new();
        for (row, (letters, inset)) in rows.iter().zip([0.0, 0.5, 1.5]).enumerate() {
            for (i, c) in letters.chars().enumerate() {
                #[allow(clippy::cast_precision_loss, reason = "a key's index")]
                keys.push((c, inset + i as f32 + 0.5, 1.4 * row as f32 + 0.7));
            }
        }
        Self { keys, pitch: 1.0 }
    }
}
