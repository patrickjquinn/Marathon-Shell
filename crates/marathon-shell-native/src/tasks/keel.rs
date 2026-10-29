//! The shell's Keel Actions (`org.shipwright.Keel.Actions` on
//! `org.marathonos.shell`, manifest shell/dbus/keel-actions.json): navigation
//! an app cannot offer, for keel-mcp. Processes the shell started (its apps)
//! may only Describe.

use std::collections::HashMap;
use std::sync::LazyLock;

use serde_json::{json, Map, Value};
use zbus::message::Header;
use zbus::OwnedVariant as OwnedValue;

use super::{launch::descends_from, q, Qt};
use crate::{apps, display, io, ipc, log};

const MANIFEST: &str = include_str!("../../../../shell/dbus/keel-actions.json");

/// The manifest's tools by action name.
static TOOLS: LazyLock<HashMap<String, Value>> = LazyLock::new(|| {
    let manifest: Value = serde_json::from_str(MANIFEST).unwrap_or_default();
    manifest["tools"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(|t| {
            Some((
                t["_meta"]["org.shipwright.keel/action"]
                    .as_str()?
                    .to_owned(),
                t.clone(),
            ))
        })
        .collect()
});

#[derive(Debug, zbus::DBusError)]
#[zbus(prefix = "org")]
enum Error {
    #[zbus(error)]
    ZBus(zbus::Error),
    #[zbus(name = "freedesktop.DBus.Error.AccessDenied")]
    AccessDenied(String),
    #[zbus(name = "shipwright.Keel.Actions.Error.UnknownAction")]
    UnknownAction(String),
    #[zbus(name = "shipwright.Keel.Actions.Error.InvalidArguments")]
    InvalidArguments(String),
    #[zbus(name = "shipwright.Keel.Actions.Error.NotAvailable")]
    NotAvailable(String),
    #[zbus(name = "shipwright.Keel.Actions.Error.Failed")]
    Failed(String),
}

impl From<zbus::fdo::Error> for Error {
    fn from(e: zbus::fdo::Error) -> Self {
        Self::Failed(e.to_string())
    }
}

pub(super) fn export(qt: Qt) {
    io::spawn(async move {
        let served = async {
            let bus = io::session_bus().await?;
            bus.object_server()
                .at("/org/shipwright/Keel/Actions", Actions { qt })
                .await?;
            bus.request_name("org.marathonos.shell").await?;
            zbus::Result::Ok(())
        };
        if let Err(e) = served.await {
            log::warn("keel", format_args!("shell actions not served: {e}"));
        }
    });
}

/// Every argument the manifest declares is a bounded string.
fn invalid(schema: &Value, args: &Map<String, Value>) -> Option<String> {
    for (name, value) in args {
        let Some(property) = schema["properties"].get(name) else {
            return Some(format!("unknown argument {name}"));
        };
        let max = property["maxLength"].as_u64().unwrap_or(0);
        if value
            .as_str()
            .is_none_or(|s| s.chars().count() as u64 > max)
        {
            return Some(format!(
                "{name} must be a string of at most {max} characters"
            ));
        }
    }
    schema["required"]
        .as_array()
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .find(|r| !args.contains_key(*r))
        .map(|r| format!("missing argument {r}"))
}

struct Actions {
    qt: Qt,
}

impl Actions {
    /// An app the shell runs, or any process it started; unknown counts as one.
    async fn is_app_caller(&self, h: &Header<'_>) -> bool {
        let Some(sender) = h.sender() else {
            return true;
        };
        let pid = async {
            zbus::fdo::DBusProxy::new(&io::session_bus().await.ok()?)
                .await
                .ok()?
                .get_connection_unix_process_id(sender.clone().into())
                .await
                .ok()
        };
        let Some(pid) = pid.await.map(i64::from) else {
            return true;
        };
        let shell = i64::from(std::process::id());
        ipc::on_gui(&self.qt, move |obj| {
            !obj.app_for_pid(pid).is_empty() || (pid != shell && descends_from(pid, shell))
        })
        .await
        .unwrap_or(true)
    }

    async fn run(&self, action: &str, args: &Map<String, Value>) -> Result<Value, Error> {
        let id = args
            .get("id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned();
        match action {
            "apps.list" => Ok(
                json!({"result": apps::all().iter().map(|a| json!({"id": a.id, "name": a.name})).collect::<Vec<_>>()}),
            ),
            "apps.running" => {
                let open = ipc::on_gui(&self.qt, |obj| {
                    obj.tasks
                        .iter()
                        .map(|t| json!({"id": t.app_id, "name": t.title}))
                        .collect::<Vec<_>>()
                })
                .await?;
                Ok(json!({"result": open}))
            }
            "shell.state" => {
                let screen_on = match display::DISPLAY.get() {
                    Some(d) => ipc::on_gui(d, |d| *d.screen_on()).await?,
                    None => true,
                };
                let (locked, front, quick) = ipc::on_gui(&self.qt, |obj| {
                    (
                        obj.locked,
                        if obj.app_window_open {
                            obj.current_app_id.clone()
                        } else {
                            String::new()
                        },
                        obj.quick_settings_open,
                    )
                })
                .await?;
                Ok(
                    json!({"locked": locked, "screenOn": screen_on, "foregroundApp": front, "quickSettingsOpen": quick}),
                )
            }
            "app.launch" => {
                let route = args
                    .get("route")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_owned();
                let launched = ipc::on_gui(&self.qt, move |mut obj| {
                    if !obj.can_launch(&q(&id)) {
                        return Err(Error::InvalidArguments(format!("no app {id}")));
                    }
                    let ok = if route.is_empty() {
                        obj.launch(&id)
                    } else {
                        obj.as_mut()
                            .launch_app_with_route(&q(&id), &q(&route), &q(""))
                    };
                    if ok {
                        Ok(())
                    } else {
                        Err(Error::Failed(format!("{id} did not start")))
                    }
                })
                .await?;
                launched.map(|()| json!({}))
            }
            "app.close" => {
                let closed = ipc::on_gui(&self.qt, {
                    let id = id.clone();
                    move |obj| obj.close_from_card(&id)
                })
                .await?;
                if closed {
                    Ok(json!({}))
                } else {
                    Err(Error::InvalidArguments(format!("{id} is not open")))
                }
            }
            "shell.home" | "shell.switcher" => {
                let switcher = action == "shell.switcher";
                ipc::on_gui(&self.qt, move |obj| obj.home_requested(switcher)).await?;
                Ok(json!({}))
            }
            "quicksettings.show" | "quicksettings.hide" => {
                let mode = i32::from(action == "quicksettings.show");
                ipc::on_gui(&self.qt, move |obj| obj.quick_settings_requested(mode)).await?;
                Ok(json!({}))
            }
            _ => Err(Error::UnknownAction(format!("no action named {action}"))),
        }
    }
}

#[allow(
    clippy::unused_self,
    clippy::needless_pass_by_value,
    reason = "the Keel Actions signatures, which the shell answers in part"
)]
#[zbus::interface(name = "org.shipwright.Keel.Actions")]
impl Actions {
    fn describe(&self) -> &'static str {
        MANIFEST
    }

    async fn invoke(
        &self,
        action: String,
        arguments: String,
        options: HashMap<String, OwnedValue>,
        #[zbus(header)] h: Header<'_>,
    ) -> Result<String, Error> {
        drop(options);
        if self.is_app_caller(&h).await {
            return Err(Error::AccessDenied("apps cannot drive the shell".into()));
        }
        let tool = TOOLS
            .get(&action)
            .ok_or_else(|| Error::UnknownAction(format!("no action named {action}")))?;
        let Ok(Value::Object(args)) = serde_json::from_str::<Value>(&arguments) else {
            return Err(Error::InvalidArguments(
                "arguments must be a JSON object".into(),
            ));
        };
        if let Some(why) = invalid(&tool["inputSchema"], &args) {
            return Err(Error::InvalidArguments(why));
        }
        let read_only = tool["annotations"]["readOnlyHint"]
            .as_bool()
            .unwrap_or(false);
        if !read_only && ipc::on_gui(&self.qt, |obj| obj.locked).await? {
            return Err(Error::NotAvailable("the phone is locked".into()));
        }
        Ok(self.run(&action, &args).await?.to_string())
    }

    fn get_entity(&self, entity_type: String, id: String) -> Result<String, Error> {
        drop(id);
        Err(Error::UnknownAction(format!(
            "no entity type {entity_type}"
        )))
    }

    fn find_entities(
        &self,
        entity_type: String,
        query: String,
        limit: u32,
    ) -> Result<String, Error> {
        drop((query, limit));
        Err(Error::UnknownAction(format!(
            "no entity type {entity_type}"
        )))
    }

    fn get_context(&self) -> &'static str {
        "{}"
    }
}

impl super::Tasks {
    /// As its switcher card closes it; false when the app is not open.
    fn close_from_card(mut self: std::pin::Pin<&mut Self>, app_id: &str) -> bool {
        let Some(task) = self.task(app_id).cloned() else {
            return false;
        };
        if task.kind == "native" && task.surface_id >= 0 {
            self.as_mut().prepare_close(&q(app_id));
            if self.as_mut().close_app_windows(&q(app_id)) == 0 {
                self.as_mut().close_window_requested(task.surface_id);
            }
            self.close_task(&q(&task.id));
        } else {
            self.close_app(&q(app_id), false);
        }
        true
    }
}
