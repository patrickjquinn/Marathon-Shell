// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! Resolves the ambience that Keel's Theme exposes, from three layers
//! (lowest precedence first):
//!
//! 1. Keel defaults: a dark ambience (`palette::DEFAULT_HIGHLIGHT`).
//! 2. The ambience forwarded by keel-shell. keel-shell dumps the dconf
//!    directories `/desktop/jolla/theme/` and `/desktop/sailfish/silica/`
//!    into the app environment (`KEEL_AMBIENCE_*`, `KEEL_SILICA_*`, with the
//!    full key list in `KEEL_AMBIENCE_KEYS`) and later sends
//!    `org.shipwright.keel.Shell1.AmbienceChanged(a{sv})` with the same full
//!    keys (keel/shell/PROTOCOL.md). Keys are matched by name, see
//!    [`property_for_key`].
//! 3. Explicit Keel overrides: `KEEL_THEME_<PROPERTY>` environment variables
//!    named after the Theme property (`KEEL_THEME_HIGHLIGHT_COLOR`,
//!    `KEEL_THEME_COLOR_SCHEME`, `KEEL_THEME_PIXEL_RATIO`, ...). For desktop
//!    runs, tests and debugging.
//!
//! Colours that no layer sets are derived from the highlight colour and the
//! colour scheme (see `palette`).

use crate::palette::{self, ColorScheme, Rgba};

/// dconf directories keel-shell forwards, with their environment prefixes.
pub const FORWARDED_SOURCES: &[(&str, &str)] = &[
    ("/desktop/jolla/theme/", "KEEL_AMBIENCE_"),
    ("/desktop/sailfish/silica/", "KEEL_SILICA_"),
];

pub const OVERRIDE_PREFIX: &str = "KEEL_THEME_";

/// Theme properties the ambience can set.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Prop {
    Highlight,
    Primary,
    Secondary,
    SecondaryHighlight,
    HighlightBackground,
    HighlightDimmer,
    OverlayBackground,
    Error,
    ColorScheme,
    PixelRatio,
    HighlightBackgroundOpacity,
    BackgroundImage,
    FontFamily,
    FontFamilyHeading,
    AmbienceName,
}

fn normalise(key: &str) -> String {
    let mut rel = key;
    for (dir, _) in FORWARDED_SOURCES {
        if let Some(r) = key.strip_prefix(dir) {
            rel = r;
        }
    }
    rel.chars()
        .filter(char::is_ascii_alphanumeric)
        .collect::<String>()
        .to_ascii_lowercase()
}

/// Maps a key to a Theme property. Accepts Theme property names
/// (`highlightColor`), their `KEEL_THEME_` spelling (`HIGHLIGHT_COLOR`) and
/// the dconf keys Keel expects under `/desktop/jolla/theme/` and
/// `/desktop/sailfish/silica/` (`color/highlight`, `color_scheme`).
/// The dconf key names are to be verified on device (keel/README.md).
pub fn property_for_key(key: &str) -> Option<Prop> {
    Some(match normalise(key).as_str() {
        "highlightcolor" | "colorhighlight" => Prop::Highlight,
        "primarycolor" | "colorprimary" => Prop::Primary,
        "secondarycolor" | "colorsecondary" => Prop::Secondary,
        "secondaryhighlightcolor" | "colorsecondaryhighlight" => Prop::SecondaryHighlight,
        "highlightbackgroundcolor" | "colorhighlightbackground" => Prop::HighlightBackground,
        "highlightdimmercolor" | "colorhighlightdimmer" => Prop::HighlightDimmer,
        "overlaybackgroundcolor" | "coloroverlaybackground" => Prop::OverlayBackground,
        "errorcolor" | "colorerror" => Prop::Error,
        "colorscheme" => Prop::ColorScheme,
        "pixelratio" | "themepixelratio" => Prop::PixelRatio,
        "highlightbackgroundopacity" | "colorhighlightbackgroundopacity" => {
            Prop::HighlightBackgroundOpacity
        }
        "backgroundimage" | "wallpaper" | "backgroundwallpaper" => Prop::BackgroundImage,
        "fontfamily" => Prop::FontFamily,
        "fontfamilyheading" => Prop::FontFamilyHeading,
        "activeambience" | "ambiencename" => Prop::AmbienceName,
        _ => return None,
    })
}

