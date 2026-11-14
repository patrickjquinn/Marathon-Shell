//! The mobile data APN: the one in use, the one the person set, and the
//! carrier's from the device's APN database. With none set, data rides the
//! LTE attach bearer, whose APN the modem's bring-up takes from the same
//! database for the SIM (q25-modem-init).

use std::collections::HashMap;

use zbus::fdo::{ObjectManagerProxy, PropertiesProxy};
use zbus::names::InterfaceName;
use zbus::{OwnedObjectPath, OwnedVariant as OwnedValue, Variant as Value};

use crate::network::{NmProxy, SavedConnectionProxy, Settings};

const MM: &str = "org.freedesktop.ModemManager1";
const APNS: &str = "/usr/share/mobile-broadband-provider-info/apns-conf.xml";

/// A carrier APN: (name, apn, user, password).
pub type Suggestion = (String, String, String, String);

/// The APN data rides now, the one set on the profile ("" for automatic),
/// and the carrier's internet APNs for the SIM.
pub async fn read(bus: &zbus::Connection) -> (String, String, Vec<Suggestion>) {
    let (live, operator) = modem_apn(bus).await.unwrap_or_default();
    let custom = crate::modem::gsm_profile(bus)
        .await
        .and_then(|(_, settings)| {
            settings
                .get("gsm")?
                .get("apn")
                .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
        })
        .unwrap_or_default();
    let suggestions =
        std::fs::read_to_string(APNS).map_or_default(|xml| carrier_apns(&xml, &operator));
    (live, custom, suggestions)
}

/// Sets the profile's APN and credentials, "" for automatic, and brings the
/// data back up on it if it is on.
pub async fn set(
    bus: &zbus::Connection,
    apn: &str,
    user: &str,
    password: &str,
) -> zbus::Result<()> {
    let Some((path, mut settings)) = crate::modem::gsm_profile(bus).await else {
        return Err(zbus::Error::Failure("no mobile data profile".to_owned()));
    };
    let gsm = settings.entry("gsm".to_owned()).or_default();
    for (key, value) in [("apn", apn), ("username", user), ("password", password)] {
        if value.is_empty() {
            gsm.remove(key);
        } else {
            gsm.insert(
                key.to_owned(),
                OwnedValue::from(zbus::Str::from(value.to_owned())),
            );
        }
    }
    let on = settings
        .get("connection")
        .and_then(|c| c.get("autoconnect"))
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(true);
    let update: Settings<'_> = settings
        .iter()
        .map(|(group, props)| {
            let props = props
                .iter()
                .filter_map(|(k, v)| Some((k.as_str(), Value::try_from(v).ok()?)))
                .collect();
            (group.as_str(), props)
        })
        .collect();
    SavedConnectionProxy::builder(bus)
        .path(path.clone())
        .build()
        .await?
        .update(update)
        .await?;
    if on {
        let none = zbus::ObjectPath::from_static_str_unchecked("/");
        NmProxy::new(bus)
            .await?
            .activate_connection(&path, &none, &none)
            .await?;
    }
    Ok(())
}

/// The connected bearer's APN, else the LTE attach bearer's; and the SIM's
/// MCC+MNC.
async fn modem_apn(bus: &zbus::Connection) -> zbus::Result<(String, String)> {
    let objects = ObjectManagerProxy::builder(bus)
        .destination(MM)
        .path("/org/freedesktop/ModemManager1")
        .build()
        .await?
        .get_managed_objects()
        .await?;
    let Some((_, interfaces)) = objects.iter().find(|(_, i)| {
        i.keys()
            .any(|k| k.as_str() == "org.freedesktop.ModemManager1.Modem")
    }) else {
        return Ok(Default::default());
    };
    let get = |interface: &str, key: &str| -> Option<OwnedValue> {
        interfaces
            .iter()
            .find(|(k, _)| k.as_str() == interface)?
            .1
            .get(key)?
            .try_clone()
            .ok()
    };
    let apn_of = |settings: HashMap<String, OwnedValue>| {
        settings
            .get("apn")
            .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
            .filter(|a| !a.is_empty())
    };
    // The connected bearer's APN; with none (data on the attach PDN), the
    // attach bearer's as the network granted it, then as it was asked for.
    let mut live = None;
    let bearers = get("org.freedesktop.ModemManager1.Modem", "Bearers")
        .and_then(|v| Vec::<OwnedObjectPath>::try_from(v).ok())
        .unwrap_or_default();
    for bearer in bearers {
        if let Some((true, apn)) = bearer_apn(bus, bearer).await {
            live = apn;
            break;
        }
    }
    if live.is_none() {
        if let Some(initial) = get(
            "org.freedesktop.ModemManager1.Modem.Modem3gpp",
            "InitialEpsBearer",
        )
        .and_then(|v| OwnedObjectPath::try_from(v).ok())
        .filter(|p| p.as_str() != "/")
        {
            live = bearer_apn(bus, initial).await.and_then(|(_, apn)| apn);
        }
    }
    let live = live
        .or_else(|| {
            get(
                "org.freedesktop.ModemManager1.Modem.Modem3gpp",
                "InitialEpsBearerSettings",
            )
            .and_then(|v| HashMap::<String, OwnedValue>::try_from(v).ok())
            .and_then(apn_of)
        })
        .map_or_default(|apn| network_name(&apn).to_owned());
    let mut operator = String::new();
    if let Some(sim) = get("org.freedesktop.ModemManager1.Modem", "Sim")
        .and_then(|v| OwnedObjectPath::try_from(v).ok())
        .filter(|p| p.as_str() != "/")
    {
        operator = PropertiesProxy::builder(bus)
            .destination(MM)
            .path(sim)
            .build()
            .await?
            .get(
                InterfaceName::from_static_str_unchecked("org.freedesktop.ModemManager1.Sim"),
                "OperatorIdentifier",
            )
            .await
            .ok()
            .and_then(|v| String::try_from(v).ok())
            .unwrap_or_default();
    }
    Ok((live, operator))
}

