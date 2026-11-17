//! The FM receiver's audio to the phone's output, as the stock HAL routes
//! it: the A-die's I2S into the AFE (`CONNSYS_I2S`), through HW gain 1 to
//! the DAC (`ADDA_DL`), all inside the AFE ("hostless"). The path runs
//! while the `Hostless_FM` PCM is open both ways, so silence is played into
//! it and its capture read into nothing for as long as the radio plays.

use std::io;
use std::process::{Child, Command, Stdio};

const SWITCHES: &[&str] = &[
    "HW_GAIN1_IN_CH1 CONNSYS_I2S_CH1",
    "HW_GAIN1_IN_CH2 CONNSYS_I2S_CH2",
    "ADDA_DL_CH1 GAIN1_OUT_CH1",
    "ADDA_DL_CH2 GAIN1_OUT_CH2",
];

pub struct Route {
    play: Child,
    capture: Child,
}

/// `hw:<card>,<device>` of the `Hostless_FM` PCM, from /proc/asound/pcm
/// (`00-08: Hostless_FM ...`).
fn hostless_fm() -> io::Result<String> {
    let pcms = std::fs::read_to_string("/proc/asound/pcm")?;
    pcms.lines()
        .find(|l| l.contains("Hostless_FM"))
        .and_then(|l| l.split(':').next())
        .and_then(|id| id.split_once('-'))
        .and_then(|(card, dev)| Some(format!("hw:{},{}", card.parse::<u32>().ok()?, dev.parse::<u32>().ok()?)))
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no Hostless_FM PCM"))
}

fn switch(on: bool) -> io::Result<()> {
    for name in SWITCHES {
        let status = Command::new("amixer")
            .args(["-q", "-c", "0", "cset", &format!("name={name}"), if on { "on" } else { "off" }])
            .status()?;
        if !status.success() && on {
            return Err(io::Error::other(format!("amixer: {name}")));
        }
    }
    Ok(())
}

fn hold(tool: &str, device: &str, file: &str) -> io::Result<Child> {
    Command::new(tool)
        .args(["-q", "-D", device, "-t", "raw", "-f", "S16_LE", "-r", "48000", "-c", "2", file])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
}

impl Route {
    pub fn start() -> io::Result<Self> {
        let device = hostless_fm()?;
        switch(true)?;
        let play = hold("aplay", &device, "/dev/zero")?;
        let capture = match hold("arecord", &device, "/dev/null") {
            Ok(c) => c,
            Err(e) => {
                let mut play = play;
                play.kill().ok();
                play.wait().ok();
                return Err(e);
            }
        };
        Ok(Self { play, capture })
    }
}

impl Drop for Route {
    fn drop(&mut self) {
        for child in [&mut self.play, &mut self.capture] {
            child.kill().ok();
            child.wait().ok();
        }
        switch(false).ok();
    }
}
