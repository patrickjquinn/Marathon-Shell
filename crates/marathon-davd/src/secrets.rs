//! DAV account secrets in the Secret Service's default collection, over a
//! plain session, as items `{service: marathon-dav, account_id: <id>}`.
//! Every error means "try again later": no keyring yet, or it is locked.

use std::collections::HashMap;

use zbus::zvariant::{ObjectPath, OwnedObjectPath, OwnedValue, Value};

#[zbus::proxy(interface = "org.freedesktop.Secret.Service", default_service = "org.freedesktop.secrets", default_path = "/org/freedesktop/secrets")]
trait SecretService {
    fn open_session(&self, algorithm: &str, input: &Value<'_>) -> zbus::Result<(OwnedValue, OwnedObjectPath)>;
    fn search_items(&self, attributes: HashMap<&str, &str>) -> zbus::Result<(Vec<OwnedObjectPath>, Vec<OwnedObjectPath>)>;
    fn read_alias(&self, name: &str) -> zbus::Result<OwnedObjectPath>;
}

#[zbus::proxy(interface = "org.freedesktop.Secret.Collection", default_service = "org.freedesktop.secrets")]
trait Collection {
    fn create_item(&self, properties: HashMap<&str, Value<'_>>, secret: &Secret, replace: bool) -> zbus::Result<(OwnedObjectPath, OwnedObjectPath)>;
}

#[zbus::proxy(interface = "org.freedesktop.Secret.Item", default_service = "org.freedesktop.secrets")]
trait Item {
    fn get_secret(&self, session: &ObjectPath<'_>) -> zbus::Result<Secret>;
    fn delete(&self) -> zbus::Result<OwnedObjectPath>;
}

/// (session, parameters, value, content type).
type Secret = (OwnedObjectPath, Vec<u8>, Vec<u8>, String);

/// The keyring cannot answer now.
#[derive(Debug)]
pub struct Unavailable;

impl From<zbus::Error> for Unavailable {
    fn from(e: zbus::Error) -> Self {
        marathon_rt::log::warn("DavSecrets", e);
        Self
    }
}

fn attributes(id: &str) -> HashMap<&str, &str> {
    HashMap::from([("service", "marathon-dav"), ("account_id", id)])
}

fn none(path: &ObjectPath<'_>) -> bool {
    path.as_str() == "/"
}

async fn session(service: &SecretServiceProxy<'_>) -> Result<OwnedObjectPath, Unavailable> {
    Ok(service.open_session("plain", &Value::from("")).await?.1)
}

pub async fn store(bus: &zbus::Connection, id: &str, label: &str, secret: &str) -> Result<(), Unavailable> {
    let service = SecretServiceProxy::new(bus).await?;
    let session = session(&service).await?;
    let collection = service.read_alias("default").await?;
    if none(&collection) {
        return Err(Unavailable);
    }
    let properties = HashMap::from([
        ("org.freedesktop.Secret.Item.Label", Value::from(label)),
        ("org.freedesktop.Secret.Item.Attributes", Value::from(attributes(id))),
    ]);
    let secret = (session, Vec::new(), secret.as_bytes().to_vec(), "text/plain".to_owned());
    let collection = CollectionProxy::builder(bus).path(collection)?.build().await?;
    let (_, prompt) = collection.create_item(properties, &secret, true).await?;
    if none(&prompt) { Ok(()) } else { Err(Unavailable) }
}

/// The account's secret; `None` when the keyring has none.
pub async fn load(bus: &zbus::Connection, id: &str) -> Result<Option<String>, Unavailable> {
    let service = SecretServiceProxy::new(bus).await?;
    let (unlocked, locked) = service.search_items(attributes(id)).await?;
    let Some(item) = unlocked.into_iter().next() else {
        return if locked.is_empty() { Ok(None) } else { Err(Unavailable) };
    };
    let session = session(&service).await?;
    let item = ItemProxy::builder(bus).path(item)?.build().await?;
    let (_, _, value, _) = item.get_secret(&session).await?;
    Ok(Some(String::from_utf8_lossy(&value).into_owned()))
}

pub async fn remove(bus: &zbus::Connection, id: &str) -> Result<(), Unavailable> {
    let service = SecretServiceProxy::new(bus).await?;
    let (unlocked, locked) = service.search_items(attributes(id)).await?;
    if !locked.is_empty() {
        return Err(Unavailable);
    }
    for item in unlocked {
        let prompt = ItemProxy::builder(bus).path(item)?.build().await?.delete().await?;
        if !none(&prompt) {
            return Err(Unavailable);
        }
    }
    Ok(())
}