/// keel-shell's environment variable name for a forwarded dconf key
/// (mirrors keel-shell's `Ambience::envName`).
pub fn env_name_for_forwarded_key(full_key: &str) -> Option<String> {
    let (dir, prefix) = FORWARDED_SOURCES
        .iter()
        .find(|(dir, _)| full_key.starts_with(dir))?;
    let rel = &full_key[dir.len()..];
    let mut out = String::from(*prefix);
    for c in rel.chars() {
        if c.is_ascii_alphanumeric() {
            out.push(c.to_ascii_uppercase());
        } else {
            out.push('_');
        }
    }
    Some(out)
}

/// Raw values set by one layer.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Layer {
    pub highlight: Option<Rgba>,
    pub primary: Option<Rgba>,
    pub secondary: Option<Rgba>,
    pub secondary_highlight: Option<Rgba>,
    pub highlight_background: Option<Rgba>,
    pub highlight_dimmer: Option<Rgba>,
    pub overlay_background: Option<Rgba>,
    pub error: Option<Rgba>,
    pub color_scheme: Option<ColorScheme>,
    pub pixel_ratio: Option<f64>,
    pub highlight_background_opacity: Option<f64>,
    pub background_image: Option<String>,
    pub font_family: Option<String>,
    pub font_family_heading: Option<String>,
    pub ambience_name: Option<String>,
}

fn unquote(v: &str) -> String {
    v.trim().trim_matches(|c| c == '\'' || c == '"').to_string()
}

fn parse_number(v: &str) -> Option<f64> {
    // GVariant text may carry a type prefix ("double 1.5", "uint32 2").
    let t = unquote(v);
    let last = t.split_whitespace().last()?;
    last.parse::<f64>().ok().filter(|n| n.is_finite())
}

impl Layer {
    /// Sets one value; unknown keys and unparsable values are ignored and
    /// reported as `false`.
    pub fn set(&mut self, key: &str, value: &str) -> bool {
        let Some(prop) = property_for_key(key) else {
            return false;
        };
        let colour = || Rgba::parse(value);
        match prop {
            Prop::Highlight => self.highlight = colour(),
            Prop::Primary => self.primary = colour(),
            Prop::Secondary => self.secondary = colour(),
            Prop::SecondaryHighlight => self.secondary_highlight = colour(),
            Prop::HighlightBackground => self.highlight_background = colour(),
            Prop::HighlightDimmer => self.highlight_dimmer = colour(),
            Prop::OverlayBackground => self.overlay_background = colour(),
            Prop::Error => self.error = colour(),
            Prop::ColorScheme => self.color_scheme = ColorScheme::parse(value),
            Prop::PixelRatio => self.pixel_ratio = parse_number(value).filter(|v| *v > 0.0),
            Prop::HighlightBackgroundOpacity => {
                self.highlight_background_opacity =
                    parse_number(value).filter(|v| (0.0..=1.0).contains(v));
            }
            Prop::BackgroundImage => self.background_image = Some(unquote(value)),
            Prop::FontFamily => self.font_family = Some(unquote(value)),
            Prop::FontFamilyHeading => self.font_family_heading = Some(unquote(value)),
            Prop::AmbienceName => self.ambience_name = Some(unquote(value)),
        }
        true
    }

