# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Shipwright.Pacific.WebView 1.0: the QML module that shows WPE WebKit pages in
# Qt 6 Quick on the legacy libwpe + WPEBackend-fdo path (README.md).
#
#   cmake -S shoal/pacific/webview -B build -G Ninja
#   cmake --build build -j4
#
# Needs Qt 6.8+ (Core, Gui and its private headers, Qml, Quick, Positioning;
# Sensors optional), and pkg-config files for wpe-webkit-2.0, wpe-1.0,
# wpebackend-fdo-1.0, egl and glesv2 (shoal/pacific/engine provides them from
# the engine packages; tools/sdk-prefix.sh makes a build prefix from the
# mirrored RPMs).
cmake_minimum_required(VERSION 3.21)
project(pacific-webview VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

option(PACIFIC_WEBVIEW_EXAMPLES "Build examples/minibrowser" ON)
# Where the engine's libraries live on the device (shoal/pacific/engine).
set(PACIFIC_ENGINE_LIBDIR "/opt/pacific/lib" CACHE PATH "Run path for libWPEWebKit and friends")

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml Quick Positioning)
find_package(Qt6 6.8 QUIET OPTIONAL_COMPONENTS Sensors)
# Qt 6.10+ splits the private modules out (Qt 6.8 has the target with Gui).
set(QT_NO_PRIVATE_MODULE_WARNING ON)
if(NOT TARGET Qt6::GuiPrivate)
    find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(WPE REQUIRED IMPORTED_TARGET wpe-webkit-2.0 wpe-1.0 wpebackend-fdo-1.0)
pkg_check_modules(GL REQUIRED IMPORTED_TARGET egl glesv2)
# wl_shm buffer access for software-rendered frames (ViewBackend::displayShm).
pkg_check_modules(WAYLAND_SERVER REQUIRED IMPORTED_TARGET wayland-server)
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client wayland-egl)

qt_standard_project_setup(REQUIRES 6.8)
if(QT_KNOWN_POLICY_QTP0004)
    qt_policy(SET QTP0004 NEW)
endif()

qt_add_qml_module(pacificwebview
    URI Shipwright.Pacific.WebView
    VERSION 1.0
    PLUGIN_TARGET pacificwebview
    NO_PLUGIN_OPTIONAL
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Shipwright/Pacific/WebView"
    SOURCES
        src/bridges.cpp src/bridges.h
        src/directsurface.cpp src/directsurface.h
        src/imcontext.cpp src/imcontext.h
        src/pacificwebview.cpp src/pacificwebview.h
        src/profile.cpp src/profile.h
        src/requests.cpp src/requests.h
        src/viewbackend.cpp src/viewbackend.h
)

qt_add_resources(pacificwebview pacific_page_scripts
    PREFIX /pacific/webview
    FILES
        js/agent.js
        js/console.js
        js/ime-fallback.js
        js/page-info.js
        js/pickers.js
        js/scroll.js
        js/selection.js
)

target_link_libraries(pacificwebview PRIVATE
    Qt6::Core Qt6::Gui Qt6::GuiPrivate Qt6::Qml Qt6::Quick Qt6::Positioning
    PkgConfig::WPE PkgConfig::GL PkgConfig::WAYLAND_SERVER PkgConfig::WAYLAND_CLIENT ${CMAKE_DL_LIBS})
if(TARGET Qt6::Sensors)
    target_link_libraries(pacificwebview PRIVATE Qt6::Sensors)
    target_compile_definitions(pacificwebview PRIVATE PACIFIC_HAVE_SENSORS)
else()
    message(STATUS "Qt Sensors not found: DeviceOrientation/DeviceMotion are off")
endif()
target_include_directories(pacificwebview PRIVATE src)
target_compile_definitions(pacificwebview PRIVATE QT_NO_KEYWORDS QT_NO_CAST_FROM_ASCII)
set_target_properties(pacificwebview PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON
    INSTALL_RPATH "${PACIFIC_ENGINE_LIBDIR};${PACIFIC_ENGINE_LIBDIR}/compat")

include(GNUInstallDirs)
# The WebProcess extension (src/webprocess): reports content-blocked requests.
set(PACIFIC_WEB_EXTENSIONS_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/shipwright-pacific-webview/web-process-extensions")
add_library(pacificwebprocess MODULE src/webprocess/extension.c)
target_link_libraries(pacificwebprocess PRIVATE PkgConfig::WPE)
set_target_properties(pacificwebprocess PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/web-process-extensions"
    C_VISIBILITY_PRESET hidden
    INSTALL_RPATH "${PACIFIC_ENGINE_LIBDIR};${PACIFIC_ENGINE_LIBDIR}/compat")
install(TARGETS pacificwebprocess LIBRARY DESTINATION "${PACIFIC_WEB_EXTENSIONS_INSTALL_DIR}")
if(IS_ABSOLUTE "${PACIFIC_WEB_EXTENSIONS_INSTALL_DIR}")
    set(_ext_dir "${PACIFIC_WEB_EXTENSIONS_INSTALL_DIR}")
else()
    set(_ext_dir "${CMAKE_INSTALL_PREFIX}/${PACIFIC_WEB_EXTENSIONS_INSTALL_DIR}")
endif()
target_compile_definitions(pacificwebview PRIVATE PACIFIC_WEB_EXTENSIONS_DIR="${_ext_dir}")
if(NOT DEFINED PACIFIC_QML_INSTALL_DIR)
    set(PACIFIC_QML_INSTALL_DIR "${CMAKE_INSTALL_LIBDIR}/qt6/qml")
endif()
set(_dest "${PACIFIC_QML_INSTALL_DIR}/Shipwright/Pacific/WebView")
install(TARGETS pacificwebview LIBRARY DESTINATION "${_dest}")
install(FILES
    "${CMAKE_BINARY_DIR}/qml/Shipwright/Pacific/WebView/qmldir"
    "${CMAKE_BINARY_DIR}/qml/Shipwright/Pacific/WebView/pacificwebview.qmltypes"
    DESTINATION "${_dest}")

if(PACIFIC_WEBVIEW_EXAMPLES)
    add_subdirectory(examples/minibrowser)
endif()
