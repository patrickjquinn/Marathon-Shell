//! The FM receiver's audio as a PipeWire stream: the A-die's I2S into the
//! AFE's UL2 capture (`CONNSYS_I2S` -> UL2), the `Capture_2` PCM, made a
//! PipeWire source and looped into a stream with the Music role, so
//! `WirePlumber` picks the output, volume and Bluetooth as it does for any
//! player. PipeWire reads the PCM in its own graph: a pipe from arecord
//! underran every half second.

use std::io::{self, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::time::{Duration, Instant};

const SWITCHES: &[&str] = &["UL2_CH1 CONNSYS_I2S_CH1", "UL2_CH2 CONNSYS_I2S_CH2"];
/// The tuner's PipeWire source; the PCM opens only while `SWITCHES` are on.
const NODE: &str = "radio_fm_tuner";

pub struct Route {
    /// pw-cli holding the tuner's source: it goes when pw-cli does.
    tuner: Child,
    _commands: ChildStdin,
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

fn node_exists() -> bool {
    Command::new("pw-cli")
        .args(["ls", "Node"])
        .stderr(Stdio::null())
        .output()
        .is_ok_and(|o| String::from_utf8_lossy(&o.stdout).contains(&format!("\"{NODE}\"")))
}

/// The PCM as a PipeWire source, held by an interactive pw-cli.
fn tuner(device: &str) -> io::Result<(Child, ChildStdin)> {
    let mut cli = Command::new("pw-cli")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let Some(mut commands) = cli.stdin.take() else {
        stop(&mut cli);
        return Err(io::Error::other("pw-cli took no commands"));
    };
    let created = writeln!(
        commands,
        "create-node adapter {{ factory.name=api.alsa.pcm.source node.name={NODE} \
         node.description=\"FM tuner\" media.class=Audio/Source \
         api.alsa.path=\"{device}\" priority.session=0 priority.driver=0 }}"
    );
    let deadline = Instant::now() + Duration::from_secs(3);
    while created.is_ok() && !node_exists() {
        if Instant::now() > deadline {
            stop(&mut cli);
            return Err(io::Error::other(
                "the FM tuner's PipeWire source did not appear",
            ));
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    if let Err(e) = created {
        stop(&mut cli);
        return Err(e);
    }
    Ok((cli, commands))
}

/// The tuner looped into the Radio stream; never another source, should
/// the tuner's go.
fn loopback(sink: Option<&str>) -> io::Result<Child> {
    let target = sink.map_or_else(String::new, |s| format!(" target.object=\"{s}\""));
    Command::new("pw-loopback")
        .arg(format!(
            "--capture-props={{ target.object={NODE} node.dont-fallback=true \
             node.dont-reconnect=true node.passive=true node.name=radio_fm_in }}"
        ))
        .arg(format!(
            "--playback-props={{ media.role=Music node.name=radio application.name=Radio \
             application.icon-name=radio node.description=Radio media.name=Radio{target} }}"
        ))
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
}

impl Route {
    pub fn start() -> io::Result<Self> {
        let device = pcm("Capture_2")?;
        switch(true)?;
        let (mut tuner, commands) = match tuner(&device) {
            Ok(t) => t,
            Err(e) => {
                switch(false).ok();
                return Err(e);
            }
        };
        let sink = std::env::var("MARATHON_RADIO_SINK")
            .ok()
            .filter(|s| !s.is_empty());
        match loopback(sink.as_deref()) {
            Ok(play) => Ok(Self {
                tuner,
                _commands: commands,
                play,
            }),
            Err(e) => {
                stop(&mut tuner);
                switch(false).ok();
                Err(e)
            }
        }
    }
}

impl Drop for Route {
    fn drop(&mut self) {
        stop(&mut self.play);
        stop(&mut self.tuner);
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
