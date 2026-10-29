//! `marathon::Ambience`: the wallpaper's seed (highlight and scheme) for
//! `AmbienceController`, and the Keel ambience it publishes, which runners
//! relay to apps through `Ambience1`. `Wallpaper1` lists the built-in
//! wallpapers for the Settings app's picker.

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::time::Duration;

use async_io::Timer;
use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::{
    AspectRatioMode, QColor, QImage, QList, QMap, QMapPair_QString_QVariant, QString, QUrl,
    QVariant, TransformationMode,
};
use palette::color_difference::Wcag21RelativeContrast as _;
use palette::Srgb;
use zbus::OwnedVariant as OwnedValue;

use crate::io;
use crate::ipc::{self, value, State};
use marathon_qt as qvariant;

#[cxx_qt::bridge(namespace = "marathon")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qcolor.h");
        type QColor = cxx_qt_lib::QColor;
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
        include!("cxx-qt-lib/qmap.h");
        type QMap_QString_QVariant = cxx_qt_lib::QMap<cxx_qt_lib::QMapPair_QString_QVariant>;
        include!("cxx-qt-lib/qlist.h");
        type QList_QVariant = cxx_qt_lib::QList<cxx_qt_lib::QVariant>;
    }

    extern "RustQt" {
        #[qobject]
        #[qproperty(QColor, base_color, cxx_name = "baseColor", READ, NOTIFY = seed_changed)]
        #[qproperty(bool, light, READ, NOTIFY = seed_changed)]
        #[qproperty(f64, brightest, READ, NOTIFY = seed_changed)]
        #[qproperty(f64, darkest, READ, NOTIFY = seed_changed)]
        #[qproperty(QString, wallpaper_url, cxx_name = "wallpaperUrl", READ, NOTIFY = seed_changed)]
        #[qproperty(QMap_QString_QVariant, ambience, READ, NOTIFY)]
        #[qproperty(f64, pixel_ratio, cxx_name = "pixelRatio", READ, NOTIFY)]
        #[qproperty(QList_QVariant, wallpapers, READ, CONSTANT)]
        type Ambience = super::AmbienceRust;

        #[qsignal]
        #[cxx_name = "seedChanged"]
        fn seed_changed(self: Pin<&mut Self>);

        /// The seed of the wallpaper at `path`: a file or qrc URL, or a path.
        #[cxx_name = "setWallpaper"]
        fn set_wallpaper(self: Pin<&mut Ambience>, path: &QString);
        /// Silica's pixel ratio at Marathon's scale (dpi / 160 x interface
        /// size): Silica's base sizes are twice Marathon's design px.
        #[cxx_name = "setScale"]
        fn set_scale(self: Pin<&mut Ambience>, dpi: f64, user_scale: f64);
        #[qinvokable]
        fn publish(self: Pin<&mut Ambience>, map: &QMap_QString_QVariant);
    }

    impl cxx_qt::Threading for Ambience {}
    impl cxx_qt::Initialize for Ambience {}
}

use qobject::Ambience;

type Map = QMap<QMapPair_QString_QVariant>;

#[derive(Default)]
pub struct AmbienceRust {
    base_color: QColor,
    light: bool,
    /// Relative luminance of the wallpaper's brightest and darkest spots.
    brightest: f64,
    darkest: f64,
    wallpaper_url: QString,
    ambience: Map,
    pixel_ratio: f64,
    wallpapers: QList<QVariant>,
    pending: Map,
    published: u64,
    wallpaper: u64,
}

/// Name, file, highlight, and the relative luminance of the brightest spot
/// of the blurred ambience on a tall or square screen. Each highlight picks
/// up its wallpaper's accent, Marathon teal on most; Tundra leans to its sky,
/// Dawn to its warmer glow. All measure dark by `seed`, the sunset and the
/// dawn too: their bright skies are half the picture at most.
type BuiltIn = (&'static str, &'static str, (u8, u8, u8), f64);

