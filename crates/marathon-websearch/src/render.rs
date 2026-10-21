//! `marathon-websearch render <url>`: the page loaded in WPE, Pacific's
//! engine, with no window (WPEBackend-fdo's shared-memory exporter, each
//! frame handed straight back), and its rendered DOM printed once it has
//! loaded and run its scripts. The engine is loaded at run time, so the
//! service builds and answers from fetched pages without it.

use std::ffi::{c_char, c_int, c_uint, c_void, CStr, CString};
use std::io::Write as _;
use std::ptr;

use glib_sys::{gboolean, gpointer, GError, GFALSE};
use gobject_sys::{GCallback, GObject};
use libloading::Library;
use marathon_rt::log;

const WIDTH: u32 = 720;
const HEIGHT: u32 = 1440;
/// `WEBKIT_LOAD_FINISHED`.
const LOAD_FINISHED: c_int = 3;
/// After the load, for the page's own scripts to fill it in.
const SETTLE_MS: c_uint = 1200;
const GIVE_UP_S: c_uint = 7;

#[repr(C)]
struct ExportableClient {
    export_buffer_resource: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
    export_dmabuf_resource: Option<unsafe extern "C" fn(*mut c_void, *mut DmabufResource)>,
    export_shm_buffer: Option<unsafe extern "C" fn(*mut c_void, *mut c_void)>,
    reserved0: Option<unsafe extern "C" fn()>,
    reserved1: Option<unsafe extern "C" fn()>,
}

#[repr(C)]
struct DmabufResource {
    buffer_resource: *mut c_void,
}

type Create = unsafe extern "C" fn(*const ExportableClient, *mut c_void, u32, u32) -> *mut c_void;
type Exported = unsafe extern "C" fn(*mut c_void) -> *mut c_void;
type Release = unsafe extern "C" fn(*mut c_void, *mut c_void);
type FrameComplete = unsafe extern "C" fn(*mut c_void);

/// What the exporter's callbacks need, kept for the process's life.
struct Frames {
    exportable: *mut c_void,
    release_buffer: Release,
    release_shm: Release,
    frame_complete: FrameComplete,
}

struct Page {
    eval: unsafe extern "C" fn(*mut c_void, *const c_char, isize, *const c_char, *const c_char, *mut c_void, gio_callback, gpointer),
    eval_finish: unsafe extern "C" fn(*mut c_void, *mut c_void, *mut *mut GError) -> *mut c_void,
    to_string: unsafe extern "C" fn(*mut c_void) -> *mut c_char,
    view: *mut c_void,
    main_loop: *mut glib_sys::GMainLoop,
    status: c_int,
}

#[allow(non_camel_case_types, reason = "GLib's name")]
type gio_callback = Option<unsafe extern "C" fn(*mut GObject, *mut c_void, gpointer)>;

const SCRIPT: &CStr = c"document.documentElement.outerHTML";

unsafe extern "C" fn buffer(data: *mut c_void, resource: *mut c_void) {
    // SAFETY: `data` is the leaked `Frames` main gave the exporter.
    let f = unsafe { &*data.cast::<Frames>() };
    // SAFETY: the exporter's own buffer, released once, then the frame.
    unsafe {
        (f.release_buffer)(f.exportable, resource);
        (f.frame_complete)(f.exportable);
    }
}

unsafe extern "C" fn dmabuf(data: *mut c_void, resource: *mut DmabufResource) {
    // SAFETY: as `buffer`; the exporter passes a valid resource.
    unsafe { buffer(data, (*resource).buffer_resource) }
}

unsafe extern "C" fn shm(data: *mut c_void, exported: *mut c_void) {
    // SAFETY: as `buffer`.
    let f = unsafe { &*data.cast::<Frames>() };
    // SAFETY: as `buffer`.
    unsafe {
        (f.release_shm)(f.exportable, exported);
        (f.frame_complete)(f.exportable);
    }
}

unsafe extern "C" fn load_changed(_view: *mut c_void, event: c_int, data: gpointer) {
    if event == LOAD_FINISHED {
        // SAFETY: GLib calls it on the main loop's thread, with `data` set
        // by main.
        unsafe { glib_sys::g_timeout_add(SETTLE_MS, Some(evaluate), data) };
    }
}