/// A bearer's connected state and APN.
async fn bearer_apn(
    bus: &zbus::Connection,
    path: OwnedObjectPath,
) -> Option<(bool, Option<String>)> {
    let props = PropertiesProxy::builder(bus)
        .destination(MM)
        .path(path)
        .build()
        .await
        .ok()?;
    let interface =
        InterfaceName::from_static_str_unchecked("org.freedesktop.ModemManager1.Bearer");
    let connected = props
        .get(interface.clone(), "Connected")
        .await
        .ok()
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(false);
    let apn = props
        .get(interface, "Properties")
        .await
        .ok()
        .and_then(|v| HashMap::<String, OwnedValue>::try_from(v).ok())
        .and_then(|settings| {
            settings
                .get("apn")
                .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
        })
        .filter(|a| !a.is_empty());
    Some((connected, apn))
}

/// An APN without the operator part the network appends (TS 23.003:
/// "<apn>.mnc<MNC>.mcc<MCC>.gprs").
fn network_name(apn: &str) -> &str {
    let lower = apn.to_ascii_lowercase();
    match lower.find(".mnc") {
        Some(at) if lower.strip_suffix(".gprs").is_some() && lower[at..].contains(".mcc") => {
            &apn[..at]
        }
        _ => apn,
    }
}

/// The internet ("default") APNs of `operator` (MCC+MNC) in an AOSP
/// apns-conf.xml, in its order.
fn carrier_apns(xml: &str, operator: &str) -> Vec<Suggestion> {
    let mut found = Vec::new();
    if operator.len() < 5 {
        return found;
    }
    let (mcc, mnc) = operator.split_at(3);
    let mut reader = quick_xml::Reader::from_str(xml);
    loop {
        match reader.read_event() {
            Ok(quick_xml::events::Event::Start(e) | quick_xml::events::Event::Empty(e))
                if AsRef::<str>::as_ref(&e.name()) == "apn" =>
            {
                let attr = |name: &str| {
                    e.try_get_attribute(name)
                        .ok()
                        .flatten()
                        .and_then(|a| {
                            a.normalized_value(quick_xml::XmlVersion::default())
                                .ok()
                                .map(std::borrow::Cow::into_owned)
                        })
                        .unwrap_or_default()
                };
                let internet = attr("type")
                    .split(',')
                    .any(|t| matches!(t.trim(), "default" | "*"))
                    || attr("type").is_empty();
                if attr("mcc") == mcc && attr("mnc") == mnc && internet {
                    found.push((attr("carrier"), attr("apn"), attr("user"), attr("password")));
                }
            }
            Ok(quick_xml::events::Event::Eof) | Err(_) => break,
            _ => {}
        }
    }
    found
}

#[cfg(test)]
mod tests {
    use super::{carrier_apns, network_name};

    #[test]
    fn drops_the_operator_part() {
        assert_eq!(
            network_name("wap.mymeteor.ie.mnc003.mcc272.gprs"),
            "wap.mymeteor.ie"
        );
        assert_eq!(network_name("internet"), "internet");
    }

    #[test]
    fn picks_the_carriers_internet_apns() {
        let xml = r#"<apns>
  <apn carrier="Broadband To Go" mcc="272" mnc="03" apn="broadband.eircommbb.ie" type="default,supl"/>
  <apn carrier="MMS" mcc="272" mnc="03" apn="mms.mymeteor.ie" user="my" password="wap" type="mms"/>
  <apn carrier="Meteor Data" mcc="272" mnc="03" apn="data.mymeteor.ie" user="my" password="meteor" type="default,supl"/>
  <apn carrier="Three" mcc="272" mnc="05" apn="3ireland.ie" type="default"/>
</apns>"#;
        let found = carrier_apns(xml, "27203");
        assert_eq!(
            found.iter().map(|s| s.1.as_str()).collect::<Vec<_>>(),
            ["broadband.eircommbb.ie", "data.mymeteor.ie"]
        );
        assert_eq!(found[1].2, "my");
        assert_eq!(carrier_apns(xml, ""), Vec::new());
    }
}
