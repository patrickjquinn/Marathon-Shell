// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The speech processes (shoal/pilot/voice): `pilot-voice` on the session
//! bus (`org.shipwright.Pilot.Voice`, D-Bus activated through
//! `shoal-pilot-voice.service`) and `pilot-tts` on its Unix socket
//! (`$XDG_RUNTIME_DIR/shoal-pilot/tts.sock`, socket activated). Stopping
//! the voice unit through the systemd user manager closes the microphone
//! when the privacy switch engages (spec section 8.3).

use std::io::Write as _;
use std::path::PathBuf;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;

use super::{AdapterError, Speech, VoiceControl};

pub const VOICE_UNIT: &str = "shoal-pilot-voice.service";
pub const VOICE_BUS_NAME: &str = "org.shipwright.Pilot.Voice";
pub const VOICE_PATH: &str = "/org/shipwright/Pilot/Voice";
pub const VOICE_INTERFACE: &str = "org.shipwright.Pilot.Voice1";

pub struct SystemdVoice {
    pub session: zbus::Connection,
    pub unit: String,
}

#[async_trait]
impl VoiceControl for SystemdVoice {
    async fn listen(&self) -> Result<String, AdapterError> {
        self.listen_reporting(&|_, _| {}).await
    }

    async fn listen_reporting(
        &self,
        report: &(dyn Fn(&str, f64) + Send + Sync),
    ) -> Result<String, AdapterError> {
        use futures_util::StreamExt as _;
        let p =
            zbus::Proxy::new(&self.session, VOICE_BUS_NAME, VOICE_PATH, VOICE_INTERFACE).await?;
        // pilot-voice's Level signal and State changes while it works.
        let mut levels = p.receive_signal("Level").await?;
        let mut states = p.receive_property_changed::<String>("State").await;
        report("listening", 0.0);
        let call = p.call::<_, _, String>("Listen", &());
        tokio::pin!(call);
        let answered = loop {
            tokio::select! {
                r = &mut call => break r,
                Some(m) = levels.next() => {
                    if let Ok(l) = m.body().deserialize::<f64>() {
                        report("level", l);
                    }
                }
                Some(c) = states.next() => {
                    if let Ok(s) = c.get().await {
                        if s == "transcribing" {
                            report("transcribing", 0.0);
                        }
                    }
                }
            }
        };
        let json: String = answered.map_err(|e| match e {
            zbus::Error::MethodError(name, msg, _)
                if name.as_str() == "org.freedesktop.DBus.Error.ServiceUnknown" =>
            {
                let _ = msg;
                AdapterError::Unavailable("voice recognition (pilot-voice)".into())
            }
            zbus::Error::MethodError(_, Some(msg), _) => AdapterError::Failed(msg),
            other => AdapterError::Failed(other.to_string()),
        })?;
        let v: serde_json::Value =
            serde_json::from_str(&json).map_err(|e| AdapterError::Failed(e.to_string()))?;
        Ok(v.get("text")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("")
            .to_owned())
    }

    async fn stop(&self) -> Result<(), AdapterError> {
        let stopped = self
            .session
            .call_method(
                Some("org.freedesktop.systemd1"),
                "/org/freedesktop/systemd1",
                Some("org.freedesktop.systemd1.Manager"),
                "StopUnit",
                &(self.unit.as_str(), "replace"),
            )
            .await;
        match stopped {
            Ok(_) => Ok(()),
            // The unit is not loaded, so pilot-voice is not running.
            Err(zbus::Error::MethodError(name, _, _))
                if name.as_str() == "org.freedesktop.systemd1.NoSuchUnit" =>
            {
                Ok(())
            }
            // No systemd user manager on this bus: the bus itself starts
            // pilot-voice. Cancel a running one (which closes the
            // microphone); one that is not running has nothing to stop,
            // and must not be activated by asking it.
            Err(zbus::Error::MethodError(name, _, _))
                if name.as_str() == "org.freedesktop.DBus.Error.ServiceUnknown" =>
            {
                self.cancel_running().await
            }
            Err(e) => Err(e.into()),
        }
    }
}

