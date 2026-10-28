// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: LicenseRef-Shipwright-Proprietary

//! Media control over MPRIS 2 on the session bus. The target is the player
//! that is playing, else one that is paused, else the first one found.

use async_trait::async_trait;

use super::{AdapterError, Media};
use crate::intents::MediaAction;

const PREFIX: &str = "org.mpris.MediaPlayer2.";
const PATH: &str = "/org/mpris/MediaPlayer2";
const PLAYER: &str = "org.mpris.MediaPlayer2.Player";

pub struct Mpris {
    pub session: zbus::Connection,
}

/// Ranks players by status: Playing, Paused, anything else.
pub fn pick(players: &[(String, String)]) -> Option<&str> {
    let rank = |s: &str| match s {
        "Playing" => 0,
        "Paused" => 1,
        _ => 2,
    };
    players
        .iter()
        .min_by_key(|(_, status)| rank(status))
        .map(|(name, _)| name.as_str())
}

pub fn method(action: MediaAction) -> &'static str {
    match action {
        MediaAction::Play => "Play",
        MediaAction::Pause => "Pause",
        MediaAction::Toggle => "PlayPause",
        MediaAction::Stop => "Stop",
        MediaAction::Next => "Next",
        MediaAction::Previous => "Previous",
    }
}

#[async_trait]
impl Media for Mpris {
    async fn control(&self, action: MediaAction) -> Result<String, AdapterError> {
        let dbus = zbus::fdo::DBusProxy::new(&self.session).await?;
        let mut players = Vec::new();
        for name in dbus.list_names().await? {
            if !name.starts_with(PREFIX) {
                continue;
            }
            let status = match zbus::Proxy::new(&self.session, name.to_string(), PATH, PLAYER).await
            {
                Ok(p) => p
                    .get_property::<String>("PlaybackStatus")
                    .await
                    .unwrap_or_default(),
                Err(_) => String::new(),
            };
            players.push((name.to_string(), status));
        }
        let target = pick(&players)
            .ok_or_else(|| AdapterError::Unavailable("a media player".into()))?
            .to_owned();
        self.session
            .call_method(
                Some(target.as_str()),
                PATH,
                Some(PLAYER),
                method(action),
                &(),
            )
            .await?;
        Ok(target.trim_start_matches(PREFIX).to_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn prefers_playing_then_paused() {
        let p = vec![
            ("org.mpris.MediaPlayer2.a".to_owned(), "Stopped".to_owned()),
            ("org.mpris.MediaPlayer2.b".to_owned(), "Paused".to_owned()),
            ("org.mpris.MediaPlayer2.c".to_owned(), "Playing".to_owned()),
        ];
        assert_eq!(pick(&p), Some("org.mpris.MediaPlayer2.c"));
        assert_eq!(pick(&p[..2]), Some("org.mpris.MediaPlayer2.b"));
        assert_eq!(pick(&[]), None);
        assert_eq!(method(MediaAction::Toggle), "PlayPause");
    }
}
