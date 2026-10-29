// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! Radios and flight mode through ConnMan on the system bus: technology
//! `Powered` for Wi-Fi, Bluetooth and mobile data, the manager's
//! `OfflineMode` for flight mode (confirmation card, spec section 6.2).

use async_trait::async_trait;
use zbus::Variant as Value;

use super::{AdapterError, DeviceToggles, Toggle};

pub struct ConnMan {
    pub system: zbus::Connection,
}

/// Object path, interface and property for a toggle.
pub fn target(what: Toggle) -> (&'static str, &'static str, &'static str) {
    match what {
        Toggle::Wifi => (
            "/net/connman/technology/wifi",
            "net.connman.Technology",
            "Powered",
        ),
        Toggle::Bluetooth => (
            "/net/connman/technology/bluetooth",
            "net.connman.Technology",
            "Powered",
        ),
        Toggle::MobileData => (
            "/net/connman/technology/cellular",
            "net.connman.Technology",
            "Powered",
        ),
        Toggle::FlightMode => ("/", "net.connman.Manager", "OfflineMode"),
    }
}

#[async_trait]
impl DeviceToggles for ConnMan {
    async fn set(&self, what: Toggle, on: bool) -> Result<(), AdapterError> {
        let (path, iface, prop) = target(what);
        self.system
            .call_method(
                Some("net.connman"),
                path,
                Some(iface),
                "SetProperty",
                &(prop, Value::from(on)),
            )
            .await?;
        Ok(())
    }

    async fn get(&self, what: Toggle) -> Result<bool, AdapterError> {
        let (path, iface, prop) = target(what);
        let reply = self
            .system
            .call_method(Some("net.connman"), path, Some(iface), "GetProperties", &())
            .await?;
        let props: std::collections::HashMap<String, zbus::OwnedVariant> =
            reply.body().deserialize()?;
        props
            .get(prop)
            .and_then(|v| bool::try_from(v).ok())
            .ok_or_else(|| AdapterError::Failed(format!("{prop} not reported")))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn targets() {
        assert_eq!(target(Toggle::FlightMode).2, "OfflineMode");
        assert_eq!(target(Toggle::Wifi).0, "/net/connman/technology/wifi");
    }
}