unsafe extern "C" fn load_failed(_view: *mut c_void, _event: c_int, _uri: *const c_char, _error: *mut GError, data: gpointer) -> gboolean {
    // SAFETY: as `load_changed`.
    let page = unsafe { &mut *data.cast::<Page>() };
    page.status = 2;
    // SAFETY: the loop main runs.
    unsafe { glib_sys::g_main_loop_quit(page.main_loop) };
    GFALSE
}

unsafe extern "C" fn evaluate(data: gpointer) -> gboolean {
    // SAFETY: as `load_changed`.
    let page = unsafe { &*data.cast::<Page>() };
    // SAFETY: the view is alive; the script is a NUL-terminated string.
    unsafe { (page.eval)(page.view, SCRIPT.as_ptr(), -1, ptr::null(), ptr::null(), ptr::null_mut(), Some(evaluated), data) };
    GFALSE
}

unsafe extern "C" fn evaluated(_source: *mut GObject, result: *mut c_void, data: gpointer) {
    // SAFETY: as `load_changed`.
    let page = unsafe { &mut *data.cast::<Page>() };
    let mut error = ptr::null_mut();
    // SAFETY: the result GLib handed this callback.
    let value = unsafe { (page.eval_finish)(page.view, result, &raw mut error) };
    if value.is_null() {
        page.status = 2;
    } else {
        // SAFETY: a JSCValue; its string is ours to free.
        let text = unsafe { (page.to_string)(value) };
        if !text.is_null() {
            // SAFETY: a NUL-terminated string from JSC.
            let html = unsafe { CStr::from_ptr(text) }.to_string_lossy();
            #[allow(clippy::print_stdout, reason = "the rendered page is this process's output")]
            {
                print!("{html}");
            }
            std::io::stdout().flush().ok();
            // SAFETY: allocated by GLib for us.
            unsafe { glib_sys::g_free(text.cast()) };
        }
    }
    // SAFETY: the loop main runs.
    unsafe { glib_sys::g_main_loop_quit(page.main_loop) };
}

unsafe extern "C" fn give_up(data: gpointer) -> gboolean {
    // SAFETY: as `load_changed`.
    let page = unsafe { &mut *data.cast::<Page>() };
    page.status = 3;
    // SAFETY: the loop main runs.
    unsafe { glib_sys::g_main_loop_quit(page.main_loop) };
    GFALSE
}

/// Its exit status: 0 printed, 1 no engine, 2 the page failed, 3 too slow.
pub fn main(url: &str) -> i32 {
    match run(url) {
        Ok(status) => status,
        Err(e) => {
            log::warn("websearch", format_args!("render: {e}"));
            1
        }
    }
}

