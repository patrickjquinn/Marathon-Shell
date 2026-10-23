//! marathon-telephonyd on a private bus, as the apps call it.

#![allow(clippy::unwrap_used, reason = "tests")]

use std::collections::HashMap;

use marathon_rt::testing::PrivateBus;
use zbus::zvariant::OwnedValue;
use zbus::Connection;

const BUS: &str = "org.marathonos.Telephony";

async fn call<R: serde::de::DeserializeOwned + zbus::zvariant::Type>(
    bus: &Connection,
    object: &str,
    method: &str,
    body: &(impl serde::Serialize + zbus::zvariant::DynamicType),
) -> zbus::Result<R> {
    let path = format!("/org/marathonos/Shell/{object}");
    let interface = format!("org.marathonos.Shell.{object}1");
    bus.call_method(
        Some(BUS),
        path.as_str(),
        Some(interface.as_str()),
        method,
        body,
    )
    .await?
    .body()
    .deserialize()
}

fn text(row: &HashMap<String, OwnedValue>, key: &str) -> String {
    String::try_from(row[key].try_clone().unwrap()).unwrap()
}

fn rows(list: Vec<OwnedValue>) -> Vec<HashMap<String, OwnedValue>> {
    list.into_iter()
        .map(|v| HashMap::try_from(v).unwrap())
        .collect()
}

#[test]
fn texts_and_calls_are_kept_for_permitted_apps() {
    let Some(mut bus) = PrivateBus::start() else {
        return;
    };
    let home = tempfile::tempdir().unwrap();
    async_io::block_on(async {
        let _shell = bus.shell(&["system"]).await.unwrap();
        bus.run(env!("CARGO_BIN_EXE_marathon-telephonyd"), home.path(), BUS)
            .await
            .unwrap();
        let app = bus.connect().await.unwrap();

        call::<()>(
            &app,
            "Sms",
            "SimulateIncomingSMS",
            &("+1 415 555 0142", "hello"),
        )
        .await
        .unwrap();
        let threads = rows(call(&app, "Sms", "GetConversations", &()).await.unwrap());
        assert_eq!(threads.len(), 1);
        assert_eq!(text(&threads[0], "id"), "+14155550142");
        assert_eq!(text(&threads[0], "lastMessage"), "hello");
        let messages = rows(
            call(&app, "Sms", "GetMessages", &("+14155550142",))
                .await
                .unwrap(),
        );
        assert_eq!(text(&messages[0], "status"), "received");
        assert!(home
            .path()
            .join("data/Marathon OS/Marathon Shell/messages.db")
            .exists());

        call::<()>(
            &app,
            "CallHistory",
            "AddCall",
            &("+14155550142", "missed", 1_i64, 0_i32),
        )
        .await
        .unwrap();
        let calls = rows(call(&app, "CallHistory", "GetHistory", &()).await.unwrap());
        assert_eq!(
            (text(&calls[0], "type"), text(&calls[0], "contactName")),
            ("missed".to_owned(), "Unknown".to_owned())
        );

        let refused = call::<HashMap<String, OwnedValue>>(&app, "Sms", "GetMmsSettings", &()).await;
        assert!(
            matches!(refused, Err(zbus::Error::MethodError(name, _, _)) if name.as_str() == "org.freedesktop.DBus.Error.AccessDenied")
        );
        assert!(!call::<bool>(&app, "Sms", "IsMmsAvailable", &())
            .await
            .unwrap());
    });
}
