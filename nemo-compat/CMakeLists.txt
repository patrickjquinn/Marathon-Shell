# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Qt6 builds of the open Nemo QML plugins (see PROVENANCE.md):
#   Nemo.DBus 2.0           (+ legacy org.nemomobile.dbus 2.0)
#   Nemo.Notifications 1.0  (+ legacy org.nemomobile.notifications 1.0)
#   Nemo.KeepAlive 1.1/1.2  (+ legacy org.nemomobile.keepalive 1.0/1.1)
#   Nemo.Configuration 1.0  (+ legacy org.nemomobile.configuration 1.0)
#   org.nemomobile.lipstick 0.1 (lipstick's launcher types, LGPL, with mlite's
#                            MDesktopEntry compiled in)
#   Nemo.Policy 1.0         (+ legacy org.nemomobile.policy 1.0;
#                            nemo-qml-plugin-policy on libresourceqt's
#                            ResourceSet with Keel's QtDBus engine)
#   Nemo.Ngf 1.0            (+ legacy org.nemomobile.ngf 1.0; libngf-qt)
# The upstream sources are kept as they are, under their own licences; the
# build, the legacy URI registration and the host fallbacks are Keel's.
#
# Each module is one plugin library. The legacy URI directories hold only a
# qmldir whose `plugin` line points at the library in the Nemo directory, so
# both URIs share one binary (the upstream plugins accept both URIs).

include(CheckIncludeFileCXX)

function(keel_nemo_module target uri_dir)
    set_target_properties(${target} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${uri_dir}"
        CXX_VISIBILITY_PRESET hidden
        VISIBILITY_INLINES_HIDDEN ON)
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/qmldir/${target}.qmldir"
                   "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/qmldir" COPYONLY)
    # The types the plugin registers at run time, for QML tooling
    # (keel/tools/qmltypes.py writes them).
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/qmldir/${target}.qmltypes"
                   "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/plugins.qmltypes" COPYONLY)
    install(TARGETS ${target} LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${uri_dir}")
    install(FILES "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${uri_dir}/plugins.qmltypes"
            DESTINATION "${KEEL_QML_INSTALL_DIR}/${uri_dir}")
endfunction()

function(keel_nemo_legacy legacy_dir qmldir_file)
    string(REPLACE ".qmldir" ".qmltypes" types_file "${qmldir_file}")
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/qmldir/${qmldir_file}"
                   "${KEEL_QML_OUTPUT_DIR}/${legacy_dir}/qmldir" COPYONLY)
    configure_file("${CMAKE_CURRENT_SOURCE_DIR}/qmldir/${types_file}"
                   "${KEEL_QML_OUTPUT_DIR}/${legacy_dir}/plugins.qmltypes" COPYONLY)
    install(FILES "${KEEL_QML_OUTPUT_DIR}/${legacy_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${legacy_dir}/plugins.qmltypes"
            DESTINATION "${KEEL_QML_INSTALL_DIR}/${legacy_dir}")
endfunction()

# ---------------------------------------------------------------------------
# Nemo.DBus (LGPL-2.1 plugin, BSD-3-Clause nemo-dbus helpers)
# ---------------------------------------------------------------------------
add_library(nemodbus MODULE
    dbus/plugin.cpp
    dbus/declarativedbus.cpp dbus/declarativedbus.h
    dbus/declarativedbusadaptor.cpp dbus/declarativedbusadaptor.h
    dbus/declarativedbusinterface.cpp dbus/declarativedbusinterface.h
    dbus/nemo-dbus/connection.cpp dbus/nemo-dbus/connection.h
    dbus/nemo-dbus/dbus.cpp dbus/nemo-dbus/dbus.h
    dbus/nemo-dbus/interface.cpp dbus/nemo-dbus/interface.h
    dbus/nemo-dbus/logging.cpp dbus/nemo-dbus/logging.h
    dbus/nemo-dbus/object.cpp dbus/nemo-dbus/object.h
    dbus/nemo-dbus/response.cpp dbus/nemo-dbus/response.h
    dbus/nemo-dbus/private/propertychanges.cpp dbus/nemo-dbus/private/propertychanges.h
    dbus/nemo-dbus/private/connectiondata.h
    dbus/nemo-dbus/global.h)
