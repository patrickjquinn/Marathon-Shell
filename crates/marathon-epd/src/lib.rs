//! A software e-paper timing controller for a panel behind a dumb DSI bridge (the MP01 Tier B
//! design, `docs/design/EPAPER_GPU_TCON.md` §5).
//!
//! - [`waveform`]: tables, loaders (IWF/CSV, the decoded v0x25 CPLD tables) and [`wbf`] files.

pub mod waveform;
pub mod wbf;
