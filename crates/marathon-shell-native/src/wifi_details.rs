//! A saved Wi-Fi network as Settings shows it: what `NetworkManager` keeps
//! for it, what the link has while it is in use, and the changes a person
//! can make (auto-join, private address, IP and DNS).

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr};

use zbus::fdo::PropertiesProxy;
use zbus::names::InterfaceName;
use zbus::{ObjectPath, OwnedObjectPath, OwnedVariant as OwnedValue};

use crate::ipc::{value, State};
use crate::network::{NmProxy, NmSettingsProxy, SavedConnectionProxy, Settings};

const NM: &str = "org.freedesktop.NetworkManager";
const ACTIVE: &str = "org.freedesktop.NetworkManager.Connection.Active";
const DEVICE: &str = "org.freedesktop.NetworkManager.Device";
const WIRELESS: &str = "org.freedesktop.NetworkManager.Device.Wireless";
const IP4: &str = "org.freedesktop.NetworkManager.IP4Config";
const IP6: &str = "org.freedesktop.NetworkManager.IP6Config";
const ACCESS_POINT: &str = "org.freedesktop.NetworkManager.AccessPoint";
const WIFI_DEVICE: u32 = 2;

type Sections = HashMap<String, HashMap<String, OwnedValue>>;

struct Saved {
    ssid: String,
    path: OwnedObjectPath,
    settings: Sections,
}

fn text(section: Option<&HashMap<String, OwnedValue>>, key: &str) -> Option<String> {
    String::try_from(section?.get(key)?.try_clone().ok()?).ok()
}

/// A client network's name; none for the hotspot's own profile.
fn client_ssid(all: &Sections) -> Option<String> {
    let wireless = all.get("802-11-wireless")?;
    if text(Some(wireless), "mode").as_deref() == Some("ap") {
        return None;
    }
    let ssid = Vec::<u8>::try_from(wireless.get("ssid")?.try_clone().ok()?).ok()?;
    Some(String::from_utf8_lossy(&ssid).into_owned()).filter(|s| !s.is_empty())
}

async fn saved(bus: &zbus::Connection) -> Vec<Saved> {
    let Ok(settings) = NmSettingsProxy::new(bus).await else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for path in settings.list_connections().await.unwrap_or_default() {
        let Ok(c) = SavedConnectionProxy::builder(bus)
            .path(path.clone())
            .build()
            .await
        else {
            continue;
        };
        let Ok(all) = c.get_settings().await else {
            continue;
        };
        if let Some(ssid) = client_ssid(&all) {
            out.push(Saved {
                ssid,
                path,
                settings: all,
            });
        }
    }
    out
}

async fn props(bus: &zbus::Connection, path: &ObjectPath<'_>, iface: &'static str) -> State {
    let p = PropertiesProxy::builder(bus)
        .destination(NM)
        .path(path.to_owned())
        .cache_properties(zbus::proxy::CacheProperties::No);
    let (Ok(p), Ok(iface)) = (p.build().await, InterfaceName::try_from(iface)) else {
        return State::new();
    };
    p.get_all(iface).await.unwrap_or_default()
}

fn path_of(props: &State, key: &str) -> Option<OwnedObjectPath> {
    OwnedObjectPath::try_from(props.get(key)?.try_clone().ok()?)
        .ok()
        .filter(|p| p.as_str() != "/")
}

/// The Wi-Fi device, and its active connection's settings path, if any.
async fn wifi_link(bus: &zbus::Connection) -> Option<(OwnedObjectPath, Option<OwnedObjectPath>)> {
    let nm = NmProxy::new(bus).await.ok()?;
    for device in nm.get_devices().await.unwrap_or_default() {
        let d = props(bus, &device, DEVICE).await;
        if d.get("DeviceType").and_then(|v| u32::try_from(v).ok()) != Some(WIFI_DEVICE) {
            continue;
        }
        let connection = match path_of(&d, "ActiveConnection") {
            Some(active) => path_of(&props(bus, &active, ACTIVE).await, "Connection"),
            None => None,
        };
        return Some((device, connection));
    }
    None
}

