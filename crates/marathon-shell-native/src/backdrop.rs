//! Whether the pixels behind a bar are light, for `BackdropProbe`: the
//! bar's glyphs go dark over a light backdrop and light over a dark one.

use palette::cast::try_from_component_slice;
use palette::color_difference::Wcag21RelativeContrast as _;
use palette::Srgba;

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::backdrop"]
    extern "Rust" {
        /// Whether RGBA8 pixels are a light backdrop, given the last answer.
        fn is_light(rgba: &[u8], was_light: bool) -> bool;
    }
}

/// Black and white glyphs have equal WCAG contrast over this luminance.
const EVEN: f32 = 0.179;
/// The share of pixels that must favour the other glyph colour to switch,
/// so mixed content keeps whichever it had.
const SWITCH: f32 = 0.6;

#[allow(clippy::cast_precision_loss, reason = "a few thousand pixels")]
fn is_light(rgba: &[u8], was_light: bool) -> bool {
    let Ok(pixels) = try_from_component_slice::<Srgba<u8>>(rgba) else {
        return was_light;
    };
    if pixels.is_empty() {
        return was_light;
    }
    let light = pixels
        .iter()
        .filter(|p| p.color.into_linear::<f32>().relative_luminance().luma > EVEN)
        .count() as f32
        / pixels.len() as f32;
    if was_light {
        light > 1.0 - SWITCH
    } else {
        light >= SWITCH
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strip(light: usize, dark: usize) -> Vec<u8> {
        let mut px = [230, 230, 230, 255].repeat(light);
        px.extend([20, 20, 20, 255].repeat(dark));
        px
    }

    #[test]
    fn clear_backdrops_decide_it() {
        assert!(is_light(&strip(10, 0), false));
        assert!(!is_light(&strip(0, 10), true));
    }

    #[test]
    fn mixed_backdrops_keep_the_last_answer() {
        assert!(is_light(&strip(5, 5), true));
        assert!(!is_light(&strip(5, 5), false));
    }

    #[test]
    fn unreadable_pixels_keep_the_last_answer() {
        assert!(is_light(&[1, 2, 3], true));
        assert!(!is_light(&[], false));
    }
}
