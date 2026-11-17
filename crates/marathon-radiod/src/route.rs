//! The FM receiver's audio as a PipeWire stream: the A-die's I2S into the
//! AFE's UL2 capture (`CONNSYS_I2S` -> UL2), read from the `Capture_2` PCM
//! and played with the Music role, so `WirePlumber` picks the output, volume
//! and Bluetooth as it does for any player.

use std::io;
use std::process::{Child, Command, Stdio};

const SWITCHES: &[&str] = &["UL2_CH1 CONNSYS_I2S_CH1", "UL2_CH2 CONNSYS_I2S_CH2"];

pub struct Route {
    capture: Child,
    play: Child,
}

/// `hw:<card>,<device>` of the PCM named `name` in /proc/asound/pcm
/// (`00-04: Capture_2 (*) :  : capture 1`).
fn pcm(name: &str) -> io::Result<String> {
    find_pcm(&std::fs::read_to_string("/proc/asound/pcm")?, name)
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, format!("no {name} PCM")))
}

fn find_pcm(pcms: &str, name: &str) -> Option<String> {
    let line = pcms.lines().find(|l| {
        l.split(':')
            .nth(1)
            .is_some_and(|n| n.trim().trim_end_matches("(*)").trim() == name)
    })?;
    let (card, dev) = line.split(':').next()?.split_once('-')?;
    Some(format!(
        "hw:{},{}",
        card.parse::<u32>().ok()?,
        dev.parse::<u32>().ok()?
    ))
}

fn switch(on: bool) -> io::Result<()> {
    for name in SWITCHES {
        let status = Command::new("amixer")
            .args([
                "-q",
                "-c",
                "0",
                "cset",
                &format!("name={name}"),
                if on { "on" } else { "off" },
            ])
            .status()?;
        if !status.success() && on {
            return Err(io::Error::other(format!("amixer: {name}")));
        }
    }
    Ok(())
}

/// Whether wired headphones are in: the FM tuner's aerial.
pub fn headset() -> bool {
    Command::new("amixer")
        .args(["-c", "0", "cget", "iface=CARD,name=Headphones Jack"])
        .output()
        .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).contains(": values=on"))
}

fn stop(child: &mut Child) {
    child.kill().ok();
    child.wait().ok();
}

impl Route {
    pub fn start() -> io::Result<Self> {
        let device = pcm("Capture_2")?;
        switch(true)?;
        let mut capture = Command::new("arecord")
            .args([
                "-q", "-D", &device, "-t", "raw", "-f", "S16_LE", "-r", "48000", "-c", "2",
            ])
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .spawn()?;
        let Some(audio) = capture.stdout.take() else {
            stop(&mut capture);
            return Err(io::Error::other("arecord gave no output"));
        };
        let play = crate::stream::player(Stdio::from(audio));
        match play {
            Ok(play) => Ok(Self { capture, play }),
            Err(e) => {
                stop(&mut capture);
                switch(false).ok();
                Err(e)
            }
        }
    }
}

impl Drop for Route {
    fn drop(&mut self) {
        stop(&mut self.capture);
        stop(&mut self.play);
        switch(false).ok();
    }
}

#[cfg(test)]
mod tests {
    use super::find_pcm;

    #[test]
    fn finds_a_pcm_by_its_name_on_the_q25() {
        let pcms = "00-01: Capture_1 (*) :  : capture 1\n\
                    00-04: Capture_2 (*) :  : capture 1\n\
                    00-05: Hostless_Speech (*) :  : playback 1 : capture 1\n";
        assert_eq!(find_pcm(pcms, "Capture_2").as_deref(), Some("hw:0,4"));
        assert_eq!(find_pcm(pcms, "Capture"), None);
    }
}