    /// Parses `key=value` lines (blank lines and `#` comments skipped).
    pub fn from_lines(text: &str) -> Layer {
        let mut layer = Layer::default();
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            if let Some((k, v)) = line.split_once('=') {
                layer.set(k.trim(), v);
            }
        }
        layer
    }

    /// The forwarded layer from keel-shell's environment.
    pub fn from_forwarded_env(get: &dyn Fn(&str) -> Option<String>) -> Layer {
        let mut layer = Layer::default();
        let Some(keys) = get("KEEL_AMBIENCE_KEYS") else {
            return layer;
        };
        for key in keys.split(':').filter(|k| !k.is_empty()) {
            if let Some(name) = env_name_for_forwarded_key(key) {
                if let Some(value) = get(&name) {
                    layer.set(key, &value);
                }
            }
        }
        layer
    }

    /// The explicit override layer (`KEEL_THEME_*`).
    pub fn from_override_env(vars: &[(String, String)]) -> Layer {
        let mut layer = Layer::default();
        for (name, value) in vars {
            if let Some(rest) = name.strip_prefix(OVERRIDE_PREFIX) {
                layer.set(rest, value);
            }
        }
        layer
    }

    /// `self` with every value set in `upper` replaced by it.
    #[must_use]
    pub fn overlay(&self, upper: &Layer) -> Layer {
        macro_rules! pick {
            ($f:ident) => {
                upper.$f.clone().or_else(|| self.$f.clone())
            };
        }
        Layer {
            highlight: pick!(highlight),
            primary: pick!(primary),
            secondary: pick!(secondary),
            secondary_highlight: pick!(secondary_highlight),
            highlight_background: pick!(highlight_background),
            highlight_dimmer: pick!(highlight_dimmer),
            overlay_background: pick!(overlay_background),
            error: pick!(error),
            color_scheme: pick!(color_scheme),
            pixel_ratio: pick!(pixel_ratio),
            highlight_background_opacity: pick!(highlight_background_opacity),
            background_image: pick!(background_image),
            font_family: pick!(font_family),
            font_family_heading: pick!(font_family_heading),
            ambience_name: pick!(ambience_name),
        }
    }
}

/// Fully resolved values, as the QML Theme consumes them.
#[derive(Clone, Debug, PartialEq)]
pub struct Resolved {
    pub highlight: Rgba,
    pub primary: Rgba,
    pub secondary: Rgba,
    pub secondary_highlight: Rgba,
    pub highlight_background: Rgba,
    pub highlight_dimmer: Rgba,
    pub overlay_background: Rgba,
    pub error: Rgba,
    pub color_scheme: ColorScheme,
    pub pixel_ratio: f64,
    pub highlight_background_opacity: f64,
    pub background_image: String,
    pub font_family: String,
    pub font_family_heading: String,
    pub ambience_name: String,
}

/// Sailfish's text and heading families. sailfish-fonts' Sail Sans Pro (an
/// OFL derivative of Adobe's Source Sans Pro) has two files: "Sail Sans Pro
/// Light" and "Sail Sans Pro" (`ExtraLight`). Sailfish 2 and 3 set headings in
/// the `ExtraLight` weight; Sailfish 4 and 5 screenshots show page and dialog headers
/// with the Light file's stems (4 px at 70 px on an Xperia 10, against 2 px
/// for `ExtraLight`), so both default to the Light family.
pub const DEFAULT_FONT_FAMILY: &str = "Sail Sans Pro Light";
pub const DEFAULT_FONT_FAMILY_HEADING: &str = "Sail Sans Pro Light";
pub const DEFAULT_HIGHLIGHT_BACKGROUND_OPACITY: f64 = 0.3;