/// Off, Fixed or Rotating, as `cloned-mac-address` reads (on D-Bus, its
/// string form is `assigned-mac-address`); Marathon's default
/// (`wifi.cloned-mac-address=stable-ssid`) is Fixed.
pub(crate) fn private_address_of(cloned: Option<&str>) -> &'static str {
    match cloned {
        Some("permanent" | "preserve") => "off",
        Some("random") => "rotating",
        _ => "fixed",
    }
}

fn cloned_mac_for(choice: &str) -> Option<&'static str> {
    match choice {
        "off" => Some("permanent"),
        "fixed" => Some("stable-ssid"),
        "rotating" => Some("random"),
        _ => None,
    }
}

pub(crate) fn prefix_to_mask(prefix: u32) -> String {
    let bits = if prefix == 0 {
        0
    } else {
        u32::MAX << (32 - prefix.min(32))
    };
    Ipv4Addr::from(bits).to_string()
}

fn mask_to_prefix(mask: &str) -> Option<u32> {
    let bits = u32::from(mask.parse::<Ipv4Addr>().ok()?);
    (bits.leading_ones() + bits.trailing_zeros() == 32).then(|| bits.leading_ones())
}

/// "address/mask/router" as a person types them, checked.
pub(crate) fn parse_manual_ipv4(v: &str) -> Result<(Ipv4Addr, u32, Option<Ipv4Addr>), String> {
    let mut parts = v.split('/').map(str::trim);
    let address = parts
        .next()
        .and_then(|a| a.parse::<Ipv4Addr>().ok())
        .ok_or_else(|| "address".to_owned())?;
    let prefix = parts
        .next()
        .and_then(mask_to_prefix)
        .ok_or_else(|| "mask".to_owned())?;
    let router = match parts.next().filter(|r| !r.is_empty()) {
        Some(r) => Some(
            r.parse::<Ipv4Addr>()
                .ok()
                .ok_or_else(|| "router".to_owned())?,
        ),
        None => None,
    };
    Ok((address, prefix, router))
}

/// DNS servers separated by commas or spaces; IPv4 only, as `ipv4.dns`.
pub(crate) fn parse_dns(v: &str) -> Result<Vec<Ipv4Addr>, String> {
    let servers = v
        .split([',', ' '])
        .filter(|s| !s.trim().is_empty())
        .map(|s| {
            s.trim()
                .parse::<Ipv4Addr>()
                .ok()
                .ok_or_else(|| s.trim().to_owned())
        })
        .collect::<Result<Vec<_>, _>>()?;
    if servers.is_empty() {
        Err(String::new())
    } else {
        Ok(servers)
    }
}

fn addresses(data: Option<&OwnedValue>) -> Vec<(String, u32)> {
    let Some(list) =
        data.and_then(|v| Vec::<HashMap<String, OwnedValue>>::try_from(v.try_clone().ok()?).ok())
    else {
        return Vec::new();
    };
    list.iter()
        .filter_map(|a| {
            let address = String::try_from(a.get("address")?.try_clone().ok()?).ok()?;
            let prefix = a
                .get("prefix")
                .and_then(|p| u32::try_from(p).ok())
                .unwrap_or(0);
            Some((address, prefix))
        })
        .collect()
}

fn dns_of(ipv4: Option<&HashMap<String, OwnedValue>>) -> Vec<String> {
    let Some(ipv4) = ipv4 else { return Vec::new() };
    if let Some(data) = ipv4
        .get("dns-data")
        .and_then(|v| Vec::<String>::try_from(v.try_clone().ok()?).ok())
    {
        return data;
    }
    ipv4.get("dns")
        .and_then(|v| Vec::<u32>::try_from(v.try_clone().ok()?).ok())
        .unwrap_or_default()
        .into_iter()
        .map(|n| Ipv4Addr::from(u32::from_be(n)).to_string())
        .collect()
}