const BUILT_IN: [BuiltIn; 18] = [
    ("Meridian", "meridian.jpg", (0x7d, 0xf0, 0xd4), 0.21),
    (
        "Mývatn Aurora",
        "aurora-myvatn.jpg",
        (0x7d, 0xf0, 0xd4),
        0.64,
    ),
    ("Moos Sunset", "moos-sunset.jpg", (0xff, 0xe2, 0xad), 0.94),
    (
        "Oeschinensee Night",
        "oeschinensee-night.jpg",
        (0xad, 0xe1, 0xff),
        0.31,
    ),
    (
        "Lake Sylvester Dawn",
        "sylvester-dawn.jpg",
        (0xad, 0xc9, 0xff),
        0.79,
    ),
    ("Slate Aurora", "slate-aurora.svg", (0x7d, 0xf0, 0xd4), 0.17),
    ("Long Run", "long-run.svg", (0x7d, 0xf0, 0xd4), 0.02),
    ("Carbon", "carbon.svg", (0x7d, 0xe6, 0xcf), 0.01),
    ("Indigo Dusk", "indigo-dusk.svg", (0x84, 0xe8, 0xda), 0.05),
    ("Track", "track.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Mesh", "mesh.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Contour", "contour.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Stride", "stride.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Tundra", "tundra.svg", (0x88, 0xe3, 0xea), 0.04),
    ("Striae", "striae.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Halftone", "halftone.svg", (0x7d, 0xf0, 0xd4), 0.01),
    ("Pulse", "pulse.svg", (0x7d, 0xf0, 0xd4), 0.02),
    ("Dawn", "dawn.svg", (0xa3, 0xee, 0xc9), 0.06),
];

/// One of Marathon's own (dark) wallpapers, by file name.
fn built_in(path: &str) -> Option<&'static BuiltIn> {
    let stem = Path::new(path).file_stem()?;
    let found = BUILT_IN
        .iter()
        .find(|w| Path::new(w.1).file_stem() == Some(stem));
    found.filter(|_| path.contains("wallpapers/"))
}

fn wallpapers() -> Vec<OwnedValue> {
    let entry = |&(name, file, _, _): &BuiltIn| {
        value(State::from([
            ("name".to_owned(), value(name.to_owned())),
            (
                "path".to_owned(),
                value(crate::settings::asset_url(&format!("wallpapers/{file}"))),
            ),
            ("isDark".to_owned(), value(true)),
        ]))
    };
    BUILT_IN.iter().map(entry).collect()
}

/// What an ambience is built from: the hue of the most saturated
/// well-populated hue band, else of the mean colour, the scheme, and the
/// relative luminance of the brightest and darkest pixels.
#[derive(Debug, PartialEq)]
struct Seed {
    hue: f64,
    greyed: bool,
    light: bool,
    brightest: f64,
    darkest: f64,
}

/// Hue in degrees (none for a grey), saturation and value.
fn hsv(rgb: [f64; 3]) -> (Option<f64>, f64, f64) {
    let [r, g, b] = rgb;
    let (max, min) = (r.max(g).max(b), r.min(g).min(b));
    let d = max - min;
    let hue = (d > 0.0).then(|| {
        let sector = if (max - r).abs() < f64::EPSILON {
            (g - b) / d
        } else if (max - g).abs() < f64::EPSILON {
            2.0 + (b - r) / d
        } else {
            4.0 + (r - g) / d
        };
        (sector * 60.0).rem_euclid(360.0)
    });
    (hue, if max > 0.0 { d / max } else { 0.0 }, max / 255.0)
}

#[derive(Clone, Copy, Default)]
struct Band {
    weight: f64,
    sum: [f64; 3],
    count: usize,
}