target_include_directories(nemodbus PRIVATE dbus dbus/nemo-dbus dbus/nemo-dbus/private)
# The helpers are compiled into the plugin, not exported from a library.
target_compile_definitions(nemodbus PRIVATE NEMODBUS_BUILD_LIBRARY)
target_link_libraries(nemodbus PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
keel_nemo_module(nemodbus Nemo/DBus)
keel_nemo_legacy(org/nemomobile/dbus org.nemomobile.dbus.qmldir)

# ---------------------------------------------------------------------------
# Nemo.Notifications (BSD-3-Clause)
# ---------------------------------------------------------------------------
set(_notif_proxy_src)
set_source_files_properties(notifications/org.freedesktop.Notifications.xml PROPERTIES
    CLASSNAME NotificationManagerProxy INCLUDE notification_p.h)
qt_add_dbus_interface(_notif_proxy_src notifications/org.freedesktop.Notifications.xml
    notificationmanagerproxy)
add_library(nemonotifications MODULE
    notifications/plugin.cpp
    notifications/notification.cpp notifications/notification.h
    notifications/notification_p.h notifications/notificationexport.h
    ${_notif_proxy_src})
target_include_directories(nemonotifications PRIVATE notifications "${CMAKE_CURRENT_BINARY_DIR}")
target_compile_definitions(nemonotifications PRIVATE BUILD_NEMO_QML_PLUGIN_NOTIFICATIONS_LIB)
target_link_libraries(nemonotifications PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml)
keel_nemo_module(nemonotifications Nemo/Notifications)
keel_nemo_legacy(org/nemomobile/notifications org.nemomobile.notifications.qmldir)

# ---------------------------------------------------------------------------
# Nemo.KeepAlive (LGPL-2.1). Uses libiphb and mce-headers when present (the
# Sailfish target); falls back to Keel's timer-based stand-ins otherwise.
# ---------------------------------------------------------------------------
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_IPHB IMPORTED_TARGET libiphb)
endif()
check_include_file_cxx(mce/dbus-names.h KEEL_HAVE_MCE_HEADERS)
option(KEEL_REQUIRE_IPHB "Fail if libiphb is missing (device builds)" OFF)
if(KEEL_REQUIRE_IPHB AND NOT KEEL_IPHB_FOUND)
    message(FATAL_ERROR "libiphb not found (pkg-config libiphb)")
endif()

set(_mce_src)
# One header, mceiface.h, with both com.nokia.mce.request and .signal proxies.
qt_add_dbus_interface(_mce_src keepalive/mceiface.xml mceiface)
add_library(keepaliveplugin MODULE
    keepalive/plugin.cpp
    keepalive/declarativebackgroundactivity.cpp keepalive/declarativebackgroundactivity.h
    keepalive/backgroundactivity.cpp keepalive/backgroundactivity.h
    keepalive/backgroundactivity_p.cpp keepalive/backgroundactivity_p.h
    keepalive/displayblanking.cpp keepalive/displayblanking.h
    keepalive/displayblanking_p.cpp keepalive/displayblanking_p.h
    keepalive/heartbeat.cpp keepalive/heartbeat.h
    keepalive/common.h
    ${_mce_src})
target_include_directories(keepaliveplugin PRIVATE keepalive "${CMAKE_CURRENT_BINARY_DIR}")
target_link_libraries(keepaliveplugin PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
if(KEEL_IPHB_FOUND)
    target_link_libraries(keepaliveplugin PRIVATE PkgConfig::KEEL_IPHB)
else()
    message(STATUS "Nemo.KeepAlive: libiphb not found, using Keel's timer fallback (no wakeups from suspend)")
    target_sources(keepaliveplugin PRIVATE keepalive/compat/iphb_fallback.cpp keepalive/compat/iphbd/libiphb.h)
    target_include_directories(keepaliveplugin PRIVATE keepalive/compat)
    find_package(Threads REQUIRED)
    target_link_libraries(keepaliveplugin PRIVATE Threads::Threads)
endif()
if(NOT KEEL_HAVE_MCE_HEADERS)
    target_include_directories(keepaliveplugin PRIVATE keepalive/compat)
endif()
keel_nemo_module(keepaliveplugin Nemo/KeepAlive)
keel_nemo_legacy(org/nemomobile/keepalive org.nemomobile.keepalive.qmldir)

# ---------------------------------------------------------------------------
# Nemo.Configuration (BSD-3-Clause). Uses mlite-qt6 (MDConfGroup/MDConfItem
# over dconf) when present, as on the Sailfish target with Chum's
# mlite-qt6-devel; otherwise Keel's fallback MDConf classes over a JSON file
# (configuration/compat, see PROVENANCE.md).
# ---------------------------------------------------------------------------
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_MLITE IMPORTED_TARGET mlite6)
endif()
option(KEEL_REQUIRE_MLITE "Fail if mlite6 is missing (device builds)" OFF)
if(KEEL_REQUIRE_MLITE AND NOT KEEL_MLITE_FOUND)
    message(FATAL_ERROR "mlite6 not found (pkg-config mlite6, Chum's mlite-qt6-devel)")