/// Saved networks, the one used most recently first.
pub(crate) async fn saved_networks(bus: &zbus::Connection) -> Vec<State> {
    let mut list: Vec<(u64, String)> = saved(bus)
        .await
        .into_iter()
        .map(|s| {
            let used = s
                .settings
                .get("connection")
                .and_then(|c| c.get("timestamp"))
                .and_then(|t| u64::try_from(t).ok())
                .unwrap_or(0);
            (used, s.ssid)
        })
        .collect();
    list.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    list.dedup_by(|a, b| a.1 == b.1);
    list.into_iter()
        .map(|(used, ssid)| {
            State::from([
                ("ssid".to_owned(), value(ssid)),
                ("lastUsed".to_owned(), value(used)),
            ])
        })
        .collect()
}

pub(crate) async fn details(bus: &zbus::Connection, ssid: &str) -> State {
    let mut out = State::new();
    out.insert("ssid".into(), value(ssid.to_owned()));
    let Some(s) = saved(bus).await.into_iter().find(|s| s.ssid == ssid) else {
        out.insert("saved".into(), value(false));
        return out;
    };
    let section = |name: &str| s.settings.get(name);
    let auto_join = section("connection")
        .and_then(|c| c.get("autoconnect"))
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(true);
    let key_mgmt = text(section("802-11-wireless-security"), "key-mgmt");
    let ipv4 = section("ipv4");
    let manual = text(ipv4, "method").as_deref() == Some("manual");
    let dns = dns_of(ipv4);
    let ignore_auto_dns = ipv4
        .and_then(|i| i.get("ignore-auto-dns"))
        .and_then(|v| bool::try_from(v).ok())
        .unwrap_or(false);
    out.insert("saved".into(), value(true));
    out.insert("autoJoin".into(), value(auto_join));
    out.insert("secured".into(), value(key_mgmt.is_some()));
    out.insert(
        "privateAddress".into(),
        value(private_address_of(
            text(section("802-11-wireless"), "assigned-mac-address").as_deref(),
        )),
    );
    out.insert("ipv4Manual".into(), value(manual));
    if manual {
        if let Some((address, prefix)) = addresses(ipv4.and_then(|i| i.get("address-data")))
            .into_iter()
            .next()
        {
            out.insert("manualAddress".into(), value(address));
            out.insert("manualMask".into(), value(prefix_to_mask(prefix)));
        }
        out.insert(
            "manualRouter".into(),
            value(text(ipv4, "gateway").unwrap_or_default()),
        );
    }
    out.insert(
        "dnsManual".into(),
        value(ignore_auto_dns && !dns.is_empty()),
    );
    out.insert("manualDns".into(), value(dns.join(", ")));

    let Some((device, Some(active))) = wifi_link(bus).await else {
        out.insert("connected".into(), value(false));
        return out;
    };
    out.insert("connected".into(), value(active == s.path));
    if active == s.path {
        live(bus, &device, &mut out).await;
    }
    out
}

