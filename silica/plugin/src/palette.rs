// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Colour arithmetic for the Keel Theme. Pure Rust, no Qt: parsing and
//! formatting of QML colour strings and the derivation of the secondary
//! ambience colours from a highlight colour.
//!
//! Provenance: clean-room. The Silica documentation names the derived colours
//! (Theme.highlightFromColor, secondaryHighlightFromColor,
//! highlightBackgroundFromColor, highlightDimmerFromColor) but does not give
//! formulas; the formulas here are Keel's own and are tagged for device
//! comparison in keel/README.md ("Needs device verification").

/// `Theme.LightOnDark` (0) or `Theme.DarkOnLight` (1), as in the Silica docs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ColorScheme {
    LightOnDark = 0,
    DarkOnLight = 1,
}

impl ColorScheme {
    pub fn from_i32(v: i32) -> ColorScheme {
        if v == 1 {
            ColorScheme::DarkOnLight
        } else {
            ColorScheme::LightOnDark
        }
    }

    /// Accepts "0"/"1", "lightondark"/"darkonlight" in any case and with
    /// optional separators (`light-on-dark`, `dark_on_light`).
    pub fn parse(text: &str) -> Option<ColorScheme> {
        let t: String = text
            .trim()
            .trim_matches(|c| c == '\'' || c == '"')
            .chars()
            .filter(char::is_ascii_alphanumeric)
            .collect::<String>()
            .to_ascii_lowercase();
        match t.as_str() {
            "0" | "lightondark" | "dark" => Some(ColorScheme::LightOnDark),
            "1" | "darkonlight" | "light" => Some(ColorScheme::DarkOnLight),
            _ => None,
        }
    }
}

/// An 8-bit RGBA colour.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rgba {
    pub r: u8,
    pub g: u8,
    pub b: u8,
    pub a: u8,
}

impl Rgba {
    pub const fn rgb(r: u8, g: u8, b: u8) -> Rgba {
        Rgba { r, g, b, a: 255 }
    }

    pub const fn from_rgba(r: u8, g: u8, b: u8, a: u8) -> Rgba {
        Rgba { r, g, b, a }
    }

    /// Parses the forms QML accepts for colour strings: `#RGB`, `#RRGGBB`,
    /// `#AARRGGBB`, plus a few named colours that ambience files use.
    /// Surrounding quotes (`GVariant` text from dconf) are stripped.
    pub fn parse(text: &str) -> Option<Rgba> {
        let t = text.trim().trim_matches(|c| c == '\'' || c == '"').trim();
        match t.to_ascii_lowercase().as_str() {
            "white" => return Some(Rgba::rgb(255, 255, 255)),
            "black" => return Some(Rgba::rgb(0, 0, 0)),
            "transparent" => return Some(Rgba::from_rgba(0, 0, 0, 0)),
            _ => {}
        }
        let hex = t.strip_prefix('#')?;
        if !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return None;
        }
        let byte = |s: &str| u8::from_str_radix(s, 16).ok();
        match hex.len() {
            3 => {
                let n = |i: usize| byte(&hex[i..=i]).map(|v| v * 17);
                Some(Rgba::rgb(n(0)?, n(1)?, n(2)?))
            }
            6 => Some(Rgba::rgb(
                byte(&hex[0..2])?,
                byte(&hex[2..4])?,
                byte(&hex[4..6])?,
            )),
            8 => Some(Rgba::from_rgba(
                byte(&hex[2..4])?,
                byte(&hex[4..6])?,
                byte(&hex[6..8])?,
                byte(&hex[0..2])?,
            )),
            _ => None,
        }
    }

    /// `#AARRGGBB`, the QML colour string form that keeps alpha.
    pub fn to_argb_string(self) -> String {
        format!("#{:02x}{:02x}{:02x}{:02x}", self.a, self.r, self.g, self.b)
    }

    #[must_use]
    pub fn with_alpha(self, alpha: f64) -> Rgba {
        Rgba {
            a: to_byte(alpha),
            ..self
        }
    }

    /// Linear blend towards `other` by `t` (0 = self, 1 = other); alpha kept.
    #[must_use]
    pub fn mix(self, other: Rgba, t: f64) -> Rgba {
        let t = t.clamp(0.0, 1.0);
        let f = |a: u8, b: u8| to_byte((f64::from(a) * (1.0 - t) + f64::from(b) * t) / 255.0);
        Rgba {
            r: f(self.r, other.r),
            g: f(self.g, other.g),
            b: f(self.b, other.b),
            a: self.a,
        }
    }

    /// Relative luminance (sRGB, approximate), 0..1.
    pub fn luminance(self) -> f64 {
        (0.2126 * f64::from(self.r) + 0.7152 * f64::from(self.g) + 0.0722 * f64::from(self.b))
            / 255.0
    }
}

