//! A software e-paper timing controller for a panel behind a dumb DSI bridge (the MP01 Tier B
//! design, `docs/design/EPAPER_GPU_TCON.md` §5).
//!
//! - [`waveform`]: tables, loaders (IWF/CSV, the decoded v0x25 CPLD tables) and [`wbf`] files.
//! - [`engine`]: per-pixel state machine, CPU reference.
//! - `gpu` (feature `gles`): the same machine as a GLES 3.1 compute shader, bit-exact.
//! - [`link`]: the drive-frame format and the bridge's acceptance rules.
//! - [`sched`]: when the loop runs: idle at 0 Hz, instant wake.

pub mod engine;
#[cfg(feature = "gles")]
pub mod gpu;
pub mod link;
pub mod sched;
pub mod waveform;
pub mod wbf;
