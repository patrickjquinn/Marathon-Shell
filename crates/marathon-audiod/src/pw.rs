//! The `PipeWire` client: mirrors sinks, sources, playback streams, their
//! devices' routes and the `default`/`sm-settings` metadata into a [`Graph`],
//! and carries out the writes the graph plans.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap};
use std::io::Cursor;
use std::rc::{Rc, Weak};

use pipewire as pw;
use pw::device::{Device, DeviceListener};
use pw::metadata::{Metadata as PwMetadata, MetadataListener};
use pw::node::{Node as PwNode, NodeListener};
use pw::spa;
use pw::types::ObjectType;
use spa::param::{ParamInfoFlags, ParamType};
use spa::pod::serialize::PodSerializer;
use spa::pod::{deserialize::PodDeserializer, Object, Pod, Property, Value, ValueArray};
use spa::sys as spa_sys;
use spa::utils::dict::DictRef;
use spa::utils::result::AsyncSeq;

use crate::graph::{
    Direction, Graph, Metadata, Mix, Node, Op, RouteId, Snapshot, Target, Write,
    SPEAKERPHONE_SETTING,
};

pub struct Request {
    pub op: Op,
    /// Signalled once `PipeWire` has handled the write and sent its events.
    pub done: async_channel::Sender<()>,
}

fn wanted(media_class: &str) -> bool {
    media_class == "Stream/Output/Audio"
        || [Direction::Output, Direction::Input]
            .iter()
            .any(|d| d.media_classes().contains(&media_class))
}

/// A device's routes as an enumeration lists them, complete once the sync
/// sent after it is done; `again` if they changed meanwhile.
struct RouteEnum {
    sync: AsyncSeq,
    routes: BTreeMap<i32, (RouteId, Mix)>,
    again: bool,
}

struct State {
    graph: Graph,
    core: pw::core::CoreRc,
    nodes: HashMap<u32, (PwNode, NodeListener)>,
    devices: HashMap<u32, (Device, DeviceListener)>,
    metadata: HashMap<u32, (Metadata, PwMetadata, MetadataListener)>,
    /// The Route param flags each device last announced; their serial bit
    /// flips whenever its routes change.
    route_flags: HashMap<u32, ParamInfoFlags>,
    route_enums: HashMap<u32, RouteEnum>,
    pending: Vec<(AsyncSeq, async_channel::Sender<()>)>,
    /// The second initial round trip; `known` once it is done.
    settled: Option<AsyncSeq>,
    known: bool,
    ready: Option<Box<dyn FnOnce()>>,
    published: Option<Snapshot>,
    publish: Box<dyn Fn(Snapshot)>,
}

/// A level is `mute` and `channelVolumes` together, as `WirePlumber`'s mixer
/// reads it; a node lists other `Props` objects besides.
fn mix_of(props: &Object) -> Option<Mix> {
    let (mut mute, mut volumes) = (None, None);
    for p in &props.properties {
        match (p.key, &p.value) {
            (spa_sys::SPA_PROP_mute, Value::Bool(m)) => mute = Some(*m),
            (spa_sys::SPA_PROP_channelVolumes, Value::ValueArray(ValueArray::Float(v))) => {
                volumes = Some(v.clone());
            }
            _ => {}
        }
    }
    Some(Mix {
        volumes: volumes?,
        mute: mute?,
    })
}

fn object_of(pod: &Pod) -> Option<Object> {
    match PodDeserializer::deserialize_any_from(pod.as_bytes()) {
        Ok((_, Value::Object(o))) => Some(o),
        _ => None,
    }
}

fn route_of(pod: &Pod) -> Option<(RouteId, Mix)> {
    let route = object_of(pod)?;
    let (mut index, mut device, mut mix) = (None, None, None);
    for p in route.properties {
        match (p.key, p.value) {
            (spa_sys::SPA_PARAM_ROUTE_index, Value::Int(i)) => index = Some(i),
            (spa_sys::SPA_PARAM_ROUTE_device, Value::Int(d)) => device = Some(d),
            (spa_sys::SPA_PARAM_ROUTE_props, Value::Object(o)) => mix = mix_of(&o),
            _ => {}
        }
    }
    Some((
        RouteId {
            index: index?,
            device: device?,
        },
        mix?,
    ))
}

fn serialize(value: &Value) -> Option<Vec<u8>> {
    PodSerializer::serialize(Cursor::new(Vec::new()), value)
        .ok()
        .map(|(c, _)| c.into_inner())
}