#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    reason = "clamped to 0..=255 before the cast"
)]
fn to_byte(v: f64) -> u8 {
    (v.clamp(0.0, 1.0) * 255.0).round() as u8
}

const WHITE: Rgba = Rgba::rgb(255, 255, 255);
const BLACK: Rgba = Rgba::rgb(0, 0, 0);

/// Highlight colour suitable for the scheme: on a dark ambience it must be
/// light enough to read, on a light ambience dark enough.
pub fn highlight_from_color(color: Rgba, scheme: ColorScheme) -> Rgba {
    let base = Rgba { a: 255, ..color };
    match scheme {
        ColorScheme::LightOnDark if base.luminance() < 0.45 => base.mix(WHITE, 0.45),
        ColorScheme::DarkOnLight if base.luminance() > 0.45 => base.mix(BLACK, 0.45),
        _ => base,
    }
}

/// Secondary highlight: the highlight darkened by about a quarter. Sailfish's
/// stock ambience files give opaque secondary highlights of this shape
/// (water: #7ff0fe -> #62b9c4, sailfish5: #ffad80 -> #c58562, i.e. x0.77;
/// airy, a light ambience: #004c99 -> #003d76, x0.8), measured 2026-10-02
/// from sailfish-content-ambiences-default 1.0.14 (values only).
pub fn secondary_highlight_from_color(color: Rgba, scheme: ColorScheme) -> Rgba {
    let h = highlight_from_color(color, scheme);
    match scheme {
        ColorScheme::LightOnDark => h.mix(BLACK, 0.23),
        ColorScheme::DarkOnLight => h.mix(BLACK, 0.2),
    }
}

/// Background behind highlighted content; drawn at
/// `Theme.highlightBackgroundOpacity` by the components. In a dark ambience
/// Sailfish uses the highlight's hue fully saturated: fitted to a `ComboBox`
/// menu and its highlight bar in the stock "water" ambience (#7ff0fe), whose
/// pixels match about #00cde7 at the 0.3 opacity (`tests/screenshots/reference/SOURCES.md`).
pub fn highlight_background_from_color(color: Rgba, scheme: ColorScheme) -> Rgba {
    let h = highlight_from_color(color, scheme);
    match scheme {
        ColorScheme::LightOnDark => saturated(h, 0.9),
        ColorScheme::DarkOnLight => h,
    }
}

/// `color` with full HSV saturation and `value_scale` times its value;
/// greys stay grey.
fn saturated(color: Rgba, value_scale: f64) -> Rgba {
    let (red, green, blue) = (f64::from(color.r), f64::from(color.g), f64::from(color.b));
    let max = red.max(green).max(blue);
    let min = red.min(green).min(blue);
    if max <= 0.0 || (max - min) / max < 0.05 {
        let scale = |x: f64| to_byte(x * value_scale / 255.0);
        return Rgba {
            r: scale(red),
            g: scale(green),
            b: scale(blue),
            a: color.a,
        };
    }
    // Same hue: each channel's position between min and max, stretched to
    // 0..value.
    let value = max * value_scale;
    let stretch = |x: f64| to_byte((x - min) / (max - min) * value / 255.0);
    Rgba {
        r: stretch(red),
        g: stretch(green),
        b: stretch(blue),
        a: color.a,
    }
}

