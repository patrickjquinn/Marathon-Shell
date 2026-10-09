// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT

//! `Keel.Ambience`: the `QObject` the QML Theme binds its colours to.
//!
//! The C++ side of the Keel plugin (keel/silica/plugin/cpp/keelplugin.cpp)
//! creates one instance per engine, registers it as the `Keel.Ambience`
//! singleton and feeds it keel-shell's `AmbienceChanged` D-Bus signal through
//! `applyForwarded()`.

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[namespace = "keel"]
        #[qproperty(QString, highlight_color, cxx_name = "highlightColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, primary_color, cxx_name = "primaryColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, secondary_color, cxx_name = "secondaryColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, secondary_highlight_color, cxx_name = "secondaryHighlightColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, highlight_background_color, cxx_name = "highlightBackgroundColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, highlight_dimmer_color, cxx_name = "highlightDimmerColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, overlay_background_color, cxx_name = "overlayBackgroundColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, error_color, cxx_name = "errorColor", READ, NOTIFY = ambience_changed)]
        #[qproperty(i32, color_scheme, cxx_name = "colorScheme", READ, NOTIFY = ambience_changed)]
        #[qproperty(f64, pixel_ratio, cxx_name = "pixelRatio", READ, NOTIFY = ambience_changed)]
        #[qproperty(f64, highlight_background_opacity, cxx_name = "highlightBackgroundOpacity", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, background_image, cxx_name = "backgroundImage", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, font_family, cxx_name = "fontFamily", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, font_family_heading, cxx_name = "fontFamilyHeading", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, ambience_name, cxx_name = "ambienceName", READ, NOTIFY = ambience_changed)]
        #[qproperty(QString, source, READ, NOTIFY = ambience_changed)]
        type Ambience = super::AmbienceRust;

        /// Emitted whenever any ambience value changes.
        #[qsignal]
        #[cxx_name = "ambienceChanged"]
        fn ambience_changed(self: Pin<&mut Self>);

        /// Re-reads the environment layers (keel-shell forwarding and
        /// KEEL_THEME_ overrides) and keeps the runtime layer.
        #[qinvokable]
        fn reload(self: Pin<&mut Self>);

        /// Replaces the runtime layer with `key=value` lines. keel-shell's
        /// AmbienceChanged(a{sv}) map is passed here one key per line.
        #[qinvokable]
        #[cxx_name = "applyForwarded"]
        fn apply_forwarded(self: Pin<&mut Self>, lines: &QString);

        #[qinvokable]
        #[cxx_name = "highlightFromColor"]
        fn highlight_from_color(&self, color: &QString, scheme: i32) -> QString;

        #[qinvokable]
        #[cxx_name = "secondaryHighlightFromColor"]
        fn secondary_highlight_from_color(&self, color: &QString, scheme: i32) -> QString;

        #[qinvokable]
        #[cxx_name = "highlightBackgroundFromColor"]
        fn highlight_background_from_color(&self, color: &QString, scheme: i32) -> QString;

        #[qinvokable]
        #[cxx_name = "highlightDimmerFromColor"]
        fn highlight_dimmer_from_color(&self, color: &QString, scheme: i32) -> QString;
    }
}

use crate::config::{self, Layer, Resolved};
use crate::palette::{self, ColorScheme, Rgba};
use core::pin::Pin;
use cxx_qt::CxxQtType;
use cxx_qt_lib::QString;

pub struct AmbienceRust {
    highlight_color: QString,
    primary_color: QString,
    secondary_color: QString,
    secondary_highlight_color: QString,
    highlight_background_color: QString,
    highlight_dimmer_color: QString,
    overlay_background_color: QString,
    error_color: QString,
    color_scheme: i32,
    pixel_ratio: f64,
    highlight_background_opacity: f64,
    background_image: QString,
    font_family: QString,
    font_family_heading: QString,
    ambience_name: QString,
    source: QString,
    /// The values last stored, so `refresh()` only notifies on a change.
    resolved: Option<Resolved>,

    forwarded: Layer,
    runtime: Layer,
    overrides: Layer,
}

fn env_layers() -> (Layer, Layer) {
    let get = |k: &str| std::env::var(k).ok();
    let forwarded = Layer::from_forwarded_env(&get);
    let vars: Vec<(String, String)> = std::env::vars()
        .filter(|(k, _)| k.starts_with(config::OVERRIDE_PREFIX))
        .collect();
    (forwarded, Layer::from_override_env(&vars))
}

