//! A card whose output volume lives on a device route, as bluez5 and ACP
//! cards keep it, exported by a client the way `WirePlumber` exports its
//! monitors' devices. Its route is active once profile 1 is selected, as a
//! Bluetooth card's is once `WirePlumber` picks a profile. A null sink
//! stands in for the card's node.

use std::cell::RefCell;
use std::ffi::c_void;
use std::io::Cursor;
use std::os::raw::c_int;
use std::path::Path;
use std::ptr;
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;

use pipewire as pw;
use pw::spa::pod::deserialize::PodDeserializer;
use pw::spa::pod::serialize::PodSerializer;
use pw::spa::pod::{Object, Pod, Property, Value, ValueArray};
use pw::spa::sys as spa;
use pw::spa::utils::result::AsyncSeq;

pub const NODE_NAME: &str = "test-route-sink";
const ROUTE_DEVICE: i32 = 1;
const ROUTE_INDEX: i32 = 1;

#[repr(C)]
struct Card {
    device: spa::spa_device,
    hooks: spa::spa_list,
    props: pw::properties::PropertiesBox,
    params: [spa::spa_param_info; 2],
    active: bool,
    volumes: Vec<f32>,
    mute: bool,
    save: bool,
}

fn param_info(id: u32) -> spa::spa_param_info {
    spa::spa_param_info {
        id,
        flags: spa::SPA_PARAM_INFO_READWRITE,
        user: 0,
        seq: 0,
        padding: [0; 4],
    }
}

fn dict(props: &pw::properties::PropertiesBox) -> *mut spa::spa_dict {
    AsRef::<pw::spa::utils::dict::DictRef>::as_ref(props).as_raw_ptr()
}

fn serialize(value: &Value) -> Vec<u8> {
    PodSerializer::serialize(Cursor::new(Vec::new()), value)
        .unwrap()
        .0
        .into_inner()
}

fn object(type_: u32, id: u32, properties: Vec<Property>) -> Value {
    Value::Object(Object {
        type_,
        id,
        properties,
    })
}

impl Card {
    fn route(&self) -> Value {
        let props = object(
            spa::SPA_TYPE_OBJECT_Props,
            spa::SPA_PARAM_Route,
            vec![
                Property::new(spa::SPA_PROP_mute, Value::Bool(self.mute)),
                Property::new(
                    spa::SPA_PROP_channelVolumes,
                    Value::ValueArray(ValueArray::Float(self.volumes.clone())),
                ),
                Property::new(
                    spa::SPA_PROP_channelMap,
                    Value::ValueArray(ValueArray::Id(vec![
                        pw::spa::utils::Id(spa::SPA_AUDIO_CHANNEL_FL),
                        pw::spa::utils::Id(spa::SPA_AUDIO_CHANNEL_FR),
                    ])),
                ),
            ],
        );
        object(
            spa::SPA_TYPE_OBJECT_ParamRoute,
            spa::SPA_PARAM_Route,
            vec![
                Property::new(spa::SPA_PARAM_ROUTE_index, Value::Int(ROUTE_INDEX)),
                Property::new(
                    spa::SPA_PARAM_ROUTE_direction,
                    Value::Id(pw::spa::utils::Id(spa::SPA_DIRECTION_OUTPUT)),
                ),
                Property::new(spa::SPA_PARAM_ROUTE_name, Value::String("speaker".into())),
                Property::new(spa::SPA_PARAM_ROUTE_device, Value::Int(ROUTE_DEVICE)),
                Property::new(spa::SPA_PARAM_ROUTE_props, props),
                Property::new(spa::SPA_PARAM_ROUTE_save, Value::Bool(self.save)),
                Property::new(spa::SPA_PARAM_ROUTE_profile, Value::Int(1)),
            ],
        )
    }

    fn profile(&self) -> Value {
        object(
            spa::SPA_TYPE_OBJECT_ParamProfile,
            spa::SPA_PARAM_Profile,
            vec![Property::new(
                spa::SPA_PARAM_PROFILE_index,
                Value::Int(i32::from(self.active)),
            )],
        )
    }

    /// Calls `f` with each listener's events and data.
    fn each_listener(&mut self, mut f: impl FnMut(&spa::spa_device_events, *mut c_void)) {
        let head = &raw mut self.hooks;
        // SAFETY: the list holds only the hooks `add_listener` linked in,
        // each a `spa_hook` whose first field is its link and whose funcs
        // are the caller's `spa_device_events`.
        unsafe {
            let mut link = (*head).next;
            while link != head {
                let next = (*link).next;
                let hook = link.cast::<spa::spa_hook>();
                f(
                    &*(*hook).cb.funcs.cast::<spa::spa_device_events>(),
                    (*hook).cb.data,
                );
                link = next;
            }
        }
    }

    fn info(&self, change_mask: u32) -> spa::spa_device_info {
        spa::spa_device_info {
            version: spa::SPA_VERSION_DEVICE_INFO,
            change_mask: u64::from(change_mask),
            flags: 0,
            props: dict(&self.props),
            params: self.params.as_ptr().cast_mut(),
            n_params: 2,
        }
    }