fn props_value(volumes: Option<&Vec<f32>>, mute: Option<bool>) -> Value {
    let mut properties = Vec::new();
    if let Some(v) = volumes {
        properties.push(Property::new(
            spa_sys::SPA_PROP_channelVolumes,
            Value::ValueArray(ValueArray::Float(v.clone())),
        ));
    }
    if let Some(m) = mute {
        properties.push(Property::new(spa_sys::SPA_PROP_mute, Value::Bool(m)));
    }
    Value::Object(Object {
        type_: spa_sys::SPA_TYPE_OBJECT_Props,
        id: spa_sys::SPA_PARAM_Props,
        properties,
    })
}

fn route_value(route: RouteId, props: Value) -> Value {
    Value::Object(Object {
        type_: spa_sys::SPA_TYPE_OBJECT_ParamRoute,
        id: spa_sys::SPA_PARAM_Route,
        properties: vec![
            Property::new(spa_sys::SPA_PARAM_ROUTE_index, Value::Int(route.index)),
            Property::new(spa_sys::SPA_PARAM_ROUTE_device, Value::Int(route.device)),
            Property::new(spa_sys::SPA_PARAM_ROUTE_props, props),
            Property::new(spa_sys::SPA_PARAM_ROUTE_save, Value::Bool(true)),
        ],
    })
}

fn update_node(node: &mut Node, props: &DictRef) {
    let s = |k: &str| props.get(k).map(str::to_owned);
    node.name = s("node.name").unwrap_or_default();
    node.description = s("node.description").unwrap_or_default();
    node.media_class = s("media.class").unwrap_or_default();
    node.app_name = s("application.name");
    node.device = props.get("device.id").and_then(|v| v.parse().ok());
    node.profile_device = props
        .get("card.profile.device")
        .and_then(|v| v.parse().ok());
}

type Shared = Rc<RefCell<State>>;

/// Runs until the connection to `PipeWire` is lost. `publish` gets every
/// changed [`Snapshot`]; `ready` is called once the initial graph is known.
pub fn run(
    requests: pw::channel::Receiver<Request>,
    publish: impl Fn(Snapshot) + 'static,
    ready: impl FnOnce() + 'static,
) -> Result<(), pw::Error> {
    let main_loop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&main_loop, None)?;
    let core = context.connect_rc(None)?;
    let registry = core.get_registry_rc()?;
    let state = Rc::new(RefCell::new(State::new(
        core.clone(),
        Box::new(publish),
        Box::new(ready),
    )));

    // Two round trips: the first lists the globals, the second their info
    // and params; then the routes those announce.
    let initial = core.sync(0)?;
    let _core_listener = core
        .add_listener_local()
        .done({
            let state = Rc::downgrade(&state);
            let core = core.downgrade();
            move |id, seq| {
                let (Some(state), Some(core)) = (state.upgrade(), core.upgrade()) else {
                    return;
                };
                if id != pw::core::PW_ID_CORE {
                    return;
                }
                if seq == initial {
                    state.borrow_mut().settled = core.sync(0).ok();
                } else {
                    state.borrow_mut().finish(seq);
                }
            }
        })
        .error({
            let main_loop = main_loop.downgrade();
            move |id, _seq, res, message| {
                crate::log(&format!("PipeWire error on {id}: {res} {message}"));
                if id == pw::core::PW_ID_CORE {
                    if let Some(l) = main_loop.upgrade() {
                        l.quit();
                    }
                }
            }
        })
        .register();

    let _registry_listener = registry
        .add_listener_local()
        .global({
            let registry = registry.downgrade();
            let state = Rc::downgrade(&state);
            move |global| {
                if let (Some(registry), Some(state)) = (registry.upgrade(), state.upgrade()) {
                    bind(&registry, &state, global);
                }
            }
        })
        .global_remove({
            let state = Rc::downgrade(&state);
            move |id| {
                if let Some(state) = state.upgrade() {
                    state.borrow_mut().remove(id);
                }
            }
        })
        .register();

    let _requests = requests.attach(main_loop.loop_(), {
        let state = Rc::downgrade(&state);
        move |request: Request| {
            if let Some(state) = state.upgrade() {
                state.borrow_mut().apply(request);
            }
        }
    });

    main_loop.run();
    Ok(())
}

