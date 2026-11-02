//! marathon-gnssd [DEVICE]: opens the GNSS device (which boots the DSP),
//! queries the DSP version and prints one line per epoch: the DSP time and
//! the messages it carried, unscrambled.

use marathon_gnssd::mtk::{self, Deframer};
use std::fmt::Write as _;
use std::fs::OpenOptions;
use std::io::{Read, Write};

fn main() -> std::io::Result<()> {
    let path = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "/dev/gnss0".into());
    let mut dev = OpenOptions::new().read(true).write(true).open(&path)?;
    dev.write_all(&mtk::version_query())?;
    let mut out = std::io::stdout().lock();
    let mut deframer = Deframer::default();
    let mut epoch: Vec<String> = Vec::new();
    let mut ms = None;
    let mut buf = [0u8; 4096];
    loop {
        let n = dev.read(&mut buf)?;
        if n == 0 {
            return Ok(());
        }
        for f in buf[..n].iter().filter_map(|&b| deframer.push(b)) {
            if let Some(t) = mtk::time_tag_ms(&f) {
                ms = Some(t);
            }
            let mut item = format!("{:04x}:", f.id);
            for b in &f.payload {
                write!(item, "{b:02x}").map_err(std::io::Error::other)?;
            }
            epoch.push(item);
            if f.id == mtk::id::EPOCH_END {
                writeln!(
                    out,
                    "{} {}",
                    ms.map_or_else(|| "-".into(), |t| t.to_string()),
                    epoch.join(" ")
                )?;
                epoch.clear();
            }
        }
    }
}