    /// Bumps the serial of `ids` and tells every listener, as a device does
    /// when a param changes.
    fn changed(&mut self, ids: &[u32]) {
        for p in &mut self.params {
            if ids.contains(&p.id) {
                p.flags ^= spa::SPA_PARAM_INFO_SERIAL;
            }
        }
        let info = self.info(spa::SPA_DEVICE_CHANGE_MASK_PARAMS);
        self.each_listener(|events, data| {
            if let Some(f) = events.info {
                // SAFETY: `info` and the params it points to outlive the call.
                unsafe { f(data, &raw const info) };
            }
        });
    }

    fn set_route(&mut self, param: &Pod) -> c_int {
        let Ok((_, Value::Object(route))) = PodDeserializer::deserialize_any_from(param.as_bytes())
        else {
            return -EINVAL;
        };
        let mut device = None;
        let mut props = None;
        for p in route.properties {
            match (p.key, p.value) {
                (spa::SPA_PARAM_ROUTE_device, Value::Int(d)) => device = Some(d),
                (spa::SPA_PARAM_ROUTE_props, Value::Object(o)) => props = Some(o),
                (spa::SPA_PARAM_ROUTE_save, Value::Bool(s)) => self.save = s,
                _ => {}
            }
        }
        if device != Some(ROUTE_DEVICE) || !self.active {
            return -EINVAL;
        }
        for p in props.map(|o| o.properties).unwrap_or_default() {
            match (p.key, p.value) {
                (spa::SPA_PROP_channelVolumes, Value::ValueArray(ValueArray::Float(v)))
                    if !v.is_empty() =>
                {
                    self.volumes = (0..self.volumes.len()).map(|i| v[i % v.len()]).collect();
                }
                (spa::SPA_PROP_mute, Value::Bool(m)) => self.mute = m,
                _ => {}
            }
        }
        self.changed(&[spa::SPA_PARAM_Route]);
        0
    }

    fn set_profile(&mut self, param: &Pod) -> c_int {
        let Ok((_, Value::Object(profile))) =
            PodDeserializer::deserialize_any_from(param.as_bytes())
        else {
            return -EINVAL;
        };
        for p in profile.properties {
            if let (spa::SPA_PARAM_PROFILE_index, Value::Int(i)) = (p.key, p.value) {
                self.active = i == 1;
            }
        }
        self.changed(&[spa::SPA_PARAM_Profile, spa::SPA_PARAM_Route]);
        0
    }
}

const EINVAL: c_int = 22;
const ENOENT: c_int = 2;

/// # Safety
/// `object` is the `Card` the device was exported with.
unsafe fn card<'a>(object: *mut c_void) -> &'a mut Card {
    // SAFETY: per the caller.
    unsafe { &mut *object.cast::<Card>() }
}

unsafe extern "C" fn add_listener(
    object: *mut c_void,
    listener: *mut spa::spa_hook,
    events: *const spa::spa_device_events,
    data: *mut c_void,
) -> c_int {
    // SAFETY: PipeWire passes the exported object and a hook it owns.
    unsafe {
        let card = card(object);
        (*listener).cb.funcs = events.cast();
        (*listener).cb.data = data;
        let head = &raw mut card.hooks;
        (*listener).link.prev = (*head).prev;
        (*listener).link.next = head;
        (*(*head).prev).next = &raw mut (*listener).link;
        (*head).prev = &raw mut (*listener).link;
        let info =
            card.info(spa::SPA_DEVICE_CHANGE_MASK_PROPS | spa::SPA_DEVICE_CHANGE_MASK_PARAMS);
        if let Some(f) = (*events).info {
            f(data, &raw const info);
        }
    }
    0
}

fn emit_result(card: &mut Card, seq: c_int, type_: u32, result: *const c_void) {
    card.each_listener(|events, data| {
        if let Some(f) = events.result {
            // SAFETY: `result` outlives the call.
            unsafe { f(data, seq, 0, type_, result) };
        }
    });
}

unsafe extern "C" fn sync(object: *mut c_void, seq: c_int) -> c_int {
    // SAFETY: the exported object.
    emit_result(unsafe { card(object) }, seq, 0, ptr::null());
    0
}

unsafe extern "C" fn enum_params(
    object: *mut c_void,
    seq: c_int,
    id: u32,
    start: u32,
    _max: u32,
    _filter: *const spa::spa_pod,
) -> c_int {
    // SAFETY: the exported object.
    let card = unsafe { card(object) };
    // Like bluez5's, the output route comes after the absent input one.
    let (index, value) = match id {
        spa::SPA_PARAM_Route if card.active && start <= 1 => (1, card.route()),
        spa::SPA_PARAM_Profile if start == 0 => (0, card.profile()),
        spa::SPA_PARAM_Route | spa::SPA_PARAM_Profile => return 0,
        _ => return -ENOENT,
    };
    let mut bytes = serialize(&value);
    let result = spa::spa_result_device_params {
        id,
        index,
        next: index + 1,
        param: bytes.as_mut_ptr().cast(),
    };
    emit_result(
        card,
        seq,
        spa::SPA_RESULT_TYPE_DEVICE_PARAMS,
        ptr::from_ref(&result).cast(),
    );
    0
}

