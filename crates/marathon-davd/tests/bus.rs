//! marathon-davd on a private bus, as the apps and the shell call it.

#![allow(clippy::unwrap_used, reason = "tests")]

use std::collections::HashMap;

use marathon_rt::testing::PrivateBus;
use zbus::zvariant::OwnedValue;
use zbus::Connection;

const BUS: &str = "org.marathonos.Dav";

async fn call<R: serde::de::DeserializeOwned + zbus::zvariant::Type>(bus: &Connection, object: &str, method: &str, body: &(impl serde::Serialize + zbus::zvariant::DynamicType)) -> zbus::Result<R> {
    let path = format!("/org/marathonos/Shell/{object}");
    let interface = format!("org.marathonos.Shell.{object}1");
    bus.call_method(Some(BUS), path.as_str(), Some(interface.as_str()), method, body).await?.body().deserialize()
}

fn text(row: &HashMap<String, OwnedValue>, key: &str) -> String {
    String::try_from(row[key].try_clone().unwrap()).unwrap()
}

#[test]
fn the_address_book_answers_permitted_callers() {
    let Some(mut bus) = PrivateBus::start() else { return };
    let home = tempfile::tempdir().unwrap();
    async_io::block_on(async {
        let _shell = bus.shell(&["system"]).await.unwrap();
        bus.run(env!("CARGO_BIN_EXE_marathon-davd"), home.path(), BUS).await.unwrap();
        let app = bus.connect().await.unwrap();

        call::<()>(&app, "Contacts", "AddContact", &("Maya Chen", "+1 415 555 0142", "maya@example.com")).await.unwrap();
        let all: Vec<OwnedValue> = call(&app, "Contacts", "GetContacts", &()).await.unwrap();
        let first = HashMap::<String, OwnedValue>::try_from(all.into_iter().next().unwrap()).unwrap();
        assert_eq!(text(&first, "name"), "Maya Chen");
        let found: HashMap<String, OwnedValue> = call(&app, "Contacts", "GetContactByNumber", &("4155550142",)).await.unwrap();
        assert_eq!(text(&found, "email"), "maya@example.com");
        let none: HashMap<String, OwnedValue> = call(&app, "Contacts", "GetContactByNumber", &("999",)).await.unwrap();
        assert!(!none.contains_key("name"));
        assert!(home.path().join("data/Marathon OS/Marathon Shell/marathon/contacts/Maya_Chen_1.vcf").exists());

        let refused = call::<Vec<OwnedValue>>(&app, "Dav", "ListAccounts", &()).await;
        assert!(matches!(refused, Err(zbus::Error::MethodError(name, Some(text), _))
            if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied" && text == "Missing permission: system"));
    });
}
