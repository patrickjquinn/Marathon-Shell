//! marathon-medialibd on a private bus, as Gallery calls it.

#![allow(clippy::unwrap_used, reason = "tests")]

use std::collections::HashMap;
use std::time::Duration;

use futures_lite::StreamExt;
use marathon_rt::testing::PrivateBus;
use zbus::OwnedVariant as OwnedValue;
use zbus::{Connection, MatchRule, MessageStream};

const BUS: &str = "org.marathonos.MediaLibrary";
const PATH: &str = "/org/marathonos/Shell/MediaLibrary";
const INTERFACE: &str = "org.marathonos.Shell.MediaLibrary1";

async fn call<R: serde::de::DeserializeOwned + zbus::Type>(
    bus: &Connection,
    method: &str,
    body: &(impl serde::Serialize + zbus::DynamicType),
) -> zbus::Result<R> {
    bus.call_method(Some(BUS), PATH, Some(INTERFACE), method, body)
        .await?
        .body()
        .deserialize()
}

#[test]
fn a_scan_finds_the_pictures() {
    let Some(mut bus) = PrivateBus::start() else {
        return;
    };
    let home = tempfile::tempdir().unwrap();
    let pictures = home.path().join("Pictures/Trip");
    std::fs::create_dir_all(&pictures).unwrap();
    image::RgbImage::new(64, 48)
        .save(pictures.join("a.png"))
        .unwrap();
    async_io::block_on(async {
        let _shell = bus.shell(&[]).await.unwrap();
        bus.run(env!("CARGO_BIN_EXE_marathon-medialibd"), home.path(), BUS)
            .await
            .unwrap();
        let app = bus.connect().await.unwrap();
        let rule = MatchRule::builder()
            .msg_type(zbus::message::Type::Signal)
            .interface(INTERFACE)
            .member("ScanComplete")
            .build();
        let mut done = MessageStream::for_match_rule(rule.unwrap(), &app, None)
            .await
            .unwrap();
        call::<()>(&app, "ScanLibraryAsync", &()).await.unwrap();
        let finished = futures_lite::future::or(async { done.next().await.is_some() }, async {
            async_io::Timer::after(Duration::from_secs(10)).await;
            false
        });
        assert!(finished.await);
        assert_eq!(call::<i32>(&app, "PhotoCount", &()).await.unwrap(), 1);
        let photos: Vec<OwnedValue> = call(&app, "GetPhotos", &("Trip",)).await.unwrap();
        let photo =
            HashMap::<String, OwnedValue>::try_from(photos.into_iter().next().unwrap()).unwrap();
        let path = String::try_from(photo["path"].try_clone().unwrap()).unwrap();
        assert!(path.starts_with("file://") && path.ends_with("Trip/a.png"));
    });
}