endif()
add_library(nemoconfiguration MODULE
    configuration/plugin.cpp
    configuration/configurationgroup.cpp configuration/configurationgroup.h
    configuration/configurationvalue.cpp configuration/configurationvalue.h)
target_link_libraries(nemoconfiguration PRIVATE Qt6::Core Qt6::Qml)
# Upstream configurationvalue.cpp uses QMetaType::type(const char *), deprecated
# in Qt 6 but present in 6.4 and 6.8; upstream is built unchanged.
target_compile_options(nemoconfiguration PRIVATE -Wno-deprecated-declarations)
if(KEEL_MLITE_FOUND)
    target_link_libraries(nemoconfiguration PRIVATE PkgConfig::KEEL_MLITE)
else()
    message(STATUS "Nemo.Configuration: mlite6 not found, using Keel's JSON-file fallback (no dconf)")
    target_sources(nemoconfiguration PRIVATE
        configuration/compat/mdconfgroup.cpp configuration/compat/mdconfgroup.h
        configuration/compat/mdconfitem.cpp configuration/compat/mdconfitem.h
        configuration/compat/keeldconfstore.cpp configuration/compat/keeldconfstore.h
        configuration/compat/mlite-global.h)
    target_include_directories(nemoconfiguration PRIVATE configuration/compat)
endif()
keel_nemo_module(nemoconfiguration Nemo/Configuration)
keel_nemo_legacy(org/nemomobile/configuration org.nemomobile.configuration.qmldir)

# ---------------------------------------------------------------------------
# org.nemomobile.lipstick 0.1: lipstick's launcher types (LGPL-2.1-only,
# lipstick/upstream) with mlite's MDesktopEntry and MRemoteAction (LGPL-2.1,
# lipstick/mlite) compiled in, launching through GIO's GDesktopAppInfo as
# lipstick does without contentaction (see PROVENANCE.md).
# ---------------------------------------------------------------------------
option(KEEL_REQUIRE_GIO "Fail if gio-unix-2.0 is missing (device builds)" OFF)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_GIO IMPORTED_TARGET gio-unix-2.0)
endif()
if(TARGET PkgConfig::KEEL_GIO)
    add_library(keellipstick MODULE
        lipstick/plugin.cpp
        lipstick/upstream/components/launcherdbus.cpp lipstick/upstream/components/launcherdbus.h
        lipstick/upstream/components/launcherfolderitem.cpp lipstick/upstream/components/launcherfolderitem.h
        lipstick/upstream/components/launcherfoldermodel.cpp lipstick/upstream/components/launcherfoldermodel.h
        lipstick/upstream/components/launcheritem.cpp lipstick/upstream/components/launcheritem.h
        lipstick/upstream/components/launchermodel.cpp lipstick/upstream/components/launchermodel.h
        lipstick/upstream/components/launchermonitor.cpp lipstick/upstream/components/launchermonitor.h
        lipstick/upstream/components/launcherwatchermodel.cpp lipstick/upstream/components/launcherwatchermodel.h
        lipstick/upstream/utilities/qobjectlistmodel.cpp lipstick/upstream/utilities/qobjectlistmodel.h
        lipstick/upstream/3rdparty/synchronizelists.h
        lipstick/upstream/logging.cpp lipstick/upstream/logging.h
        lipstick/upstream/lipstickdbus.h lipstick/upstream/lipstickglobal.h
        lipstick/mlite/mdesktopentry.cpp lipstick/mlite/mdesktopentry.h lipstick/mlite/mdesktopentry_p.h
        lipstick/mlite/mremoteaction.cpp lipstick/mlite/mremoteaction.h lipstick/mlite/mremoteaction_p.h
        lipstick/mlite/logging.cpp lipstick/mlite/logging.h lipstick/mlite/mlite-global.h)
    set_target_properties(keellipstick PROPERTIES AUTOMOC ON)
    # Upstream as it is: QString::count() and QScopedPointer::take() are
    # deprecated in Qt 6.
    target_compile_options(keellipstick PRIVATE -Wno-deprecated-declarations)
    # Compiled into the plugin (hidden symbols): no library is exported.
    target_compile_definitions(keellipstick PRIVATE LIPSTICK_BUILD_LIBRARY)
    target_include_directories(keellipstick PRIVATE
        lipstick/upstream lipstick/upstream/components lipstick/upstream/utilities
        lipstick/upstream/3rdparty lipstick/mlite)
    target_link_libraries(keellipstick PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml PkgConfig::KEEL_GIO)
    keel_nemo_module(keellipstick org/nemomobile/lipstick)