#[allow(
    clippy::cast_possible_truncation,
    clippy::cast_sign_loss,
    clippy::cast_precision_loss,
    reason = "hues in [0, 360), 64x64 pixels"
)]
fn seed(pixels: &[[u8; 3]]) -> Option<Seed> {
    if pixels.is_empty() {
        return None;
    }
    let mut bands = [Band::default(); 12];
    let (mut sum, mut lum) = ([0.0; 3], 0.0);
    let (mut brightest, mut darkest) = (0.0_f32, 1.0_f32);
    for px in pixels {
        let rgb = px.map(f64::from);
        sum.iter_mut().zip(rgb).for_each(|(s, c)| *s += c);
        lum += 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
        let luma = Srgb::new(px[0], px[1], px[2])
            .into_linear::<f32>()
            .relative_luminance()
            .luma;
        (brightest, darkest) = (brightest.max(luma), darkest.min(luma));
        let (Some(hue), s, v) = hsv(rgb) else {
            continue;
        };
        if s < 0.25 || v < 0.15 {
            continue;
        }
        let band = &mut bands[(hue as usize * 12 / 360).min(11)];
        band.weight += s;
        band.sum.iter_mut().zip(rgb).for_each(|(s, c)| *s += c);
        band.count += 1;
    }
    let best = bands.iter().filter(|b| b.count >= pixels.len() / 20).fold(
        None,
        |best: Option<&Band>, b| match best {
            Some(best) if best.weight >= b.weight => Some(best),
            _ => Some(b),
        },
    );
    let mean = |sum: [f64; 3], n: usize| sum.map(|c| (c / n as f64).round());
    let dominant = best.map_or_else(|| mean(sum, pixels.len()), |b| mean(b.sum, b.count));
    Some(Seed {
        hue: hsv(dominant).0.unwrap_or(0.0) / 360.0,
        greyed: best.is_none(),
        light: lum / pixels.len() as f64 / 255.0 > 0.6,
        brightest: f64::from(brightest),
        darkest: f64::from(darkest),
    })
}

#[allow(
    clippy::cast_sign_loss,
    clippy::cast_possible_truncation,
    reason = "QColor channels are 0..=255"
)]
fn pixels(path: &Path) -> Option<Vec<[u8; 3]>> {
    let image = QImage::from_data(&std::fs::read(path).ok()?, None)?;
    let image = image.scaled(
        64,
        64,
        AspectRatioMode::IgnoreAspectRatio,
        TransformationMode::SmoothTransformation,
    );
    let px = |x, y| {
        let c = image.pixel_color(x, y);
        [c.red(), c.green(), c.blue()].map(|c| c as u8)
    };
    Some(
        (0..image.height())
            .flat_map(|y| (0..image.width()).map(move |x| (x, y)))
            .map(|(x, y)| px(x, y))
            .collect(),
    )
}

/// A light pastel on a dark ambience, a deep quiet tone on a light one; a
/// grey wallpaper keeps a near-neutral highlight.
#[allow(clippy::cast_possible_truncation, reason = "QColor takes f32")]
fn highlight(seed: &Seed) -> QColor {
    let (s, v) = match (seed.light, seed.greyed) {
        (true, greyed) => (if greyed { 0.1 } else { 0.65 }, 0.5),
        (false, greyed) => (if greyed { 0.06 } else { 0.32 }, 1.0),
    };
    QColor::from_hsv_f(seed.hue as f32, s, v)
}

impl cxx_qt::Initialize for Ambience {
    fn initialize(mut self: Pin<&mut Self>) {
        self.as_mut().rust_mut().wallpapers = qvariant::qlist(&wallpapers());
        // Until the first seed, as bright and as dark as a wallpaper gets.
        self.as_mut().rust_mut().brightest = 1.0;
        self.as_mut()
            .on_ambience_changed(|obj| {
                ipc::signal("Ambience", "AmbienceChanged", (state(&obj.ambience),));
            })
            .release();
        self.as_mut()
            .on_ambience_changed(|obj| {
                let get = |k: &str| obj.ambience.get(&QString::from(k));
                let highlight = get("/desktop/jolla/theme/color/highlight").and_then(|v| {
                    v.value::<QColor>()
                        .map(|c| crate::theme::Color::new(c.red_f(), c.green_f(), c.blue_f()))
                        .or_else(|| {
                            v.value::<QString>()
                                .and_then(|s| crate::theme::parse(&s.to_string()))
                        })
                });
                let scheme = get("/desktop/jolla/theme/color_scheme")
                    .and_then(|v| v.value::<QString>())
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                crate::portal::set_ambience(highlight, &scheme);
            })
            .release();
        ipc::export(
            "Ambience",
            Ambience1 {
                qt: self.qt_thread(),
            },
        );
        ipc::export("Wallpaper", Wallpaper1);
    }
}