/// What the network's link has now: its address, band and IP.
async fn live(bus: &zbus::Connection, device: &OwnedObjectPath, out: &mut State) {
    let d = props(bus, device, DEVICE).await;
    let w = props(bus, device, WIRELESS).await;
    let text_of = |m: &State, k: &str| {
        m.get(k)
            .and_then(|v| String::try_from(v.try_clone().ok()?).ok())
            .unwrap_or_default()
    };
    out.insert("macAddress".into(), value(text_of(&w, "HwAddress")));
    if let Some(ap) = path_of(&w, "ActiveAccessPoint") {
        let ap = props(bus, &ap, ACCESS_POINT).await;
        if let Some(f) = ap.get("Frequency").and_then(|v| u32::try_from(v).ok()) {
            out.insert("frequency".into(), value(f));
        }
    }
    if let Some(b) = w.get("Bitrate").and_then(|v| u32::try_from(v).ok()) {
        out.insert("bitrate".into(), value(b / 1000));
    }
    if let Some(config) = path_of(&d, "Ip4Config") {
        let v4 = props(bus, &config, IP4).await;
        if let Some((address, prefix)) = addresses(v4.get("AddressData")).into_iter().next() {
            out.insert("ipv4Address".into(), value(address));
            out.insert("subnetMask".into(), value(prefix_to_mask(prefix)));
        }
        out.insert("router".into(), value(text_of(&v4, "Gateway")));
        let servers: Vec<String> = v4
            .get("NameserverData")
            .and_then(|v| Vec::<HashMap<String, OwnedValue>>::try_from(v.try_clone().ok()?).ok())
            .unwrap_or_default()
            .iter()
            .filter_map(|n| String::try_from(n.get("address")?.try_clone().ok()?).ok())
            .collect();
        out.insert("dns".into(), value(servers.join(", ")));
    }
    if let Some(config) = path_of(&d, "Ip6Config") {
        let v6 = props(bus, &config, IP6).await;
        let global: Vec<String> = addresses(v6.get("AddressData"))
            .into_iter()
            .filter(|(a, _)| {
                a.parse::<IpAddr>().is_ok_and(
                    |ip| !matches!(ip, IpAddr::V6(v) if v.segments()[0] & 0xffc0 == 0xfe80),
                )
            })
            .map(|(a, _)| a)
            .collect();
        out.insert("ipv6Addresses".into(), value(global.join("\n")));
        out.insert("ipv6Router".into(), value(text_of(&v6, "Gateway")));
    }
}

/// The saved key, for Settings to show once the owner has confirmed.
pub(crate) async fn password(bus: &zbus::Connection, ssid: &str) -> Result<String, String> {
    let s = saved(bus)
        .await
        .into_iter()
        .find(|s| s.ssid == ssid)
        .ok_or_else(|| ssid.to_owned())?;
    let c = SavedConnectionProxy::builder(bus)
        .path(s.path)
        .build()
        .await
        .map_err(|e| e.to_string())?;
    let secrets = c
        .get_secrets("802-11-wireless-security")
        .await
        .map_err(|e| e.to_string())?;
    Ok(text(secrets.get("802-11-wireless-security"), "psk").unwrap_or_default())
}

fn borrowed(all: &Sections) -> Result<Settings<'_>, String> {
    all.iter()
        .map(|(name, section)| {
            let section = section
                .iter()
                .map(|(k, v)| Ok((k.as_str(), (**v).try_clone().map_err(|e| e.to_string())?)))
                .collect::<Result<HashMap<_, _>, String>>()?;
            Ok((name.as_str(), section))
        })
        .collect()
}