impl Layer {
    pub fn resolve(&self) -> Resolved {
        let scheme = self.color_scheme.unwrap_or(ColorScheme::LightOnDark);
        let base = self.highlight.unwrap_or(match scheme {
            ColorScheme::LightOnDark => palette::DEFAULT_HIGHLIGHT,
            ColorScheme::DarkOnLight => palette::DEFAULT_LIGHT_HIGHLIGHT,
        });
        let highlight = palette::highlight_from_color(base, scheme);
        Resolved {
            highlight,
            primary: self.primary.unwrap_or_else(|| palette::primary_for(scheme)),
            secondary: self
                .secondary
                .unwrap_or_else(|| palette::secondary_for(scheme)),
            secondary_highlight: self
                .secondary_highlight
                .unwrap_or_else(|| palette::secondary_highlight_from_color(base, scheme)),
            highlight_background: self
                .highlight_background
                .unwrap_or_else(|| palette::highlight_background_from_color(base, scheme)),
            highlight_dimmer: self
                .highlight_dimmer
                .unwrap_or_else(|| palette::highlight_dimmer_from_color(base, scheme)),
            overlay_background: self
                .overlay_background
                .unwrap_or_else(|| palette::overlay_background_for(scheme)),
            error: self.error.unwrap_or_else(|| palette::error_for(scheme)),
            color_scheme: scheme,
            // 0 = not provided: the QML Theme then derives it from the screen.
            pixel_ratio: self.pixel_ratio.unwrap_or(0.0),
            highlight_background_opacity: self
                .highlight_background_opacity
                .unwrap_or(DEFAULT_HIGHLIGHT_BACKGROUND_OPACITY),
            background_image: self.background_image.clone().unwrap_or_default(),
            font_family: self
                .font_family
                .clone()
                .filter(|f| !f.is_empty())
                .unwrap_or_else(|| DEFAULT_FONT_FAMILY.to_string()),
            font_family_heading: self
                .font_family_heading
                .clone()
                .or_else(|| self.font_family.clone())
                .filter(|f| !f.is_empty())
                .unwrap_or_else(|| DEFAULT_FONT_FAMILY_HEADING.to_string()),
            ambience_name: self.ambience_name.clone().unwrap_or_default(),
        }
    }
}