impl Ambience {
    fn set_wallpaper(mut self: Pin<&mut Self>, path: &QString) {
        let path = path.to_string();
        let url = QUrl::from(&QString::from(&path));
        let (local, shown) = if url.scheme_or_default().to_string() == "qrc" {
            (None, path)
        } else {
            let local = if url.is_local_file() {
                url.to_local_file_or_default().to_string()
            } else {
                path
            };
            let shown = QUrl::from_local_file(&QString::from(&local)).to_string();
            (Some(PathBuf::from(local)), shown)
        };
        let generation = {
            let mut rust = self.as_mut().rust_mut();
            rust.wallpaper += 1;
            rust.wallpaper
        };
        if let Some(&(_, _, rgb, brightest)) = built_in(&shown) {
            let base = QColor::from_rgb(rgb.0.into(), rgb.1.into(), rgb.2.into());
            return self.show_seed(base, false, (brightest, 0.0), &shown);
        }
        let Some(local) = local else { return };
        let qt = self.qt_thread();
        io::spawn(async move {
            let Some(seed) = blocking::unblock(move || seed(&pixels(&local)?)).await else {
                return;
            };
            qt.queue(move |obj| {
                if obj.wallpaper == generation {
                    let extremes = (seed.brightest, seed.darkest);
                    obj.show_seed(highlight(&seed), seed.light, extremes, &shown);
                }
            })
            .ok();
        });
    }

    fn show_seed(
        mut self: Pin<&mut Self>,
        base: QColor,
        light: bool,
        (brightest, darkest): (f64, f64),
        url: &str,
    ) {
        let mut rust = self.as_mut().rust_mut();
        rust.base_color = base;
        rust.light = light;
        rust.brightest = brightest;
        rust.darkest = darkest;
        rust.wallpaper_url = QString::from(url);
        self.seed_changed();
    }

    fn set_scale(mut self: Pin<&mut Self>, dpi: f64, user_scale: f64) {
        let ratio = dpi / 160.0 * user_scale / 2.0;
        if (ratio - self.pixel_ratio).abs() < 1e-9 {
            return;
        }
        self.as_mut().rust_mut().pixel_ratio = ratio;
        self.as_mut().pixel_ratio_changed();
        let latest = if self.pending.is_empty() {
            self.ambience.clone()
        } else {
            self.pending.clone()
        };
        self.publish(&latest);
    }

    /// Runners see the last of a burst of changes, 250 ms on.
    fn publish(mut self: Pin<&mut Self>, map: &Map) {
        let mut map = map.clone();
        if self.pixel_ratio > 0.0 {
            map.insert(
                QString::from("/desktop/sailfish/silica/theme_pixel_ratio"),
                QVariant::from(&self.pixel_ratio),
            );
        }
        let generation = {
            let mut rust = self.as_mut().rust_mut();
            rust.pending = map;
            rust.published += 1;
            rust.published
        };
        let qt = self.qt_thread();
        io::spawn(async move {
            Timer::after(Duration::from_millis(250)).await;
            qt.queue(move |mut obj| {
                if obj.published == generation && obj.pending != obj.ambience {
                    let pending = obj.pending.clone();
                    obj.as_mut().rust_mut().ambience = pending;
                    obj.ambience_changed();
                }
            })
            .ok();
        });
    }
}

fn state(map: &Map) -> State {
    map.iter()
        .filter_map(|(k, v)| Some((k.to_string(), qvariant::from_qt(v)?.try_to_owned().ok()?)))
        .collect()
}

