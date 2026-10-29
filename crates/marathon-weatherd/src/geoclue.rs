//! One city-accuracy fix from `GeoClue2` on the system bus. `GeoClue` can take
//! 90 s to come up without Wi-Fi or a SIM, so the whole exchange, from
//! connecting to the first `LocationUpdated`, runs under one timeout.
//! Dropping the connection releases the `GeoClue` client.

use std::time::Duration;

use futures_lite::{future, StreamExt};
use zbus::OwnedObjectPath;
use zbus::{Connection, Proxy};

const SERVICE: &str = "org.freedesktop.GeoClue2";
const DESKTOP_ID: &str = "marathon-weather";
const ACCURACY_CITY: u32 = 4;

async fn proxy(
    conn: &Connection,
    path: OwnedObjectPath,
    iface: &'static str,
) -> zbus::Result<Proxy<'static>> {
    Proxy::new(conn, SERVICE, path, iface).await
}

async fn fix() -> zbus::Result<(f64, f64)> {
    let conn = Connection::system().await?;
    let manager = Proxy::new(
        &conn,
        SERVICE,
        "/org/freedesktop/GeoClue2/Manager",
        "org.freedesktop.GeoClue2.Manager",
    )
    .await?;
    let client_path: OwnedObjectPath = manager.call("GetClient", &()).await?;
    let client = proxy(&conn, client_path, "org.freedesktop.GeoClue2.Client").await?;
    client.set_property("DesktopId", DESKTOP_ID).await?;
    client
        .set_property("RequestedAccuracyLevel", ACCURACY_CITY)
        .await?;
    let mut updates = client.receive_signal("LocationUpdated").await?;
    client.call::<_, _, ()>("Start", &()).await?;
    let update = updates
        .next()
        .await
        .ok_or_else(|| zbus::Error::Failure("GeoClue went away".into()))?;
    let (_old, new): (OwnedObjectPath, OwnedObjectPath) = update.body().deserialize()?;
    let location = proxy(&conn, new, "org.freedesktop.GeoClue2.Location").await?;
    Ok((
        location.get_property("Latitude").await?,
        location.get_property("Longitude").await?,
    ))
}

pub fn locate(timeout: Duration) -> Result<(f64, f64), String> {
    zbus::block_on(future::or(
        async { fix().await.map_err(|e| e.to_string()) },
        async {
            async_io::Timer::after(timeout).await;
            Err("GeoClue timed out".to_owned())
        },
    ))
}