else()
    if(KEEL_REQUIRE_GIO)
        message(FATAL_ERROR "gio-unix-2.0 not found (pkg-config gio-unix-2.0, glib2-devel)")
    endif()
    message(STATUS "org.nemomobile.lipstick: gio-unix-2.0 not found, not built")
endif()

# ---------------------------------------------------------------------------
# Nemo.Policy / org.nemomobile.policy 1.0: nemo-qml-plugin-policy (BSD-3-Clause)
# with libresourceqt's ResourceSet and resources (LGPL-2.1-only) compiled in.
# libresourceqt's engine (libresource over libdbus) is replaced by Keel's,
# which speaks the resource manager's D-Bus protocol on the system bus with
# QtDBus and grants locally when no manager runs (PROVENANCE.md).
# ---------------------------------------------------------------------------
add_library(nemopolicy MODULE
    policy/plugin/plugin.cpp
    policy/plugin/permissions.cpp policy/plugin/permissions.h
    policy/plugin/resource.cpp policy/plugin/resource.h
    policy/libresourceqt/src/resource.cpp policy/libresourceqt/src/resources.cpp
    policy/libresourceqt/src/audio-resource.cpp policy/libresourceqt/src/resource-set.cpp
    policy/libresourceqt/include/policy/resource.h policy/libresourceqt/include/policy/resources.h
    policy/libresourceqt/include/policy/audio-resource.h policy/libresourceqt/include/policy/resource-set.h
    policy/engine/resource-engine.cpp policy/engine/resource-engine.h)
target_include_directories(nemopolicy PRIVATE policy/libresourceqt/include policy/engine policy/plugin)
target_link_libraries(nemopolicy PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
keel_nemo_module(nemopolicy Nemo/Policy)
keel_nemo_legacy(org/nemomobile/policy org.nemomobile.policy.qmldir)

# ---------------------------------------------------------------------------
# Nemo.Ngf / org.nemomobile.ngf 1.0 (LGPL-2.1): libngf-qt's QML plugin with
# its Ngf::Client compiled in. Plays events through ngfd on the system bus
# (com.nokia.NonGraphicFeedback1.Backend), as the Qt 5 plugin does.
# ---------------------------------------------------------------------------
add_library(nemongf MODULE
    ngf/declarative/plugin.cpp
    ngf/declarative/declarativengfevent.cpp ngf/declarative/declarativengfevent.h
    ngf/declarative/declarativengfeventproperty.cpp ngf/declarative/declarativengfeventproperty.h
    ngf/client/client.cpp ngf/client/clientprivate.cpp ngf/client/clientprivate.h
    ngf/client/ngfclient.h ngf/client/ngfclient_global.h)
target_include_directories(nemongf PRIVATE ngf/client ngf/declarative)
# The client is compiled into the plugin, not exported from a library.
target_compile_definitions(nemongf PRIVATE NGFCLIENT_LIBRARY)
target_link_libraries(nemongf PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
# Upstream uses QVariant::type(), deprecated in Qt 6 but present in 6.4 and
# 6.8; upstream is built unchanged.
target_compile_options(nemongf PRIVATE -Wno-deprecated-declarations)
keel_nemo_module(nemongf Nemo/Ngf)
keel_nemo_legacy(org/nemomobile/ngf org.nemomobile.ngf.qmldir)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