fn bind(
    registry: &pw::registry::RegistryRc,
    state: &Shared,
    global: &pw::registry::GlobalObject<&DictRef>,
) {
    let prop = |k: &str| global.props.and_then(|p| p.get(k));
    let id = global.id;
    let weak = Rc::downgrade(state);
    match global.type_ {
        ObjectType::Node if wanted(prop("media.class").unwrap_or_default()) => {
            let Ok(node) = registry.bind::<PwNode, _>(global) else {
                return;
            };
            let listener = node
                .add_listener_local()
                .info({
                    let state = Weak::clone(&weak);
                    // Props come only with the events that change them.
                    move |info| {
                        if !info.change_mask().contains(pw::node::NodeChangeMask::PROPS) {
                            return;
                        }
                        if let (Some(state), Some(props)) = (state.upgrade(), info.props()) {
                            let mut s = state.borrow_mut();
                            update_node(s.graph.nodes.entry(id).or_default(), props);
                            s.changed();
                        }
                    }
                })
                .param(move |_seq, kind, _index, _next, pod| {
                    let mix = pod.and_then(object_of).as_ref().and_then(mix_of);
                    if let (Some(state), Some(mix), ParamType::Props) = (weak.upgrade(), mix, kind)
                    {
                        let mut s = state.borrow_mut();
                        s.graph.nodes.entry(id).or_default().props = Some(mix);
                        s.changed();
                    }
                })
                .register();
            node.subscribe_params(&[ParamType::Props]);
            state.borrow_mut().nodes.insert(id, (node, listener));
        }
        ObjectType::Device if prop("media.class") == Some("Audio/Device") => {
            let Ok(device) = registry.bind::<Device, _>(global) else {
                return;
            };
            // A client-exported device (all of WirePlumber's) sends
            // subscribers no param changes: re-enumerate, as pipewire-pulse does.
            let listener = device
                .add_listener_local()
                .info({
                    let state = Weak::clone(&weak);
                    move |info| {
                        if !info
                            .change_mask()
                            .contains(pw::device::DeviceChangeMask::PARAMS)
                        {
                            return;
                        }
                        let flags = info
                            .params()
                            .iter()
                            .find(|p| p.id() == ParamType::Route)
                            .map(spa::param::ParamInfo::flags);
                        if let (Some(state), Some(flags)) = (state.upgrade(), flags) {
                            state.borrow_mut().routes_changed(id, flags);
                        }
                    }
                })
                .param(move |_seq, kind, _index, _next, pod| {
                    if let (Some(state), Some(pod), ParamType::Route) = (weak.upgrade(), pod, kind)
                    {
                        state.borrow_mut().route(id, pod);
                    }
                })
                .register();
            state.borrow_mut().devices.insert(id, (device, listener));
        }
        ObjectType::Metadata => {
            let which = match prop("metadata.name") {
                Some("default") => Metadata::Default,
                Some("sm-settings") => Metadata::Settings,
                _ => return,
            };
            let Ok(metadata) = registry.bind::<PwMetadata, _>(global) else {
                return;
            };
            let listener = metadata
                .add_listener_local()
                .property(move |subject, key, _type, value| {
                    if let (Some(state), 0) = (weak.upgrade(), subject) {
                        state.borrow_mut().metadata_property(which, key, value);
                    }
                    0
                })
                .register();
            state
                .borrow_mut()
                .metadata
                .insert(id, (which, metadata, listener));
        }
        _ => {}
    }
}

impl State {
    fn new(
        core: pw::core::CoreRc,
        publish: Box<dyn Fn(Snapshot)>,
        ready: Box<dyn FnOnce()>,
    ) -> Self {
        Self {
            graph: Graph::default(),
            core,
            nodes: HashMap::new(),
            devices: HashMap::new(),
            metadata: HashMap::new(),
            route_flags: HashMap::new(),
            route_enums: HashMap::new(),
            pending: Vec::new(),
            settled: None,
            known: false,
            ready: Some(ready),
            published: None,
            publish,
        }
    }

    fn changed(&mut self) {
        let snapshot = self.graph.snapshot();
        if self.published.as_ref() != Some(&snapshot) {
            self.published = Some(snapshot.clone());
            (self.publish)(snapshot);
        }
    }

    fn apply(&mut self, request: Request) {
        let written = self
            .graph
            .plan(&request.op)
            .is_some_and(|w| self.execute(&w));
        match self.core.sync(0) {
            Ok(seq) if written => self.pending.push((seq, request.done)),
            _ => {
                request.done.try_send(()).ok();
            }
        }
    }

    fn finish(&mut self, seq: AsyncSeq) {
        self.pending.retain(|(s, done)| {
            if *s == seq {
                done.try_send(()).ok();
            }
            *s != seq
        });
        let complete: Vec<u32> = self
            .route_enums
            .iter()
            .filter(|(_, e)| e.sync == seq)
            .map(|(device, _)| *device)
            .collect();
        for device in complete {
            if let Some(e) = self.route_enums.remove(&device) {
                self.graph.devices.entry(device).or_default().routes = e.routes;
                if e.again {
                    self.enumerate_routes(device);
                }
            }
        }
        if self.settled == Some(seq) {
            self.known = true;
        }
        self.changed();
        // The name is taken once the graph and its routes are known, so the
        // first GetAll after activation sees the real levels.
        if self.known && self.route_enums.is_empty() {
            if let Some(ready) = self.ready.take() {
                ready();
            }
        }
    }