unsafe extern "C" fn set_param(
    object: *mut c_void,
    id: u32,
    _flags: u32,
    param: *const spa::spa_pod,
) -> c_int {
    // SAFETY: the exported object, and a whole pod or null.
    let (card, param) = unsafe {
        (
            card(object),
            (!param.is_null()).then(|| Pod::from_raw(param)),
        )
    };
    match (id, param) {
        (spa::SPA_PARAM_Route, Some(p)) => card.set_route(p),
        (spa::SPA_PARAM_Profile, Some(p)) => card.set_profile(p),
        _ => -EINVAL,
    }
}

static METHODS: spa::spa_device_methods = spa::spa_device_methods {
    version: spa::SPA_VERSION_DEVICE_METHODS,
    add_listener: Some(add_listener),
    sync: Some(sync),
    enum_params: Some(enum_params),
    set_param: Some(set_param),
};

/// Exports the card and its node into the `PipeWire` at `socket`; returns
/// the card's id once both are in the graph. They last as long as that
/// `PipeWire` does.
pub fn start(socket: &Path, volume: f32) -> u32 {
    let socket = socket.display().to_string();
    let (tx, rx) = mpsc::channel();
    thread::spawn(move || run(&socket, volume, &tx));
    rx.recv().unwrap()
}

fn run(socket: &str, volume: f32, ready: &mpsc::Sender<u32>) {
    pw::init();
    let main_loop = pw::main_loop::MainLoopRc::new(None).unwrap();
    let context = pw::context::ContextRc::new(&main_loop, None).unwrap();
    let core = context
        .connect_rc(Some(
            pw::properties::properties! { "remote.name" => socket },
        ))
        .unwrap();

    let card = Box::leak(Box::new(Card {
        device: spa::spa_device {
            iface: spa::spa_interface {
                type_: spa::SPA_TYPE_INTERFACE_Device.as_ptr().cast(),
                version: spa::SPA_VERSION_DEVICE,
                cb: spa::spa_callbacks {
                    funcs: ptr::from_ref(&METHODS).cast(),
                    data: ptr::null_mut(),
                },
            },
        },
        hooks: spa::spa_list {
            next: ptr::null_mut(),
            prev: ptr::null_mut(),
        },
        props: pw::properties::properties! {
            "device.name" => "test-card",
            "device.description" => "Test Card",
            "device.api" => "test",
            "media.class" => "Audio/Device",
        },
        params: [
            param_info(spa::SPA_PARAM_Route),
            param_info(spa::SPA_PARAM_Profile),
        ],
        active: false,
        volumes: vec![volume; 2],
        mute: false,
        save: false,
    }));
    let card_ptr: *mut Card = card;
    card.device.iface.cb.data = card_ptr.cast();
    let head = &raw mut card.hooks;
    card.hooks.next = head;
    card.hooks.prev = head;

    // SAFETY: the core is connected and the card lives forever.
    let proxy = unsafe {
        pw::sys::pw_core_export(
            core.as_raw_ptr(),
            spa::SPA_TYPE_INTERFACE_Device.as_ptr().cast(),
            dict(&card.props),
            ptr::from_mut(&mut card.device).cast(),
            0,
        )
    };
    assert!(!proxy.is_null(), "cannot export the card");

    let exported = core.sync(0).unwrap();
    let node: Rc<RefCell<Option<(pw::node::Node, u32, AsyncSeq)>>> = Rc::default();
    let ready = ready.clone();
    let _listener = core
        .add_listener_local()
        .done({
            let core = core.clone();
            let node = Rc::clone(&node);
            move |_, seq| {
                if seq == exported {
                    // SAFETY: the proxy is the card's, bound by now.
                    let id = unsafe { pw::sys::pw_proxy_get_bound_id(proxy) };
                    let n = core
                        .create_object::<pw::node::Node>(
                            "adapter",
                            &pw::properties::properties! {
                                "factory.name" => "support.null-audio-sink",
                                "node.name" => NODE_NAME,
                                "node.description" => "Test Route Sink",
                                "media.class" => "Audio/Sink",
                                "audio.position" => "[ FL FR ]",
                                "device.id" => id.to_string(),
                                "card.profile.device" => ROUTE_DEVICE.to_string(),
                            },
                        )
                        .unwrap();
                    let created = core.sync(0).unwrap();
                    *node.borrow_mut() = Some((n, id, created));
                } else if let Some((_, id, created)) = node.borrow().as_ref() {
                    if seq == *created {
                        ready.send(*id).ok();
                    }
                }
            }
        })
        .error({
            let main_loop = main_loop.downgrade();
            move |id, _, _, _| {
                if id == pw::core::PW_ID_CORE {
                    if let Some(l) = main_loop.upgrade() {
                        l.quit();
                    }
                }
            }
        })
        .register();
    main_loop.run();
}
