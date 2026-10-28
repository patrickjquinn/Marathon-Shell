// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Calls through oFono on the system bus (`org.ofono`,
//! `VoiceCallManager.Dial`). Always behind a confirmation card.
//!
//! SMS is deliberately not sent through oFono's `MessageManager`: a message
//! sent that way bypasses commhistory and never appears in the Messages
//! app. The right path is Telepathy (telepathy-ring), which is device work;
//! until then `messages.send` reports itself unavailable.

use async_trait::async_trait;
use zbus::zvariant::OwnedObjectPath;

use super::{AdapterError, Telephony};

pub struct Ofono {
    pub system: zbus::Connection,
}

/// Digits, `+`, `*`, `#` and `p`/`w` pauses only: anything else is not a
/// number the modem should see.
pub fn dialable(number: &str) -> Option<String> {
    let n: String = number
        .chars()
        .filter(|c| !matches!(c, ' ' | '-' | '(' | ')' | '.'))
        .collect();
    let ok = !n.is_empty()
        && n.len() <= 32
        && n.chars().enumerate().all(|(i, c)| {
            c.is_ascii_digit() || matches!(c, '*' | '#' | 'p' | 'w') || (c == '+' && i == 0)
        });
    ok.then_some(n)
}

/// What a modem says about itself, as far as choosing one to call from
/// needs: its object path, whether it is online, and its interfaces.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModemInfo {
    pub path: String,
    pub online: bool,
    pub interfaces: Vec<String>,
}

impl ModemInfo {
    fn has(&self, interface: &str) -> bool {
        self.interfaces.iter().any(|i| i == interface)
    }
}

/// Where the modems come from: oFono on the system bus, or a fake in tests.
#[async_trait]
pub trait Modems: Send + Sync {
    /// The SIM the person chose for calls (Settings > Dual SIM), from
    /// Sailfish's oFono: `org.nemomobile.ofono.ModemManager`
    /// `GetDefaultVoiceModem`. None when that interface is missing (not
    /// Sailfish's oFono) or nothing is chosen.
    async fn default_voice_modem(&self) -> Option<String>;
    /// `org.ofono.Manager.GetModems`.
    async fn modems(&self) -> Result<Vec<ModemInfo>, AdapterError>;
}

/// The modem to call from: the default voice modem the person chose (dual
/// SIM phones such as the Xperia 10 II have two modems), when it is one of
/// the modems; else the first online modem with a SIM and voice calls; else
/// the first online one with voice calls; else the first with voice calls;
/// else the first modem.
pub async fn choose_modem(source: &dyn Modems) -> Result<String, AdapterError> {
    let modems = source.modems().await?;
    if let Some(default) = source.default_voice_modem().await {
        if modems.iter().any(|m| m.path == default) {
            return Ok(default);
        }
    }
    let voice = |m: &&ModemInfo| m.has("org.ofono.VoiceCallManager");
    modems
        .iter()
        .find(|m| m.online && m.has("org.ofono.SimManager") && voice(m))
        .or_else(|| modems.iter().find(|m| m.online && voice(m)))
        .or_else(|| modems.iter().find(voice))
        .or_else(|| modems.first())
        .map(|m| m.path.clone())
        .ok_or_else(|| AdapterError::Unavailable("a modem".into()))
}

#[async_trait]
impl Modems for Ofono {
    async fn default_voice_modem(&self) -> Option<String> {
        let reply = self
            .system
            .call_method(
                Some("org.ofono"),
                "/",
                Some("org.nemomobile.ofono.ModemManager"),
                "GetDefaultVoiceModem",
                &(),
            )
            .await
            .ok()?;
        // An object path ("/" or "" when none is chosen); some releases
        // answer with a string.
        let body = reply.body();
        let path = body
            .deserialize::<OwnedObjectPath>()
            .map(|p| p.as_str().to_owned())
            .or_else(|_| body.deserialize::<String>())
            .ok()?;
        (!path.is_empty() && path != "/").then_some(path)
    }