/// Where the current values came from, for diagnostics (`Ambience.source`).
pub fn describe_sources(forwarded: &Layer, runtime: &Layer, overrides: &Layer) -> String {
    let mut parts = vec!["defaults"];
    if *forwarded != Layer::default() {
        parts.push("keel-shell environment");
    }
    if *runtime != Layer::default() {
        parts.push("keel-shell D-Bus");
    }
    if *overrides != Layer::default() {
        parts.push("KEEL_THEME_ overrides");
    }
    parts.join(" + ")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn maps_theme_names_env_names_and_dconf_keys() {
        assert_eq!(property_for_key("highlightColor"), Some(Prop::Highlight));
        assert_eq!(property_for_key("HIGHLIGHT_COLOR"), Some(Prop::Highlight));
        assert_eq!(
            property_for_key("/desktop/jolla/theme/color/highlight"),
            Some(Prop::Highlight)
        );
        assert_eq!(
            property_for_key("/desktop/jolla/theme/color_scheme"),
            Some(Prop::ColorScheme)
        );
        assert_eq!(
            property_for_key("/desktop/sailfish/silica/theme_pixel_ratio"),
            Some(Prop::PixelRatio)
        );
        assert_eq!(property_for_key("/desktop/jolla/theme/version"), None);
    }

    #[test]
    fn env_names_match_keel_shell() {
        assert_eq!(
            env_name_for_forwarded_key("/desktop/jolla/theme/color/highlight").as_deref(),
            Some("KEEL_AMBIENCE_COLOR_HIGHLIGHT")
        );
        assert_eq!(
            env_name_for_forwarded_key("/desktop/jolla/theme/color_scheme").as_deref(),
            Some("KEEL_AMBIENCE_COLOR_SCHEME")
        );
        assert_eq!(
            env_name_for_forwarded_key("/desktop/sailfish/silica/theme_pixel_ratio").as_deref(),
            Some("KEEL_SILICA_THEME_PIXEL_RATIO")
        );
        assert_eq!(env_name_for_forwarded_key("/other/key"), None);
    }

    #[test]
    fn defaults_are_a_dark_ambience() {
        let r = Layer::default().resolve();
        assert_eq!(r.color_scheme, ColorScheme::LightOnDark);
        assert_eq!(r.primary.to_argb_string(), "#ffffffff");
        assert_eq!(r.secondary.to_argb_string(), "#ffbababa");
        assert_eq!(r.highlight, palette::DEFAULT_HIGHLIGHT);
        assert_eq!(r.font_family, "Sail Sans Pro Light");
        assert_eq!(r.font_family_heading, "Sail Sans Pro Light");
        assert!(r.pixel_ratio.abs() < f64::EPSILON);
        assert!((r.highlight_background_opacity - 0.3).abs() < f64::EPSILON);
    }

    #[test]
    fn forwarded_environment_is_read_through_the_key_list() {
        let mut env = HashMap::new();
        env.insert(
            "KEEL_AMBIENCE_KEYS",
            "/desktop/jolla/theme/color/highlight:/desktop/jolla/theme/color_scheme:/desktop/sailfish/silica/theme_pixel_ratio:/desktop/jolla/theme/version",
        );
        env.insert("KEEL_AMBIENCE_COLOR_HIGHLIGHT", "'#00aa00'");
        env.insert("KEEL_AMBIENCE_COLOR_SCHEME", "'darkonlight'");
        env.insert("KEEL_SILICA_THEME_PIXEL_RATIO", "2.0");
        env.insert("KEEL_AMBIENCE_VERSION", "3");
        let get = |k: &str| env.get(k).map(ToString::to_string);
        let layer = Layer::from_forwarded_env(&get);
        assert_eq!(layer.highlight, Some(Rgba::rgb(0, 0xaa, 0)));
        assert_eq!(layer.color_scheme, Some(ColorScheme::DarkOnLight));
        assert_eq!(layer.pixel_ratio, Some(2.0));
        let r = layer.resolve();
        assert_eq!(r.primary.to_argb_string(), "#ff000000");
    }

    #[test]
    fn overrides_win_over_forwarded_values() {
        let forwarded = Layer::from_lines("highlightColor=#ff0000\ncolorScheme=0\n");
        let overrides = Layer::from_override_env(&[
            ("KEEL_THEME_HIGHLIGHT_COLOR".into(), "#00ff00".into()),
            ("KEEL_THEME_PIXEL_RATIO".into(), "1.5".into()),
            ("UNRELATED".into(), "x".into()),
        ]);
        let r = forwarded.overlay(&overrides).resolve();
        assert_eq!(r.highlight, Rgba::rgb(0, 255, 0));
        assert!((r.pixel_ratio - 1.5).abs() < f64::EPSILON);
        assert_eq!(r.color_scheme, ColorScheme::LightOnDark);
    }

    #[test]
    fn explicit_colours_are_not_rederived() {
        let layer = Layer::from_lines(
            "# comment\nhighlightColor=#ff0000\nsecondaryHighlightColor=#123456\n\nbogus=1\n",
        );
        let r = layer.resolve();
        assert_eq!(r.secondary_highlight, Rgba::rgb(0x12, 0x34, 0x56));
        assert_ne!(r.highlight_dimmer, r.highlight);
    }

    #[test]
    fn numbers_accept_gvariant_type_prefixes_and_reject_nonsense() {
        let mut l = Layer::default();
        l.set("pixelRatio", "double 1.75");
        assert_eq!(l.pixel_ratio, Some(1.75));
        l.set("pixelRatio", "-3");
        assert_eq!(l.pixel_ratio, None);
        l.set("highlightBackgroundOpacity", "0.5");
        assert_eq!(l.highlight_background_opacity, Some(0.5));
        l.set("highlightBackgroundOpacity", "5");
        assert_eq!(l.highlight_background_opacity, None);
    }

    #[test]
    fn source_description() {
        let empty = Layer::default();
        let one = Layer::from_lines("highlightColor=#fff");
        assert_eq!(describe_sources(&empty, &empty, &empty), "defaults");
        assert_eq!(
            describe_sources(&one, &empty, &one),
            "defaults + keel-shell environment + KEEL_THEME_ overrides"
        );
    }
}