/// A strongly dimmed shade of the highlight, used for dimming overlays. In
/// a dark ambience Sailfish uses the highlight's hue fully saturated at a
/// fifth of full value: highlight #80d9ff gives #002333 on a Silica phone
/// (measured by Onyx, codeberg.org/decon/onyx src/onyxsettings.cpp), not
/// the highlight mixed towards black (#1a2b33).
pub fn highlight_dimmer_from_color(color: Rgba, scheme: ColorScheme) -> Rgba {
    let h = highlight_from_color(color, scheme);
    match scheme {
        ColorScheme::LightOnDark => saturated(h, 0.2),
        ColorScheme::DarkOnLight => h.mix(WHITE, 0.8),
    }
}

/// Keel's default ambience ("Harbour", keel/silica/ambience/): a dark
/// ambience with a light cyan highlight, in the range of Sailfish's stock
/// dark ambiences.
pub const DEFAULT_HIGHLIGHT: Rgba = Rgba::rgb(0x7f, 0xd8, 0xff);

/// The highlight of Keel's light default ambience ("Harbour light").
pub const DEFAULT_LIGHT_HIGHLIGHT: Rgba = Rgba::rgb(0x00, 0x5c, 0xa3);

pub fn primary_for(scheme: ColorScheme) -> Rgba {
    match scheme {
        ColorScheme::LightOnDark => WHITE,
        ColorScheme::DarkOnLight => BLACK,
    }
}

/// Opaque, as in Sailfish's stock ambience files: #ffbababa in every dark
/// ambience, #ff454545 in the light ones.
pub fn secondary_for(scheme: ColorScheme) -> Rgba {
    match scheme {
        ColorScheme::LightOnDark => Rgba::rgb(0xba, 0xba, 0xba),
        ColorScheme::DarkOnLight => Rgba::rgb(0x45, 0x45, 0x45),
    }
}

pub fn overlay_background_for(scheme: ColorScheme) -> Rgba {
    match scheme {
        ColorScheme::LightOnDark => Rgba::rgb(0x0a, 0x0a, 0x0f).with_alpha(0.9),
        ColorScheme::DarkOnLight => Rgba::rgb(0xf5, 0xf5, 0xf5).with_alpha(0.9),
    }
}