    fn routes_changed(&mut self, device: u32, flags: ParamInfoFlags) {
        if self.route_flags.insert(device, flags) == Some(flags)
            || !flags.contains(ParamInfoFlags::READ)
        {
            return;
        }
        match self.route_enums.get_mut(&device) {
            Some(e) => e.again = true,
            None => self.enumerate_routes(device),
        }
    }

    /// Replies carry the protocol's sequence, which pipewire-rs does not
    /// return, so one enumeration runs at a time per device.
    fn enumerate_routes(&mut self, device: u32) {
        let Some((proxy, _)) = self.devices.get(&device) else {
            return;
        };
        proxy.enum_params(0, Some(ParamType::Route), 0, u32::MAX);
        if let Ok(sync) = self.core.sync(0) {
            self.route_enums.insert(
                device,
                RouteEnum {
                    sync,
                    routes: BTreeMap::new(),
                    again: false,
                },
            );
        }
    }

    fn route(&mut self, device: u32, pod: &Pod) {
        if let (Some(e), Some((route, mix))) = (self.route_enums.get_mut(&device), route_of(pod)) {
            e.routes.insert(route.device, (route, mix));
        }
    }

    fn metadata_property(&mut self, which: Metadata, key: Option<&str>, value: Option<&str>) {
        match (which, key) {
            (Metadata::Default, Some(key)) => self.graph.set_default(key, value),
            (Metadata::Default, None) => self.graph.clear_defaults(),
            (Metadata::Settings, Some(key)) => self.graph.set_setting(key, value),
            (Metadata::Settings, None) => self.graph.set_setting(SPEAKERPHONE_SETTING, None),
        }
        self.changed();
    }

    fn remove(&mut self, id: u32) {
        self.nodes.remove(&id);
        self.devices.remove(&id);
        self.route_flags.remove(&id);
        self.route_enums.remove(&id);
        self.graph.nodes.remove(&id);
        self.graph.devices.remove(&id);
        if let Some((Metadata::Default, _, _)) = self.metadata.remove(&id) {
            self.graph.clear_defaults();
        }
        self.changed();
    }

    fn execute(&self, write: &Write) -> bool {
        match write {
            Write::Props {
                target,
                volumes,
                mute,
            } => {
                let props = props_value(volumes.as_ref(), *mute);
                match target {
                    Target::Node(id) => {
                        let (Some((node, _)), Some(bytes)) =
                            (self.nodes.get(id), serialize(&props))
                        else {
                            return false;
                        };
                        Pod::from_bytes(&bytes)
                            .map(|pod| node.set_param(ParamType::Props, 0, pod))
                            .is_some()
                    }
                    Target::Route { device, route } => {
                        let (Some((dev, _)), Some(bytes)) = (
                            self.devices.get(device),
                            serialize(&route_value(*route, props)),
                        ) else {
                            return false;
                        };
                        Pod::from_bytes(&bytes)
                            .map(|pod| dev.set_param(ParamType::Route, 0, pod))
                            .is_some()
                    }
                }
            }
            Write::Metadata {
                metadata,
                key,
                type_,
                value,
            } => {
                let Some((_, m, _)) = self
                    .metadata
                    .values()
                    .find(|(which, _, _)| which == metadata)
                else {
                    return false;
                };
                m.set_property(0, key, Some(type_), Some(value));
                true
            }
        }
    }
}

#[cfg(test)]
#[allow(clippy::unwrap_used, reason = "tests")]
mod tests {
    use super::*;

    // The pods written are the ones read back: a Route carrying Props.
    #[test]
    fn route_props_round_trip() {
        let route = RouteId {
            index: 2,
            device: 7,
        };
        let value = route_value(route, props_value(Some(&vec![0.25, 0.25]), Some(true)));
        let bytes = serialize(&value).unwrap();
        let (parsed, mix) = route_of(Pod::from_bytes(&bytes).unwrap()).unwrap();
        assert_eq!(parsed, route);
        assert_eq!(
            mix,
            Mix {
                volumes: vec![0.25, 0.25],
                mute: true,
            }
        );
    }

    #[test]
    fn props_without_levels_are_not_a_mix() {
        let bytes = serialize(&props_value(None, None)).unwrap();
        let object = object_of(Pod::from_bytes(&bytes).unwrap()).unwrap();
        assert_eq!(mix_of(&object), None);
    }
}
