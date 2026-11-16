// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: Apache-2.0

//! The two C entry points Qt looks up in a dynamic plugin. CXX-Qt's plugin
//! class defines them in C++, renamed in build.rs because a Rust cdylib
//! exports only its own symbols; these export them under Qt's names.

use std::ffi::c_void;

/// `QPluginMetaData`: the plugin's metadata, as Qt's qplugin.h lays it out.
#[repr(C)]
pub struct QPluginMetaData {
    data: *const c_void,
    size: usize,
}

extern "C" {
    fn pacific_qt_plugin_instance() -> *mut c_void;
    fn pacific_qt_plugin_query_metadata_v2() -> QPluginMetaData;
}

#[no_mangle]
pub extern "C" fn qt_plugin_instance() -> *mut c_void {
    // SAFETY: moc's plugin instance function takes no arguments and returns
    // the plugin's QObject, created on first call.
    unsafe { pacific_qt_plugin_instance() }
}

#[no_mangle]
pub extern "C" fn qt_plugin_query_metadata_v2() -> QPluginMetaData {
    // SAFETY: moc's metadata function takes no arguments and returns a
    // pointer to static data with its size.
    unsafe { pacific_qt_plugin_query_metadata_v2() }
}
