# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# keel-wl-shell: the Qt Wayland shell integration of Keel's direct mode
# (wl_shell + qt_extended_surface, as Lipstick expects; see keelwlshell.cpp).
# Keel's launcher asks for it first (QT_WAYLAND_SHELL_INTEGRATION=
# "keel-wl-shell;wl-shell"). Built when Qt's Wayland client private headers,
# libwayland-client and wayland-scanner are found; with
# KEEL_REQUIRE_WL_SHELL=ON (the RPM builds) their absence is an error, so a
# shipping build can never leave the plugin out without saying so.

option(KEEL_REQUIRE_WL_SHELL "Fail the configure step when keel-wl-shell cannot be built" OFF)

find_package(Qt6 ${KEEL_QT_MIN_VERSION} QUIET COMPONENTS WaylandClient)
set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 ${KEEL_QT_MIN_VERSION} QUIET COMPONENTS WaylandClientPrivate)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_WAYLAND_CLIENT QUIET IMPORTED_TARGET wayland-client)
endif()
find_program(KEEL_WAYLAND_SCANNER wayland-scanner)
if(NOT TARGET Qt6::WaylandClientPrivate OR NOT TARGET Qt6::GuiPrivate OR NOT KEEL_WAYLAND_CLIENT_FOUND
   OR NOT KEEL_WAYLAND_SCANNER)
    set(_keel_wl_shell_missing "keel-wl-shell: Qt Wayland client private headers, libwayland-client or "
                               "wayland-scanner missing")
    if(KEEL_REQUIRE_WL_SHELL)
        message(FATAL_ERROR "${_keel_wl_shell_missing} (KEEL_REQUIRE_WL_SHELL is ON). Direct mode on "
                            "Lipstick needs it: install qt6-qtwayland-devel (with its private headers), "
                            "wayland-devel and wayland-scanner.")
    endif()
    message(WARNING "${_keel_wl_shell_missing}; not built (direct mode on Lipstick needs it)")
    return()
endif()

# The protocol Lipstick (QtCompositor 5.6) serves; BSD-3-Clause, copied
# unmodified from sailfishos/qtwayland (see keel/shell/PROVENANCE.md).
set(_proto "${CMAKE_CURRENT_SOURCE_DIR}/../../shell/tests/e2e/fake-lipstick/surface-extension.xml")
set(_gen "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${_gen}")
add_custom_command(
    OUTPUT "${_gen}/surface-extension-client-protocol.h" "${_gen}/surface-extension-protocol.c"
    COMMAND "${KEEL_WAYLAND_SCANNER}" client-header "${_proto}" "${_gen}/surface-extension-client-protocol.h"
    COMMAND "${KEEL_WAYLAND_SCANNER}" private-code "${_proto}" "${_gen}/surface-extension-protocol.c"
    DEPENDS "${_proto}")
enable_language(C)

add_library(keel-wl-shell MODULE keelwlshell.cpp keel-wl-shell.json
    "${_gen}/surface-extension-protocol.c" "${_gen}/surface-extension-client-protocol.h")
target_include_directories(keel-wl-shell PRIVATE "${_gen}")
target_link_libraries(keel-wl-shell PRIVATE Qt6::WaylandClientPrivate Qt6::GuiPrivate PkgConfig::KEEL_WAYLAND_CLIENT)
set_target_properties(keel-wl-shell PROPERTIES
    PREFIX "lib"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON
    # Staged where tests point QT_PLUGIN_PATH.
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/plugins/wayland-shell-integration")

if(NOT DEFINED KEEL_QT_PLUGINS_INSTALL_DIR)
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)
    execute_process(COMMAND "${_keel_qmake}" -query QT_INSTALL_PLUGINS
                    OUTPUT_VARIABLE _keel_qt_plugins OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(KEEL_QT_PLUGINS_INSTALL_DIR "${_keel_qt_plugins}" CACHE PATH "Qt6 plugin directory to install into")
endif()
install(TARGETS keel-wl-shell LIBRARY DESTINATION "${KEEL_QT_PLUGINS_INSTALL_DIR}/wayland-shell-integration")
set(KEEL_WL_SHELL_PLUGIN_DIR "${CMAKE_BINARY_DIR}/plugins" PARENT_SCOPE)