fn run(url: &str) -> Result<i32, libloading::Error> {
    let Ok(uri) = CString::new(url) else { return Ok(2) };
    // SAFETY: system libraries with C constructors only.
    let (wpe, fdo, webkit) = unsafe { (Library::new("libwpe-1.0.so.1")?, Library::new("libWPEBackend-fdo-1.0.so.1")?, Library::new("libWPEWebKit-2.0.so.1")?) };
    // SAFETY: each symbol is looked up with its C signature (wpe/fdo.h,
    // wpe/WebKitWebView.h); the libraries outlive this function's loop.
    unsafe {
        let loader_init: libloading::Symbol<unsafe extern "C" fn(*const c_char) -> bool> = wpe.get(b"wpe_loader_init\0")?;
        let initialize_shm: libloading::Symbol<unsafe extern "C" fn() -> bool> = fdo.get(b"wpe_fdo_initialize_shm\0")?;
        let create: libloading::Symbol<Create> = fdo.get(b"wpe_view_backend_exportable_fdo_create\0")?;
        let view_backend: libloading::Symbol<Exported> = fdo.get(b"wpe_view_backend_exportable_fdo_get_view_backend\0")?;
        let frames = Box::leak(Box::new(Frames {
            exportable: ptr::null_mut(),
            release_buffer: *fdo.get::<Release>(b"wpe_view_backend_exportable_fdo_dispatch_release_buffer\0")?,
            release_shm: *fdo.get::<Release>(b"wpe_view_backend_exportable_fdo_dispatch_release_shm_exported_buffer\0")?,
            frame_complete: *fdo.get::<FrameComplete>(b"wpe_view_backend_exportable_fdo_dispatch_frame_complete\0")?,
        }));
        let backend_new: libloading::Symbol<unsafe extern "C" fn(*mut c_void, Option<unsafe extern "C" fn(gpointer)>, gpointer) -> *mut c_void> = webkit.get(b"webkit_web_view_backend_new\0")?;
        let view_type: libloading::Symbol<unsafe extern "C" fn() -> glib_sys::GType> = webkit.get(b"webkit_web_view_get_type\0")?;
        let ephemeral: libloading::Symbol<unsafe extern "C" fn() -> *mut c_void> = webkit.get(b"webkit_network_session_new_ephemeral\0")?;
        let settings: libloading::Symbol<unsafe extern "C" fn(*mut c_void) -> *mut c_void> = webkit.get(b"webkit_web_view_get_settings\0")?;
        let load_uri: libloading::Symbol<unsafe extern "C" fn(*mut c_void, *const c_char)> = webkit.get(b"webkit_web_view_load_uri\0")?;

        if !loader_init(c"libWPEBackend-fdo-1.0.so.1".as_ptr()) || !initialize_shm() {
            return Ok(1);
        }
        let client = Box::leak(Box::new(ExportableClient {
            export_buffer_resource: Some(buffer),
            export_dmabuf_resource: Some(dmabuf),
            export_shm_buffer: Some(shm),
            reserved0: None,
            reserved1: None,
        }));
        let frames_ptr: *mut Frames = frames;
        frames.exportable = create(client, frames_ptr.cast(), WIDTH, HEIGHT);
        if frames.exportable.is_null() {
            return Ok(1);
        }
        let backend = backend_new(view_backend(frames.exportable), None, ptr::null_mut());
        let view = gobject_sys::g_object_new(view_type(), c"backend".as_ptr(), backend, c"network-session".as_ptr(), ephemeral(), ptr::null::<c_char>());
        gobject_sys::g_object_set(settings(view.cast()).cast(), c"auto-load-images".as_ptr(), GFALSE, c"enable-media".as_ptr(), GFALSE, ptr::null::<c_char>());
        let page = Box::leak(Box::new(Page {
            eval: *webkit.get(b"webkit_web_view_evaluate_javascript\0")?,
            eval_finish: *webkit.get(b"webkit_web_view_evaluate_javascript_finish\0")?,
            to_string: *webkit.get(b"jsc_value_to_string\0")?,
            view: view.cast(),
            main_loop: glib_sys::g_main_loop_new(ptr::null_mut(), GFALSE),
            status: 0,
        }));
        let data: *mut Page = page;
        connect(view, c"load-changed", std::mem::transmute::<unsafe extern "C" fn(*mut c_void, c_int, gpointer), unsafe extern "C" fn()>(load_changed), data.cast());
        connect(view, c"load-failed", std::mem::transmute::<unsafe extern "C" fn(*mut c_void, c_int, *const c_char, *mut GError, gpointer) -> gboolean, unsafe extern "C" fn()>(load_failed), data.cast());
        glib_sys::g_timeout_add_seconds(GIVE_UP_S, Some(give_up), data.cast());
        load_uri(view.cast(), uri.as_ptr());
        glib_sys::g_main_loop_run(page.main_loop);
        // The engine's processes go with this one; nothing to tear down.
        Ok(page.status)
    }
}

/// # Safety
/// `handler` must have the signal's C signature.
unsafe fn connect(object: *mut GObject, signal: &CStr, handler: unsafe extern "C" fn(), data: gpointer) {
    let callback: GCallback = Some(handler);
    // SAFETY: per this function's contract.
    unsafe { gobject_sys::g_signal_connect_data(object.cast(), signal.as_ptr(), callback, data, None, 0) };
}
