//! radiod as an MPRIS player (`org.mpris.MediaPlayer2`), so the lock
//! screen and the shell's media controls show and drive it.

use zbus::{fdo, interface};

use crate::{Core, Dict, Radio};

pub struct Root;

#[allow(
    clippy::unused_self,
    reason = "MPRIS properties a radio answers the same way"
)]
#[interface(name = "org.mpris.MediaPlayer2")]
impl Root {
    fn raise(&self) {}

    fn quit(&self) {}

    #[zbus(property)]
    fn can_quit(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_raise(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn has_track_list(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn identity(&self) -> &'static str {
        "Radio"
    }

    #[zbus(property)]
    fn desktop_entry(&self) -> &'static str {
        "radio"
    }

    #[zbus(property)]
    fn supported_uri_schemes(&self) -> Vec<String> {
        Vec::new()
    }

    #[zbus(property)]
    fn supported_mime_types(&self) -> Vec<String> {
        Vec::new()
    }
}

pub struct Player(pub Core);

#[allow(
    clippy::unused_self,
    reason = "MPRIS properties a radio answers the same way"
)]
#[interface(name = "org.mpris.MediaPlayer2.Player")]
impl Player {
    async fn play(&self) -> fdo::Result<()> {
        self.0.act(Radio::resume).await
    }

    async fn pause(&self) -> fdo::Result<()> {
        self.stop().await
    }

    async fn stop(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                r.stop();
                Ok(())
            })
            .await
    }

    async fn play_pause(&self) -> fdo::Result<()> {
        self.0
            .act(|r| {
                if r.status.sounding() {
                    r.stop();
                    Ok(())
                } else {
                    r.resume()
                }
            })
            .await
    }

    async fn next(&self) -> fdo::Result<()> {
        self.0.act(|r| r.step(true)).await
    }

    async fn previous(&self) -> fdo::Result<()> {
        self.0.act(|r| r.step(false)).await
    }

    #[zbus(property)]
    async fn playback_status(&self) -> String {
        let sounding = self.0.radio.with(|r| r.status.sounding()).await;
        if sounding { "Playing" } else { "Stopped" }.to_owned()
    }

    #[zbus(property)]
    async fn metadata(&self) -> Dict {
        self.0.radio.with(|r| r.metadata()).await
    }

    #[zbus(property)]
    fn can_go_next(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_go_previous(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_play(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_pause(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn can_seek(&self) -> bool {
        false
    }

    #[zbus(property)]
    fn can_control(&self) -> bool {
        true
    }

    #[zbus(property)]
    fn position(&self) -> i64 {
        0
    }

    #[zbus(property)]
    fn rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn minimum_rate(&self) -> f64 {
        1.0
    }

    #[zbus(property)]
    fn maximum_rate(&self) -> f64 {
        1.0
    }
}
