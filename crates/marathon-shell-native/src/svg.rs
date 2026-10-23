//! SVG icons with resvg (clip paths and text, which Qt Svg lacks): app
//! icons spell marks in Sora, which text with no font family falls back to.

use std::sync::{Arc, LazyLock};

use resvg::{tiny_skia, usvg};

#[cxx_qt::bridge]
mod ffi {
    #[namespace = "marathon::svg"]
    extern "Rust" {
        /// Premultiplied RGBA, `width` x `height`, the SVG fitted inside;
        /// empty if it does not parse.
        fn render(data: &[u8], width: u32, height: u32) -> Vec<u8>;
    }
}

static OPTIONS: LazyLock<usvg::Options<'static>> = LazyLock::new(|| {
    let mut fonts = usvg::fontdb::Database::new();
    fonts.load_system_fonts();
    let mut options = usvg::Options {
        font_family: "Sora".into(),
        ..usvg::Options::default()
    };
    options.fontdb = Arc::new(fonts);
    options
});

#[allow(clippy::cast_precision_loss, reason = "icon sizes")]
fn render(data: &[u8], width: u32, height: u32) -> Vec<u8> {
    let Ok(tree) = usvg::Tree::from_data(data, &OPTIONS) else {
        return Vec::new();
    };
    let Some(mut pixmap) = tiny_skia::Pixmap::new(width, height) else {
        return Vec::new();
    };
    let size = tree.size();
    let scale = (width as f32 / size.width()).min(height as f32 / size.height());
    let dx = (width as f32 - size.width() * scale) / 2.0;
    let dy = (height as f32 - size.height() * scale) / 2.0;
    resvg::render(
        &tree,
        tiny_skia::Transform::from_row(scale, 0.0, 0.0, scale, dx, dy),
        &mut pixmap.as_mut(),
    );
    pixmap.take()
}
