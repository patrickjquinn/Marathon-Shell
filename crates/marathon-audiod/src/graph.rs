//! The audio graph as the daemon sees it, and what a request writes to it.
//!
//! Volume follows `WirePlumber`'s mixer API (and pipewire-pulse): a node
//! backed by a device route is controlled through that route, so the level
//! is the device's and `WirePlumber` stores it per route; any other node is
//! controlled through its own `Props`. Levels are cubic, as `wpctl` and
//! pavucontrol show them.

use std::collections::BTreeMap;

pub const SPEAKERPHONE_SETTING: &str = "marathon.call.speakerphone";
const JSON: &str = "Spa:String:JSON";
/// The two halves of a role-based policy loopback, as `WirePlumber` names
/// them (node/find-media-role-default-volume.lua).
const ROLE_LOOPBACKS: [&str; 2] = ["input.loopback.sink.role.", "output.loopback.sink.role."];

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Mix {
    pub volumes: Vec<f32>,
    pub mute: bool,
}

#[derive(Debug, Clone, Default)]
pub struct Node {
    pub name: String,
    pub description: String,
    pub media_class: String,
    pub app_name: Option<String>,
    pub device: Option<u32>,
    pub profile_device: Option<i32>,
    pub props: Option<Mix>,
}

impl Node {
    /// A media role's loopback: plumbing, not a device or an app.
    fn is_role_loopback(&self) -> bool {
        ROLE_LOOPBACKS.iter().any(|p| self.name.starts_with(p))
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct RouteId {
    pub index: i32,
    pub device: i32,
}

/// The device's active routes, by route `device` (a node's `card.profile.device`).
#[derive(Debug, Clone, Default)]
pub struct Device {
    pub routes: BTreeMap<i32, (RouteId, Mix)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Direction {
    Output,
    Input,
}

impl Direction {
    /// The classes `WirePlumber` picks this direction's default from, less a
    /// sink's monitor standing in for a microphone.
    pub fn media_classes(self) -> &'static [&'static str] {
        match self {
            Direction::Output => &["Audio/Sink", "Audio/Duplex"],
            Direction::Input => &["Audio/Source", "Audio/Source/Virtual", "Audio/Duplex"],
        }
    }

    fn has(self, node: &Node) -> bool {
        self.media_classes().contains(&node.media_class.as_str())
    }

    fn configured_key(self) -> &'static str {
        match self {
            Direction::Output => "default.configured.audio.sink",
            Direction::Input => "default.configured.audio.source",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Op {
    Volume(Direction, f64),
    Muted(Direction, bool),
    Default(Direction, String),
    StreamVolume(u32, f64),
    StreamMuted(u32, bool),
    Speakerphone(bool),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Target {
    Node(u32),
    Route { device: u32, route: RouteId },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Metadata {
    /// `default`: the configured and current default nodes.
    Default,
    /// `sm-settings`: `WirePlumber`'s settings, read by its policy scripts.
    Settings,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Write {
    Props {
        target: Target,
        volumes: Option<Vec<f32>>,
        mute: Option<bool>,
    },
    Metadata {
        metadata: Metadata,
        key: &'static str,
        type_: &'static str,
        value: String,
    },
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Port {
    pub name: String,
    pub description: String,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Stream {
    pub id: u32,
    pub name: String,
    pub volume: f64,
    pub muted: bool,
}

/// What the D-Bus interface publishes.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Snapshot {
    pub volume: f64,
    pub muted: bool,
    pub input_volume: f64,
    pub input_muted: bool,
    pub default_sink: String,
    pub default_source: String,
    pub sinks: Vec<Port>,
    pub sources: Vec<Port>,
    pub streams: Vec<Stream>,
    pub speakerphone: bool,
}

#[derive(Debug, Default)]
pub struct Graph {
    pub nodes: BTreeMap<u32, Node>,
    pub devices: BTreeMap<u32, Device>,
    default_sink: Option<String>,
    default_source: Option<String>,
    speakerphone: bool,
}

fn cubic(linear: f32) -> f64 {
    f64::from(linear.max(0.0)).cbrt()
}

#[allow(
    clippy::cast_possible_truncation,
    reason = "a level in 0..=1 fits an f32"
)]
fn linear(level: f64) -> f32 {
    level.clamp(0.0, 1.0).powi(3) as f32
}

fn level(mix: &Mix) -> f64 {
    if mix.volumes.is_empty() {
        return 0.0;
    }
    let sum: f64 = mix.volumes.iter().copied().map(cubic).sum();
    sum / f64::from(u32::try_from(mix.volumes.len()).unwrap_or(u32::MAX))
}

/// The node name in a `default` metadata value: `{"name": "..."}`.
fn node_name(value: &str) -> Option<String> {
    let json: serde_json::Value = serde_json::from_str(value).ok()?;
    json.get("name")?.as_str().map(str::to_owned)
}

impl Graph {
    /// A property of the `default` metadata changed; `None` removes it.
    pub fn set_default(&mut self, key: &str, value: Option<&str>) {
        let name = value.and_then(node_name);
        match key {
            "default.audio.sink" => self.default_sink = name,
            "default.audio.source" => self.default_source = name,
            _ => {}
        }
    }

    pub fn clear_defaults(&mut self) {
        self.default_sink = None;
        self.default_source = None;
    }

    /// A property of `sm-settings` changed; `None` removes it.
    pub fn set_setting(&mut self, key: &str, value: Option<&str>) {
        if key == SPEAKERPHONE_SETTING {
            self.speakerphone = value == Some("true");
        }
    }

    fn default_node(&self, direction: Direction) -> Option<(u32, &Node)> {
        let name = match direction {
            Direction::Output => self.default_sink.as_deref(),
            Direction::Input => self.default_source.as_deref(),
        }?;
        self.nodes
            .iter()
            .find(|(_, n)| n.name == name && direction.has(n))
            .map(|(id, n)| (*id, n))
    }

    /// Where a node's level lives, and the level now.
    fn mix(&self, id: u32, node: &Node) -> Option<(Target, Mix)> {
        if let (Some(device), Some(profile_device)) = (node.device, node.profile_device) {
            if let Some((route, mix)) = self
                .devices
                .get(&device)
                .and_then(|d| d.routes.get(&profile_device))
            {
                return Some((
                    Target::Route {
                        device,
                        route: *route,
                    },
                    mix.clone(),
                ));
            }
        }
        node.props.clone().map(|mix| (Target::Node(id), mix))
    }

    fn volume_write(&self, id: u32, node: &Node, level: f64) -> Option<Write> {
        let (target, mix) = self.mix(id, node)?;
        Some(Write::Props {
            target,
            volumes: Some(vec![linear(level); mix.volumes.len().max(1)]),
            mute: None,
        })
    }

    fn mute_write(&self, id: u32, node: &Node, mute: bool) -> Option<Write> {
        let (target, _) = self.mix(id, node)?;
        Some(Write::Props {
            target,
            volumes: None,
            mute: Some(mute),
        })
    }

    fn stream(&self, id: u32) -> Option<&Node> {
        self.nodes
            .get(&id)
            .filter(|n| n.media_class == "Stream/Output/Audio" && !n.is_role_loopback())
    }

    /// The write that carries out `op`, if its target exists.
    pub fn plan(&self, op: &Op) -> Option<Write> {
        match op {
            Op::Volume(direction, level) => {
                let (id, node) = self.default_node(*direction)?;
                self.volume_write(id, node, *level)
            }
            Op::Muted(direction, mute) => {
                let (id, node) = self.default_node(*direction)?;
                self.mute_write(id, node, *mute)
            }
            Op::Default(direction, name) => {
                self.nodes
                    .values()
                    .find(|n| &n.name == name && direction.has(n))?;
                Some(Write::Metadata {
                    metadata: Metadata::Default,
                    key: direction.configured_key(),
                    type_: JSON,
                    value: serde_json::json!({ "name": name }).to_string(),
                })
            }
            Op::StreamVolume(id, level) => self.volume_write(*id, self.stream(*id)?, *level),
            Op::StreamMuted(id, mute) => self.mute_write(*id, self.stream(*id)?, *mute),
            Op::Speakerphone(on) => Some(Write::Metadata {
                metadata: Metadata::Settings,
                key: SPEAKERPHONE_SETTING,
                type_: JSON,
                value: on.to_string(),
            }),
        }
    }

    fn ports(&self, direction: Direction) -> Vec<Port> {
        self.nodes
            .values()
            .filter(|n| direction.has(n) && !n.is_role_loopback())
            .map(|n| Port {
                name: n.name.clone(),
                description: if n.description.is_empty() {
                    n.name.clone()
                } else {
                    n.description.clone()
                },
            })
            .collect()
    }

    fn level_of(&self, direction: Direction) -> (f64, bool, String) {
        self.default_node(direction)
            .map(|(id, node)| {
                let (volume, muted) = self
                    .mix(id, node)
                    .map_or((0.0, false), |(_, mix)| (level(&mix), mix.mute));
                (volume, muted, node.name.clone())
            })
            .unwrap_or_default()
    }

    pub fn snapshot(&self) -> Snapshot {
        let (volume, muted, default_sink) = self.level_of(Direction::Output);
        let (input_volume, input_muted, default_source) = self.level_of(Direction::Input);
        let streams = self
            .nodes
            .iter()
            .filter(|(id, _)| self.stream(**id).is_some())
            .map(|(id, n)| {
                let mix = n.props.clone().unwrap_or_default();
                Stream {
                    id: *id,
                    name: n
                        .app_name
                        .clone()
                        .or_else(|| (!n.description.is_empty()).then(|| n.description.clone()))
                        .unwrap_or_else(|| n.name.clone()),
                    volume: level(&mix),
                    muted: mix.mute,
                }
            })
            .collect();
        Snapshot {
            volume,
            muted,
            input_volume,
            input_muted,
            default_sink,
            default_source,
            sinks: self.ports(Direction::Output),
            sources: self.ports(Direction::Input),
            streams,
            speakerphone: self.speakerphone,
        }
    }
}

#[cfg(test)]
#[allow(clippy::panic, reason = "tests")]
mod tests {
    use super::*;

    fn sink(name: &str, props: Option<Mix>) -> Node {
        Node {
            name: name.into(),
            description: format!("{name} desc"),
            media_class: "Audio/Sink".into(),
            props,
            ..Node::default()
        }
    }

    fn mix(level: f32, mute: bool) -> Mix {
        Mix {
            volumes: vec![level; 2],
            mute,
        }
    }

    fn with_default(nodes: Vec<(u32, Node)>, default: &str) -> Graph {
        let mut g = Graph::default();
        g.nodes.extend(nodes);
        g.set_default(
            "default.audio.sink",
            Some(&format!(r#"{{"name":"{default}"}}"#)),
        );
        g
    }

    // A Bluetooth speaker's level lives on its device route.
    #[test]
    fn device_backed_sink_is_set_through_its_route() {
        let mut speaker = sink("bluez_output.AA", Some(mix(1.0, false)));
        speaker.device = Some(87);
        speaker.profile_device = Some(1);
        let mut g = with_default(vec![(78, speaker)], "bluez_output.AA");
        let route = RouteId {
            index: 0,
            device: 1,
        };
        g.devices.insert(
            87,
            Device {
                routes: BTreeMap::from([(1, (route, mix(0.125, false)))]),
            },
        );

        assert!((g.snapshot().volume - 0.5).abs() < 1e-6);
        assert_eq!(
            g.plan(&Op::Volume(Direction::Output, 0.5)),
            Some(Write::Props {
                target: Target::Route { device: 87, route },
                volumes: Some(vec![0.125, 0.125]),
                mute: None,
            })
        );
    }

    #[test]
    fn plain_sink_is_set_through_its_props() {
        let g = with_default(vec![(40, sink("null", Some(mix(0.0, false))))], "null");
        assert_eq!(
            g.plan(&Op::Muted(Direction::Output, true)),
            Some(Write::Props {
                target: Target::Node(40),
                volumes: None,
                mute: Some(true),
            })
        );
    }

    // A device node whose route has not been reported yet falls back to its
    // own props rather than writing nowhere.
    #[test]
    fn route_not_yet_known_uses_node_props() {
        let mut n = sink("alsa", Some(mix(1.0, false)));
        n.device = Some(5);
        n.profile_device = Some(3);
        let g = with_default(vec![(41, n)], "alsa");
        assert!(matches!(
            g.plan(&Op::Volume(Direction::Output, 1.0)),
            Some(Write::Props {
                target: Target::Node(41),
                ..
            })
        ));
    }

    #[test]
    fn levels_are_cubic_and_clamped() {
        let g = with_default(vec![(40, sink("null", Some(mix(0.0, false))))], "null");
        let Some(Write::Props { volumes, .. }) = g.plan(&Op::Volume(Direction::Output, 2.0)) else {
            panic!("no write");
        };
        assert_eq!(volumes, Some(vec![1.0, 1.0]));
    }

    #[test]
    fn default_follows_the_metadata() {
        let mut g = with_default(
            vec![
                (40, sink("a", Some(mix(1.0, false)))),
                (41, sink("b", Some(mix(0.008, true)))),
            ],
            "a",
        );
        assert_eq!(g.snapshot().default_sink, "a");
        assert!((g.snapshot().volume - 1.0).abs() < 1e-6);

        g.set_default("default.audio.sink", Some(r#"{"name":"b"}"#));
        let s = g.snapshot();
        assert_eq!(s.default_sink, "b");
        assert!((s.volume - 0.2).abs() < 1e-6);
        assert!(s.muted);

        g.set_default("default.audio.sink", None);
        assert_eq!(g.snapshot().default_sink, "");
        assert_eq!(g.plan(&Op::Volume(Direction::Output, 0.3)), None);
    }

    #[test]
    fn set_default_names_an_existing_node_of_that_direction() {
        let g = with_default(vec![(40, sink("a", None))], "a");
        assert_eq!(
            g.plan(&Op::Default(Direction::Output, "a".into())),
            Some(Write::Metadata {
                metadata: Metadata::Default,
                key: "default.configured.audio.sink",
                type_: "Spa:String:JSON",
                value: r#"{"name":"a"}"#.into(),
            })
        );
        assert_eq!(g.plan(&Op::Default(Direction::Input, "a".into())), None);
        assert_eq!(g.plan(&Op::Default(Direction::Output, "x".into())), None);
    }

    #[test]
    fn streams_are_listed_and_set_by_id() {
        let mut g = Graph::default();
        g.nodes.insert(
            90,
            Node {
                name: "firefox".into(),
                media_class: "Stream/Output/Audio".into(),
                app_name: Some("Firefox".into()),
                props: Some(mix(0.125, false)),
                ..Node::default()
            },
        );
        g.nodes.insert(40, sink("null", Some(mix(1.0, false))));
        assert_eq!(
            g.snapshot().streams,
            vec![Stream {
                id: 90,
                name: "Firefox".into(),
                volume: 0.5,
                muted: false,
            }]
        );
        assert!(g.plan(&Op::StreamMuted(90, true)).is_some());
        assert_eq!(g.plan(&Op::StreamMuted(40, true)), None);
    }

    #[test]
    fn speakerphone_is_a_wireplumber_setting() {
        let mut g = Graph::default();
        assert_eq!(
            g.plan(&Op::Speakerphone(true)),
            Some(Write::Metadata {
                metadata: Metadata::Settings,
                key: SPEAKERPHONE_SETTING,
                type_: "Spa:String:JSON",
                value: "true".into(),
            })
        );
        g.set_setting(SPEAKERPHONE_SETTING, Some("true"));
        assert!(g.snapshot().speakerphone);
        g.set_setting(SPEAKERPHONE_SETTING, None);
        assert!(!g.snapshot().speakerphone);
    }

    // WirePlumber's role loopbacks are neither outputs to pick nor apps.
    #[test]
    fn role_loopbacks_are_not_listed() {
        let mut g = Graph::default();
        g.nodes.insert(40, sink("speaker", None));
        g.nodes.insert(
            50,
            sink("input.loopback.sink.role.alarm", Some(mix(1.0, false))),
        );
        g.nodes.insert(
            51,
            Node {
                name: "output.loopback.sink.role.alarm".into(),
                media_class: "Stream/Output/Audio".into(),
                props: Some(mix(1.0, false)),
                ..Node::default()
            },
        );
        let s = g.snapshot();
        assert_eq!(
            s.sinks.iter().map(|p| p.name.as_str()).collect::<Vec<_>>(),
            ["speaker"]
        );
        assert!(s.streams.is_empty());
        assert_eq!(g.plan(&Op::StreamVolume(51, 0.5)), None);
    }

    #[test]
    fn sources_and_sinks_are_listed_apart() {
        let mut g = Graph::default();
        g.nodes.insert(40, sink("out", None));
        g.nodes.insert(
            41,
            Node {
                name: "mic".into(),
                media_class: "Audio/Source".into(),
                props: Some(mix(1.0, true)),
                ..Node::default()
            },
        );
        g.set_default("default.audio.source", Some(r#"{"name":"mic"}"#));
        let s = g.snapshot();
        assert_eq!(s.sinks.len(), 1);
        assert_eq!(
            s.sources,
            vec![Port {
                name: "mic".into(),
                description: "mic".into(),
            }]
        );
        assert!(s.input_muted);
        assert_eq!(s.default_source, "mic");
    }
}