struct Ambience1 {
    qt: cxx_qt::CxxQtThread<Ambience>,
}

/// Public: the ambience is what every app is drawn with.
#[zbus::interface(name = "org.marathonos.Shell.Ambience1")]
impl Ambience1 {
    async fn get_ambience(&self) -> zbus::fdo::Result<State> {
        ipc::on_gui(&self.qt, |obj| state(&obj.ambience)).await
    }
}

struct Wallpaper1;

/// Public: the built-in wallpapers.
#[zbus::interface(name = "org.marathonos.Shell.Wallpaper1")]
impl Wallpaper1 {
    #[allow(clippy::unused_self, reason = "a D-Bus method")]
    fn get_wallpapers(&self) -> Vec<OwnedValue> {
        wallpapers()
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::{built_in, pixels, seed, BUILT_IN};
    use std::path::Path;

    fn solid(rgb: [u8; 3]) -> Vec<[u8; 3]> {
        vec![rgb; 64 * 64]
    }

    #[test]
    fn a_saturated_wallpaper_gives_its_hue() {
        let s = seed(&solid([10, 40, 120])).unwrap();
        assert!((s.hue * 360.0 - 224.0).abs() < 1.0 && !s.greyed && !s.light);
    }

    #[test]
    fn a_bright_wallpaper_is_light() {
        assert!(seed(&solid([235, 240, 245])).unwrap().light);
    }

    #[test]
    fn a_grey_wallpaper_is_greyed() {
        let s = seed(&solid([90, 90, 90])).unwrap();
        assert!(s.greyed && !s.light && s.hue.abs() < 1e-9);
        assert!((s.brightest - 0.102).abs() < 1e-3 && (s.darkest - s.brightest).abs() < 1e-9);
    }

    #[test]
    fn a_seed_spans_its_brightest_and_darkest_pixels() {
        let mut px = solid([90, 90, 90]);
        px[0] = [255, 255, 255];
        px[1] = [0, 0, 0];
        let s = seed(&px).unwrap();
        assert!((s.brightest - 1.0).abs() < 1e-6 && s.darkest.abs() < 1e-6);
    }

    #[test]
    fn a_minority_hue_loses_to_the_mean() {
        let mut px = solid([90, 90, 90]);
        px[..100].fill([255, 0, 0]);
        assert!(seed(&px).unwrap().greyed);
        assert_eq!(seed(&[]), None);
    }

    fn installed(file: &str) -> Option<&'static super::BuiltIn> {
        built_in(&format!("/usr/share/marathon-shell/wallpapers/{file}"))
    }

    #[test]
    fn built_in_wallpapers_have_their_highlight() {
        assert_eq!(installed("indigo-dusk.svg").unwrap().2, (0x84, 0xe8, 0xda));
        assert!(built_in("qrc:/wallpapers/aurora-myvatn.jpg").is_some());
        assert_eq!(built_in("/home/user/Pictures/beach.jpg"), None);
        assert_eq!(built_in("/home/user/Pictures/dawn.svg"), None);
    }

    #[test]
    fn the_photographic_wallpapers_have_their_highlight() {
        for (file, rgb) in [
            ("moos-sunset.jpg", (0xff, 0xe2, 0xad)),
            ("oeschinensee-night.jpg", (0xad, 0xe1, 0xff)),
            ("sylvester-dawn.jpg", (0xad, 0xc9, 0xff)),
        ] {
            assert_eq!(installed(file).unwrap().2, rgb, "{file}");
        }
    }

    // Measured from the shipped files. Blurring only takes a peak down.
    #[test]
    fn every_built_in_wallpaper_measures_dark() {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../shell/resources/wallpapers");
        for &(_, file, _, brightest) in &BUILT_IN {
            let s = seed(&pixels(&dir.join(file)).unwrap()).unwrap();
            assert!(!s.light, "{file}");
            assert!(brightest <= s.brightest + 0.01, "{file}: {}", s.brightest);
        }
    }
}