    async fn modems(&self) -> Result<Vec<ModemInfo>, AdapterError> {
        let reply = self
            .system
            .call_method(
                Some("org.ofono"),
                "/",
                Some("org.ofono.Manager"),
                "GetModems",
                &(),
            )
            .await?;
        let modems: Vec<(
            OwnedObjectPath,
            std::collections::HashMap<String, zbus::zvariant::OwnedValue>,
        )> = reply.body().deserialize()?;
        Ok(modems
            .into_iter()
            .map(|(path, props)| ModemInfo {
                path: path.as_str().to_owned(),
                online: props
                    .get("Online")
                    .and_then(|v| bool::try_from(v).ok())
                    .unwrap_or(false),
                interfaces: props
                    .get("Interfaces")
                    .and_then(|v| v.try_clone().ok())
                    .and_then(|v| Vec::<String>::try_from(v).ok())
                    .unwrap_or_default(),
            })
            .collect())
    }
}

#[async_trait]
impl Telephony for Ofono {
    async fn dial(&self, number: &str) -> Result<(), AdapterError> {
        let n =
            dialable(number).ok_or_else(|| AdapterError::Failed("not a phone number".into()))?;
        let modem = choose_modem(self).await?;
        self.system
            .call_method(
                Some("org.ofono"),
                modem.as_str(),
                Some("org.ofono.VoiceCallManager"),
                "Dial",
                &(n.as_str(), "default"),
            )
            .await?;
        Ok(())
    }

    async fn send_sms(&self, _: &str, _: &str) -> Result<(), AdapterError> {
        Err(AdapterError::Unavailable(
            "sending messages (needs the Telepathy path)".into(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dialable_numbers() {
        assert_eq!(
            dialable("+358 40-123 (4567)").as_deref(),
            Some("+358401234567")
        );
        assert_eq!(dialable("*100#").as_deref(), Some("*100#"));
        assert_eq!(dialable("12+3"), None);
        assert_eq!(dialable("call me"), None);
        assert_eq!(dialable(""), None);
    }

    /// oFono as a dual SIM Xperia 10 II shows it: two modems, the second
    /// chosen for calls.
    struct Fake {
        default: Option<&'static str>,
        modems: Vec<ModemInfo>,
    }

    #[async_trait]
    impl Modems for Fake {
        async fn default_voice_modem(&self) -> Option<String> {
            self.default.map(str::to_owned)
        }
        async fn modems(&self) -> Result<Vec<ModemInfo>, AdapterError> {
            Ok(self.modems.clone())
        }
    }

    fn modem(path: &str, online: bool, sim: bool) -> ModemInfo {
        let mut interfaces = vec!["org.ofono.VoiceCallManager".to_owned()];
        if sim {
            interfaces.push("org.ofono.SimManager".to_owned());
        }
        ModemInfo {
            path: path.to_owned(),
            online,
            interfaces,
        }
    }

    fn block<T>(f: impl std::future::Future<Output = T>) -> T {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap()
            .block_on(f)
    }

    #[test]
    fn the_chosen_voice_sim_is_used() {
        let fake = Fake {
            default: Some("/ril_1"),
            modems: vec![modem("/ril_0", true, true), modem("/ril_1", true, true)],
        };
        assert_eq!(block(choose_modem(&fake)).unwrap(), "/ril_1");
    }

    #[test]
    fn without_a_choice_the_first_online_modem_with_a_sim() {
        // SIM slot 1 empty and off, slot 2 in use.
        let fake = Fake {
            default: None,
            modems: vec![modem("/ril_0", false, false), modem("/ril_1", true, true)],
        };
        assert_eq!(block(choose_modem(&fake)).unwrap(), "/ril_1");
        // A default that is not one of the modems (stale) is ignored.
        let fake = Fake {
            default: Some("/ril_9"),
            modems: vec![modem("/ril_0", true, false), modem("/ril_1", true, true)],
        };
        assert_eq!(block(choose_modem(&fake)).unwrap(), "/ril_1");
        // Nothing online: the first that can make calls (emergency calls).
        let fake = Fake {
            default: None,
            modems: vec![modem("/ril_0", false, false), modem("/ril_1", false, true)],
        };
        assert_eq!(block(choose_modem(&fake)).unwrap(), "/ril_0");
        let fake = Fake {
            default: None,
            modems: vec![],
        };
        assert!(block(choose_modem(&fake)).is_err());
    }
}