impl AmbienceRust {
    /// Stores `r`; returns whether anything QML can see changed.
    fn store(&mut self, r: &Resolved) -> bool {
        let source = QString::from(
            config::describe_sources(&self.forwarded, &self.runtime, &self.overrides).as_str(),
        );
        if self.resolved.as_ref() == Some(r) && self.source == source {
            return false;
        }
        self.resolved = Some(r.clone());
        self.source = source;
        let c = |v: Rgba| QString::from(v.to_argb_string().as_str());
        self.highlight_color = c(r.highlight);
        self.primary_color = c(r.primary);
        self.secondary_color = c(r.secondary);
        self.secondary_highlight_color = c(r.secondary_highlight);
        self.highlight_background_color = c(r.highlight_background);
        self.highlight_dimmer_color = c(r.highlight_dimmer);
        self.overlay_background_color = c(r.overlay_background);
        self.error_color = c(r.error);
        self.color_scheme = r.color_scheme as i32;
        self.pixel_ratio = r.pixel_ratio;
        self.highlight_background_opacity = r.highlight_background_opacity;
        self.background_image = QString::from(r.background_image.as_str());
        self.font_family = QString::from(r.font_family.as_str());
        self.font_family_heading = QString::from(r.font_family_heading.as_str());
        self.ambience_name = QString::from(r.ambience_name.as_str());
        true
    }

    fn resolve(&self) -> Resolved {
        self.forwarded
            .overlay(&self.runtime)
            .overlay(&self.overrides)
            .resolve()
    }
}

impl Default for AmbienceRust {
    fn default() -> Self {
        let (forwarded, overrides) = env_layers();
        let mut me = AmbienceRust {
            highlight_color: QString::default(),
            primary_color: QString::default(),
            secondary_color: QString::default(),
            secondary_highlight_color: QString::default(),
            highlight_background_color: QString::default(),
            highlight_dimmer_color: QString::default(),
            overlay_background_color: QString::default(),
            error_color: QString::default(),
            color_scheme: 0,
            pixel_ratio: 0.0,
            highlight_background_opacity: config::DEFAULT_HIGHLIGHT_BACKGROUND_OPACITY,
            background_image: QString::default(),
            font_family: QString::default(),
            font_family_heading: QString::default(),
            ambience_name: QString::default(),
            source: QString::default(),
            resolved: None,
            forwarded,
            runtime: Layer::default(),
            overrides,
        };
        let r = me.resolve();
        let _ = me.store(&r);
        me
    }
}

fn derive(color: &QString, scheme: i32, f: fn(Rgba, ColorScheme) -> Rgba) -> QString {
    let parsed = Rgba::parse(&color.to_string()).unwrap_or(palette::DEFAULT_HIGHLIGHT);
    QString::from(
        f(parsed, ColorScheme::from_i32(scheme))
            .to_argb_string()
            .as_str(),
    )
}

impl qobject::Ambience {
    fn refresh(mut self: Pin<&mut Self>) {
        let r = self.resolve();
        if self.as_mut().rust_mut().store(&r) {
            self.ambience_changed();
        }
    }

    pub fn reload(mut self: Pin<&mut Self>) {
        let (forwarded, overrides) = env_layers();
        {
            let mut me = self.as_mut().rust_mut();
            me.forwarded = forwarded;
            me.overrides = overrides;
        }
        self.refresh();
    }

    pub fn apply_forwarded(mut self: Pin<&mut Self>, lines: &QString) {
        let layer = Layer::from_lines(&lines.to_string());
        self.as_mut().rust_mut().runtime = layer;
        self.refresh();
    }

    pub fn highlight_from_color(&self, color: &QString, scheme: i32) -> QString {
        derive(color, scheme, palette::highlight_from_color)
    }

    pub fn secondary_highlight_from_color(&self, color: &QString, scheme: i32) -> QString {
        derive(color, scheme, palette::secondary_highlight_from_color)
    }

    pub fn highlight_background_from_color(&self, color: &QString, scheme: i32) -> QString {
        derive(color, scheme, palette::highlight_background_from_color)
    }

    pub fn highlight_dimmer_from_color(&self, color: &QString, scheme: i32) -> QString {
        derive(color, scheme, palette::highlight_dimmer_from_color)
    }
}