/// Changes one thing about a saved network and, if it is in use, joins it
/// again so the change takes. Err says what was wrong with the value.
pub(crate) async fn set_option(
    bus: &zbus::Connection,
    ssid: &str,
    key: &str,
    v: &str,
) -> Result<(), String> {
    let s = saved(bus)
        .await
        .into_iter()
        .find(|s| s.ssid == ssid)
        .ok_or_else(|| ssid.to_owned())?;
    let c = SavedConnectionProxy::builder(bus)
        .path(s.path.clone())
        .build()
        .await
        .map_err(|e| e.to_string())?;
    let mut all = s.settings;
    // Update replaces the profile; keep its key, which GetSettings leaves out.
    if all.contains_key("802-11-wireless-security") {
        if let Ok(secrets) = c.get_secrets("802-11-wireless-security").await {
            for (name, section) in secrets {
                all.entry(name).or_default().extend(section);
            }
        }
    }
    let mut rejoin = true;
    match key {
        "autoJoin" => {
            all.entry("connection".into())
                .or_default()
                .insert("autoconnect".into(), value(v == "true"));
            rejoin = false;
        }
        "privateAddress" => {
            let mac = cloned_mac_for(v).ok_or_else(|| v.to_owned())?;
            all.entry("802-11-wireless".into())
                .or_default()
                .insert("assigned-mac-address".into(), value(mac.to_owned()));
        }
        "ipv4" => {
            let ipv4 = all.entry("ipv4".into()).or_default();
            ipv4.remove("addresses");
            ipv4.remove("address-data");
            ipv4.remove("gateway");
            if v == "auto" {
                ipv4.insert("method".into(), value("auto".to_owned()));
            } else {
                let (address, prefix, router) = parse_manual_ipv4(v)?;
                let entry = HashMap::from([
                    ("address".to_owned(), value(address.to_string())),
                    ("prefix".to_owned(), value(prefix)),
                ]);
                ipv4.insert("method".into(), value("manual".to_owned()));
                ipv4.insert("address-data".into(), value(vec![entry]));
                if let Some(router) = router {
                    ipv4.insert("gateway".into(), value(router.to_string()));
                }
            }
        }
        "dns" => {
            let ipv4 = all.entry("ipv4".into()).or_default();
            ipv4.remove("dns-data");
            if v == "auto" {
                ipv4.remove("dns");
                ipv4.insert("ignore-auto-dns".into(), value(false));
            } else {
                let servers: Vec<u32> = parse_dns(v)?
                    .into_iter()
                    .map(|a| u32::from(a).to_be())
                    .collect();
                ipv4.insert("dns".into(), value(servers));
                ipv4.insert("ignore-auto-dns".into(), value(true));
            }
        }
        _ => return Err(key.to_owned()),
    }
    c.update(borrowed(&all)?).await.map_err(|e| e.to_string())?;
    if rejoin {
        if let Some((device, Some(active))) = wifi_link(bus).await {
            if active == s.path {
                let nm = NmProxy::new(bus).await.map_err(|e| e.to_string())?;
                nm.activate_connection(
                    &s.path,
                    &device,
                    &ObjectPath::try_from("/").map_err(|e| e.to_string())?,
                )
                .await
                .map_err(|e| e.to_string())?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{parse_dns, parse_manual_ipv4, prefix_to_mask, private_address_of};
    use std::net::Ipv4Addr;

    #[test]
    fn private_address_reads_as_settings_shows_it() {
        assert_eq!(private_address_of(None), "fixed");
        assert_eq!(private_address_of(Some("stable-ssid")), "fixed");
        assert_eq!(private_address_of(Some("permanent")), "off");
        assert_eq!(private_address_of(Some("random")), "rotating");
    }

    #[test]
    fn masks_and_manual_addresses() {
        assert_eq!(prefix_to_mask(22), "255.255.252.0");
        assert_eq!(prefix_to_mask(24), "255.255.255.0");
        assert_eq!(
            parse_manual_ipv4("192.168.1.20/255.255.255.0/192.168.1.1"),
            Ok((
                Ipv4Addr::new(192, 168, 1, 20),
                24,
                Some(Ipv4Addr::new(192, 168, 1, 1))
            ))
        );
        assert_eq!(
            parse_manual_ipv4("192.168.1.20/255.0.255.0/"),
            Err("mask".to_owned())
        );
        assert_eq!(
            parse_manual_ipv4("1.2.3/255.255.255.0/"),
            Err("address".to_owned())
        );
    }

    #[test]
    fn dns_servers_by_comma_or_space() {
        assert_eq!(
            parse_dns("1.1.1.1, 9.9.9.9"),
            Ok(vec![Ipv4Addr::new(1, 1, 1, 1), Ipv4Addr::new(9, 9, 9, 9)])
        );
        assert_eq!(parse_dns("1.1.1.1 nope"), Err("nope".to_owned()));
        assert!(parse_dns(" ").is_err());
    }
}