impl SystemdVoice {
    async fn cancel_running(&self) -> Result<(), AdapterError> {
        let bus = zbus::fdo::DBusProxy::new(&self.session).await?;
        let name = zbus::names::BusName::try_from(VOICE_BUS_NAME)
            .map_err(|e| AdapterError::Failed(e.to_string()))?;
        if !bus.name_has_owner(name).await? {
            return Ok(());
        }
        log::info!("no systemd user manager: cancelling pilot-voice directly");
        let p =
            zbus::Proxy::new(&self.session, VOICE_BUS_NAME, VOICE_PATH, VOICE_INTERFACE).await?;
        p.call_method("Cancel", &()).await?;
        Ok(())
    }
}

/// `pilot-tts` over its socket. Each request is one JSON line written from
/// a short-lived thread, so a slow or missing speaker never delays a turn.
pub struct TtsSocket {
    pub path: PathBuf,
    /// Utterances sent and not yet answered. A stop with none in flight is
    /// not sent: connecting would socket-activate `pilot-tts` (and load a
    /// voice) only to tell it to stop saying nothing.
    speaking: Arc<AtomicUsize>,
}

impl TtsSocket {
    pub fn new(path: PathBuf) -> TtsSocket {
        TtsSocket {
            path,
            speaking: Arc::default(),
        }
    }

    pub fn default_path() -> Option<PathBuf> {
        std::env::var_os("XDG_RUNTIME_DIR")
            .filter(|v| !v.is_empty())
            .map(|d| PathBuf::from(d).join("shoal-pilot/tts.sock"))
    }

    /// Whether an utterance is in flight.
    pub fn speaking(&self) -> bool {
        self.speaking.load(Ordering::SeqCst) > 0
    }

    fn send(&self, line: String, utterance: bool) {
        let path = self.path.clone();
        let speaking = utterance.then(|| {
            self.speaking.fetch_add(1, Ordering::SeqCst);
            self.speaking.clone()
        });
        let _ = std::thread::Builder::new()
            .name("pilot-tts-client".into())
            .spawn(move || {
                match std::os::unix::net::UnixStream::connect(&path) {
                    Ok(mut s) => {
                        let _ = s.set_write_timeout(Some(Duration::from_secs(2)));
                        if let Err(e) = writeln!(s, "{line}") {
                            log::debug!("pilot-tts: {e}");
                        }
                        // Wait for the reply so the speaker is not cut off
                        // by the connection closing.
                        let _ = s.set_read_timeout(Some(Duration::from_secs(60)));
                        let mut buf = [0u8; 256];
                        let _ = std::io::Read::read(&mut s, &mut buf);
                    }
                    Err(e) => log::debug!("pilot-tts not reachable: {e}"),
                }
                if let Some(speaking) = speaking {
                    speaking.fetch_sub(1, Ordering::SeqCst);
                }
            });
    }
}

impl Speech for TtsSocket {
    fn say(&self, text: &str) {
        self.send(serde_json::json!({ "text": text }).to_string(), true);
    }

    fn stop(&self) {
        if !self.speaking() {
            return;
        }
        self.send(serde_json::json!({ "stop": true }).to_string(), false);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{BufRead as _, BufReader};

    #[test]
    fn tts_socket_sends_json_lines() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tts.sock");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        let tts = TtsSocket::new(path);
        tts.say("Timer set.");
        let (stream, _) = listener.accept().unwrap();
        let mut w = stream.try_clone().unwrap();
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).unwrap();
        assert_eq!(line.trim(), r#"{"text":"Timer set."}"#);
        assert!(tts.speaking());
        // A stop while it speaks gets through.
        tts.stop();
        let (stop, _) = listener.accept().unwrap();
        let mut line = String::new();
        BufReader::new(stop).read_line(&mut line).unwrap();
        assert_eq!(line.trim(), r#"{"stop":true}"#);
        writeln!(w, r#"{{"ok":true}}"#).unwrap();
        for _ in 0..200 {
            if !tts.speaking() {
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        assert!(!tts.speaking());
    }

    #[test]
    fn a_stop_with_nothing_spoken_never_connects() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("tts.sock");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        listener.set_nonblocking(true).unwrap();
        let tts = TtsSocket::new(path);
        tts.stop();
        std::thread::sleep(Duration::from_millis(200));
        // A connection here is what would socket-activate pilot-tts.
        assert!(listener.accept().is_err(), "stop connected to the socket");
    }
}