pub fn error_for(scheme: ColorScheme) -> Rgba {
    match scheme {
        ColorScheme::LightOnDark => Rgba::rgb(0xff, 0x4d, 0x4d),
        ColorScheme::DarkOnLight => Rgba::rgb(0xc4, 0x00, 0x1a),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_qml_colour_forms() {
        assert_eq!(Rgba::parse("#fff"), Some(WHITE));
        assert_eq!(Rgba::parse("#123456"), Some(Rgba::rgb(0x12, 0x34, 0x56)));
        assert_eq!(
            Rgba::parse("#80123456"),
            Some(Rgba::from_rgba(0x12, 0x34, 0x56, 0x80))
        );
        assert_eq!(Rgba::parse("'#ff0000'"), Some(Rgba::rgb(255, 0, 0)));
        assert_eq!(Rgba::parse("white"), Some(WHITE));
        assert_eq!(Rgba::parse("#12345"), None);
        assert_eq!(Rgba::parse("#gggggg"), None);
        assert_eq!(Rgba::parse("red-ish"), None);
    }

    #[test]
    fn formats_with_alpha_first() {
        assert_eq!(Rgba::rgb(1, 2, 3).to_argb_string(), "#ff010203");
        assert_eq!(WHITE.with_alpha(0.6).to_argb_string(), "#99ffffff");
        assert_eq!(
            secondary_for(ColorScheme::LightOnDark).to_argb_string(),
            "#ffbababa"
        );
    }

    #[test]
    fn scheme_parsing() {
        assert_eq!(
            ColorScheme::parse("'darkonlight'"),
            Some(ColorScheme::DarkOnLight)
        );
        assert_eq!(
            ColorScheme::parse("light-on-dark"),
            Some(ColorScheme::LightOnDark)
        );
        assert_eq!(ColorScheme::parse("1"), Some(ColorScheme::DarkOnLight));
        assert_eq!(ColorScheme::parse("sepia"), None);
    }

    #[test]
    fn highlight_is_readable_on_its_scheme() {
        let dark_blue = Rgba::rgb(0, 0, 0x60);
        assert!(highlight_from_color(dark_blue, ColorScheme::LightOnDark).luminance() > 0.3);
        let pale = Rgba::rgb(0xee, 0xee, 0xff);
        assert!(highlight_from_color(pale, ColorScheme::DarkOnLight).luminance() < 0.6);
        // Already suitable colours pass through unchanged.
        assert_eq!(
            highlight_from_color(DEFAULT_HIGHLIGHT, ColorScheme::LightOnDark),
            DEFAULT_HIGHLIGHT
        );
    }

    #[test]
    fn highlight_background_is_the_saturated_hue() {
        let water =
            highlight_background_from_color(Rgba::rgb(0x7f, 0xf0, 0xfe), ColorScheme::LightOnDark);
        assert_eq!((water.r, water.g, water.b), (0, 203, 229));
        let grey =
            highlight_background_from_color(Rgba::rgb(200, 200, 200), ColorScheme::LightOnDark);
        assert_eq!((grey.r, grey.g, grey.b), (180, 180, 180));
    }

    #[test]
    fn derived_colours_match_a_silica_phone() {
        // Highlight #80d9ff and what Silica derives from it on a phone,
        // as measured by Onyx (src/onyxsettings.cpp): background #00a1e6,
        // secondary #62a7c5, dimmer #002333. Within one step per channel.
        let h = Rgba::rgb(0x80, 0xd9, 0xff);
        let near = |c: Rgba, (r, g, b): (u8, u8, u8)| {
            c.r.abs_diff(r) <= 1 && c.g.abs_diff(g) <= 1 && c.b.abs_diff(b) <= 1
        };
        let bg = highlight_background_from_color(h, ColorScheme::LightOnDark);
        assert!(near(bg, (0x00, 0xa1, 0xe6)), "{bg:?}");
        let dim = highlight_dimmer_from_color(h, ColorScheme::LightOnDark);
        assert!(near(dim, (0x00, 0x23, 0x33)), "{dim:?}");
        let sec = secondary_highlight_from_color(h, ColorScheme::LightOnDark);
        assert!(near(sec, (0x62, 0xa7, 0xc5)), "{sec:?}");
    }

    #[test]
    fn derived_colours_move_towards_background() {
        let h = DEFAULT_HIGHLIGHT;
        let s = secondary_highlight_from_color(h, ColorScheme::LightOnDark);
        let d = highlight_dimmer_from_color(h, ColorScheme::LightOnDark);
        assert!(s.luminance() < h.luminance());
        assert!(d.luminance() < s.luminance());
        // Sailfish's water ambience: #7ff0fe -> #62b9c4.
        let w =
            secondary_highlight_from_color(Rgba::rgb(0x7f, 0xf0, 0xfe), ColorScheme::LightOnDark);
        assert!(w.r.abs_diff(0x62) <= 2 && w.g.abs_diff(0xb9) <= 2 && w.b.abs_diff(0xc4) <= 2);
        let hl = Rgba::rgb(0x00, 0x4c, 0x99);
        let sl = secondary_highlight_from_color(hl, ColorScheme::DarkOnLight);
        assert!(sl.luminance() < hl.luminance());
    }
}
