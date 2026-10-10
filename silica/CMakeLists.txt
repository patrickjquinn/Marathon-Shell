# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Two QML modules:
#   Sailfish.Silica 1.0  - the compatibility module (QML + thin C++ glue)
#   Keel 1.0             - Keel-only extensions: Ambience (Rust via CXX-Qt)
#                          and Shell (keel-shell client, QtDBus)
# Sailfish.Silica imports Keel; apps only ever need `import Sailfish.Silica 1.0`.

# ---------------------------------------------------------------------------
# Rust native part (keel/silica/plugin), built with Cargo and CXX-Qt.
# ---------------------------------------------------------------------------
# KEEL_RUST_PREBUILT_DIR: use a native part built beforehand (the Sailfish
# SDK's Rust is too old for CXX-Qt 0.10, so device builds cross-compile it
# with keel/rpm/build-native.sh and pass the result here). The directory
# holds libkeel_silica_native.a and CXX-Qt's export tree (cxxqt-export/).
set(KEEL_RUST_PREBUILT_DIR "" CACHE PATH "Prebuilt keel_silica_native (see keel/rpm/build-native.sh)")
set(_rust_dir "${CMAKE_CURRENT_SOURCE_DIR}/plugin")

if(KEEL_RUST_PREBUILT_DIR)
    set(KEEL_RUST_STATICLIB "${KEEL_RUST_PREBUILT_DIR}/libkeel_silica_native.a")
    set(_cxxqt_export "${KEEL_RUST_PREBUILT_DIR}/cxxqt-export")
    foreach(_f "${KEEL_RUST_STATICLIB}" "${_cxxqt_export}/crates/keel_silica_native/initializers.o")
        if(NOT EXISTS "${_f}")
            message(FATAL_ERROR "KEEL_RUST_PREBUILT_DIR: missing ${_f}")
        endif()
    endforeach()
    add_custom_target(keel_silica_native_cargo)
else()
    find_program(KEEL_CARGO cargo REQUIRED)
    option(KEEL_CARGO_OFFLINE "Pass --offline to cargo (vendored or pre-fetched crates)" OFF)
    set(KEEL_RUST_TARGET "" CACHE STRING "Rust target triple for cross builds (empty: host)")

    set(_cargo_target_dir "${CMAKE_CURRENT_BINARY_DIR}/cargo")
    set(_cxxqt_export "${CMAKE_CURRENT_BINARY_DIR}/cxxqt-export")
    if(CMAKE_BUILD_TYPE MATCHES "^(Release|RelWithDebInfo|MinSizeRel)$")
        set(_cargo_profile_flag --release)
        set(_cargo_profile_dir release)
    else()
        set(_cargo_profile_flag)
        set(_cargo_profile_dir debug)
    endif()
    set(_cargo_args build --manifest-path "${_rust_dir}/Cargo.toml" --locked ${_cargo_profile_flag})
    if(KEEL_CARGO_OFFLINE)
        list(APPEND _cargo_args --offline)
    endif()
    if(KEEL_RUST_TARGET)
        list(APPEND _cargo_args --target "${KEEL_RUST_TARGET}")
        set(_cargo_out "${_cargo_target_dir}/${KEEL_RUST_TARGET}/${_cargo_profile_dir}")
    else()
        set(_cargo_out "${_cargo_target_dir}/${_cargo_profile_dir}")
    endif()
    set(KEEL_RUST_STATICLIB "${_cargo_out}/libkeel_silica_native.a")
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)

    add_custom_target(keel_silica_native_cargo ALL
        COMMAND ${CMAKE_COMMAND} -E env
            "QMAKE=${_keel_qmake}"
            "CARGO_TARGET_DIR=${_cargo_target_dir}"
            "CARGO_INCREMENTAL=0"
            "CXX_QT_EXPORT_DIR=${_cxxqt_export}"
            "CXX_QT_EXPORT_CRATE_keel_silica_native=1"
            "${KEEL_CARGO}" ${_cargo_args}
        BYPRODUCTS "${KEEL_RUST_STATICLIB}" "${_cxxqt_export}/crates/keel_silica_native/initializers.o"
        WORKING_DIRECTORY "${_rust_dir}"
        COMMENT "Building keel_silica_native (Rust, CXX-Qt)"
        USES_TERMINAL
        VERBATIM)
endif()
set(KEEL_RUST_INITIALIZERS "${_cxxqt_export}/crates/keel_silica_native/initializers.o")
set(KEEL_RUST_INCLUDE "${_cxxqt_export}/crates/keel_silica_native/include")
file(MAKE_DIRECTORY "${KEEL_RUST_INCLUDE}")

find_package(Threads REQUIRED)

# dconf through libdconf (keeldconf.h): the phone's sandboxed apps have no
# `dconf` program (Sailjail's private-bin). Hosts without dconf's
# development files fall back to the program. KEEL_REQUIRE_LIBDCONF=ON (the
# RPM build) makes the library mandatory.
option(KEEL_REQUIRE_LIBDCONF "Fail the build without libdconf" OFF)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_DCONF IMPORTED_TARGET dconf)
endif()
if(KEEL_REQUIRE_LIBDCONF AND NOT KEEL_DCONF_FOUND)
    message(FATAL_ERROR "KEEL_REQUIRE_LIBDCONF: dconf (pkg-config) not found; install dconf-devel")
endif()
if(NOT KEEL_DCONF_FOUND)
    message(STATUS "keel/silica: libdconf not found, reading dconf through the dconf program")
endif()
function(keel_use_dconf target)
    if(KEEL_DCONF_FOUND)
        target_compile_definitions(${target} PRIVATE KEEL_HAVE_LIBDCONF)
        target_link_libraries(${target} PRIVATE PkgConfig::KEEL_DCONF)
    endif()
endfunction()

# ---------------------------------------------------------------------------
# Keel 1.0
# ---------------------------------------------------------------------------
qt_add_qml_module(keelplugin
    URI Keel
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET keelplugin
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME KeelPlugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Keel"
    SOURCES
        plugin/cpp/keelplugin.cpp
        plugin/cpp/glyphwarning.cpp
        plugin/cpp/shellclient.cpp plugin/cpp/shellclient.h
        plugin/cpp/dconfambience.cpp plugin/cpp/dconfambience.h
        plugin/cpp/keeldconf.cpp plugin/cpp/keeldconf.h
)
keel_use_dconf(keelplugin)
add_dependencies(keelplugin keel_silica_native_cargo)
# keelplugin.cpp registers the Keel types itself (qmlRegisterType), so the
# keelplugin.qmltypes qmltyperegistrar writes is empty: replace it with what
# the plugin registers (plugin/keel.qmltypes, keel/tools/qmltypes.py).
add_custom_command(TARGET keelplugin POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_CURRENT_SOURCE_DIR}/plugin/keel.qmltypes"
            "${KEEL_QML_OUTPUT_DIR}/Keel/keelplugin.qmltypes"
    VERBATIM)
# Direct mode tags the cover window through Qt's platform native interface
# (qpa/qplatformnativeinterface.h, a private header: qt6-base-private-dev,
# Chum's qt6-qtbase-private-devel). Without it the cover is an ordinary
# window on Lipstick.
find_package(Qt6 ${KEEL_QT_MIN_VERSION} QUIET COMPONENTS GuiPrivate)
if(TARGET Qt6::GuiPrivate)
    target_link_libraries(keelplugin PRIVATE Qt6::GuiPrivate)
    target_compile_definitions(keelplugin PRIVATE KEEL_HAVE_QPA)
else()
    message(WARNING "Qt6 GUI private headers not found: direct mode cannot tag covers CATEGORY=cover")
endif()
target_include_directories(keelplugin PRIVATE "${KEEL_RUST_INCLUDE}" plugin/cpp)
target_link_libraries(keelplugin PRIVATE
    "${KEEL_RUST_INITIALIZERS}"
    "${KEEL_RUST_STATICLIB}"
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::DBus
    Threads::Threads ${CMAKE_DL_LIBS} m)
# Keep the Rust runtime's symbols private to the plugin, so that an app that
# links its own Rust code does not clash with ours.
target_link_options(keelplugin PRIVATE "LINKER:--exclude-libs,libkeel_silica_native.a")

# ---------------------------------------------------------------------------
# Sailfish.Silica 1.0
# ---------------------------------------------------------------------------
file(GLOB _silica_public_qml CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/*.qml)
file(GLOB _silica_public_js CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/*.js)
file(GLOB _silica_private_qml CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/private/*.qml)
file(GLOB _silica_private_js CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/private/*.js)

# Qt 6.10+ overrides. Silica's API has members that shadow Qt Quick's
# (`palette` on every Silica item, OpacityRampEffect's `enabled`). Qt 6.10
# and later warn about each one ("overrides a member of the base object")
# unless it is declared `override`, a keyword older Qt (the phone's 6.8)
# cannot parse. Such declarations are written `/*override*/ property ...`;
# with Qt 6.10+ the file is copied to the build directory with the comment
# replaced by the keyword, and the copy is compiled in its place.
# keel_qml_overrides(<list variable>): rewrites the list in place.
function(keel_qml_overrides _var)
    if(Qt6_VERSION VERSION_LESS 6.10)
        return()
    endif()
    set(_out "")
    foreach(_f IN LISTS ${_var})
        set(_src "${CMAKE_CURRENT_SOURCE_DIR}/${_f}")
        file(READ "${_src}" _text)
        string(FIND "${_text}" "/*override*/" _at)
        if(_at EQUAL -1)
            list(APPEND _out "${_f}")
            continue()
        endif()
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${_src}")
        string(REPLACE "/*override*/" "override" _text "${_text}")
        set(_dst "${CMAKE_CURRENT_BINARY_DIR}/qt610-overrides/${_f}")
        # Written only when it changed, so a reconfigure rebuilds nothing.
        set(_old "")
        if(EXISTS "${_dst}")
            file(READ "${_dst}" _old)
        endif()
        if(NOT _old STREQUAL _text)
            file(WRITE "${_dst}" "${_text}")
        endif()
        list(APPEND _out "${_dst}")
    endforeach()
    set(${_var} "${_out}" PARENT_SCOPE)
endfunction()
keel_qml_overrides(_silica_public_qml)
keel_qml_overrides(_silica_private_qml)

set_source_files_properties(qml/Remorse.qml qml/Notices.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)
# Files live in qml/ and qml/private/ but are served from their module's root.
foreach(_f IN LISTS _silica_public_qml _silica_public_js _silica_private_qml _silica_private_js)
    get_filename_component(_name "${_f}" NAME)
    set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS "${_name}")
endforeach()

# ---------------------------------------------------------------------------
# Sailfish.Silica.private 1.0: the native (C++) types Silica's BSD QML uses,
# Keel's QML stand-ins for the remaining ones, and Silica's BSD private QML
# (qml/private). Served from qrc:/qt/qml/Sailfish/Silica/private/, which is
# also what `import "private"` in Silica's QML resolves to.
# ---------------------------------------------------------------------------
# Keel.SilicaCore 1.0: Sailfish.Silica's Theme singleton (C++), which
# Sailfish.Silica re-exports (IMPORTS). A module of its own so that it is
# built before Sailfish.Silica.private, whose QML reads it: with its type
# known, qmlcachegen compiles that QML's Theme bindings to C++.
# ---------------------------------------------------------------------------
qt_add_qml_module(silicacoreplugin
    URI Keel.SilicaCore
    VERSION 1.0
    PLUGIN_TARGET silicacoreplugin
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME KeelSilicaCorePlugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Keel/SilicaCore"
    RESOURCE_PREFIX /qt/qml
    # QtQuick (and Qt6::Quick below): the colour value type (QColor) of
    # Theme's properties and methods, for qmlcachegen.
    DEPENDENCIES Keel QtQuick
    SOURCES
        plugin/cpp/coreplugin.cpp
        plugin/cpp/theme.cpp plugin/cpp/theme.h
)
target_include_directories(silicacoreplugin PRIVATE plugin/cpp)
target_link_libraries(silicacoreplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
add_dependencies(silicacoreplugin keelplugin)

# ---------------------------------------------------------------------------
# JavaScript libraries are imported by path (`import "private/Util.js"`), not
# as module members: `Util` in this module is the C++ singleton.
set_source_files_properties(${_silica_private_js} ${_silica_public_js} PROPERTIES QT_QML_SKIP_QMLDIR_ENTRY TRUE)
qt_add_qml_module(silicaprivateplugin
    URI Sailfish.Silica.private
    VERSION 1.0
    PLUGIN_TARGET silicaprivateplugin
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME SailfishSilicaPrivatePlugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Silica/private"
    RESOURCE_PREFIX /qt/qml
    DEPENDENCIES Keel Keel.SilicaCore QtQuick
    QML_FILES ${_silica_private_qml} ${_silica_private_js}
    SOURCES
        plugin/cpp/private/privateplugin.cpp
        plugin/cpp/private/palette.cpp plugin/cpp/private/palette.h
        plugin/cpp/private/silicatext.cpp plugin/cpp/private/silicatext.h
        plugin/cpp/private/silicaitems.cpp plugin/cpp/private/silicaitems.h
        plugin/cpp/private/keeltheme.h
        plugin/cpp/private/dragfilter.cpp plugin/cpp/private/dragfilter.h
        plugin/cpp/private/inversemousearea.cpp plugin/cpp/private/inversemousearea.h
        plugin/cpp/private/glassitem.cpp plugin/cpp/private/glassitem.h
        plugin/cpp/private/pulleymenulogic.cpp plugin/cpp/private/pulleymenulogic.h
        plugin/cpp/private/textsupport.cpp plugin/cpp/private/textsupport.h
        plugin/cpp/private/misc.cpp plugin/cpp/private/misc.h
        plugin/cpp/private/animatedloader.cpp plugin/cpp/private/animatedloader.h
        plugin/cpp/private/pagestackgesture.cpp plugin/cpp/private/pagestackgesture.h
        plugin/cpp/private/pagedview.cpp plugin/cpp/private/pagedview.h
)
target_include_directories(silicaprivateplugin PRIVATE plugin/cpp plugin/cpp/private)
# Qt Quick's private API: SilicaText derives from QQuickText (Text),
# SilicaMouseArea and SilicaRectangle from QQuickMouseArea and QQuickRectangle.
find_package(Qt6 QUIET COMPONENTS QuickPrivate)
target_link_libraries(silicaprivateplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::QuickPrivate)
add_dependencies(silicaprivateplugin keelplugin silicacoreplugin)

# Compiled Qt 6 shaders for the ShaderEffects of Silica's BSD QML (sources
# and build-shaders.sh in qml/shaders/), served from
# qrc:/qt/qml/Sailfish/Silica/shaders/.
# Keel's default ambiences (wallpapers drawn behind the window when no
# compositor does) and the glass dither, served from
# qrc:/qt/qml/Sailfish/Silica/ambience/ (ambience/make-ambience.py).
set(_silica_ambience ambience/harbour-dark.jpg ambience/harbour-light.jpg ambience/glass-dither.png)
foreach(_f ${_silica_ambience})
    get_filename_component(_name "${_f}" NAME)
    set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS "ambience/${_name}")
endforeach()
file(GLOB _silica_shaders CONFIGURE_DEPENDS RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" qml/shaders/*.qsb)
foreach(_f IN LISTS _silica_shaders)
    get_filename_component(_name "${_f}" NAME)
    set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS "shaders/${_name}")
endforeach()
qt_add_qml_module(silicaplugin
    URI Sailfish.Silica
    VERSION 1.0
    PLUGIN_TARGET silicaplugin
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME SailfishSilicaPlugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Silica"
    RESOURCE_PREFIX /qt/qml
    DEPENDENCIES Keel Keel.SilicaCore Sailfish.Silica.private QtQuick
    IMPORTS Keel.SilicaCore
    QML_FILES ${_silica_public_qml} ${_silica_public_js}
    RESOURCES ${_silica_shaders} ${_silica_ambience}
    SOURCES
        plugin/cpp/silicaplugin.cpp
        plugin/cpp/clipboard.cpp plugin/cpp/clipboard.h
        plugin/cpp/screen.cpp plugin/cpp/screen.h
        plugin/cpp/keeldconf.cpp plugin/cpp/keeldconf.h
        plugin/cpp/standardpaths.h
        plugin/cpp/buttonlayout.cpp plugin/cpp/buttonlayout.h
        plugin/cpp/enterkey.cpp plugin/cpp/enterkey.h
        plugin/cpp/themeimageprovider.cpp plugin/cpp/themeimageprovider.h
        plugin/cpp/ambienceimageprovider.cpp plugin/cpp/ambienceimageprovider.h
        plugin/cpp/format.cpp plugin/cpp/format.h
        plugin/cpp/urlresolver.cpp plugin/cpp/urlresolver.h
        plugin/cpp/windowdefaults.h
        plugin/cpp/private/translator.cpp plugin/cpp/private/translator.h
)
target_include_directories(silicaplugin PRIVATE plugin/cpp plugin/cpp/private)
target_link_libraries(silicaplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
keel_use_dconf(silicaplugin)
add_dependencies(silicaplugin keelplugin silicacoreplugin silicaprivateplugin silicabackgroundplugin)

# ---------------------------------------------------------------------------
# Keel.SilicaScreen 1.0: Silica's Screen singleton (a superset of Qt Quick's
# attached Screen) alone, for keel/qt5compat's Qt Quick 2.x shims to
# re-export after Qt Quick, so that `Screen` is Silica's (see screen.h).
# ---------------------------------------------------------------------------
qt_add_qml_module(silicascreenplugin
    URI Keel.SilicaScreen
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET silicascreenplugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Keel/SilicaScreen"
    SOURCES plugin/cpp/screen.cpp plugin/cpp/screen.h plugin/cpp/keeldconf.cpp plugin/cpp/keeldconf.h
)
keel_use_dconf(silicascreenplugin)
target_include_directories(silicascreenplugin PRIVATE plugin/cpp)
target_link_libraries(silicascreenplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml)

# ---------------------------------------------------------------------------
# Sailfish.Silica.Background 1.0: Keel's stand-ins for the two names of
# Silica's (proprietary) Background module that its BSD QML uses.
# ---------------------------------------------------------------------------
set(_silica_background_qml background/ColorBackground.qml background/Corners.qml)
keel_qml_overrides(_silica_background_qml)
foreach(_f IN LISTS _silica_background_qml)
    get_filename_component(_name "${_f}" NAME)
    set_source_files_properties(${_f} PROPERTIES QT_RESOURCE_ALIAS "${_name}")
endforeach()
qt_add_qml_module(silicabackgroundplugin
    URI Sailfish.Silica.Background
    VERSION 1.0
    PLUGIN_TARGET silicabackgroundplugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Silica/Background"
    RESOURCE_PREFIX /qt/qml
    DEPENDENCIES QtQuick
    QML_FILES ${_silica_background_qml}
)

# ---------------------------------------------------------------------------
# Sailfish.Share 1.0: ShareAction opens the system share dialog
# (org.sailfishos.share) or falls back to the clipboard; ShareProvider and
# ShareResource make the app a share target (share/keelshare.*).
# ---------------------------------------------------------------------------
set_source_files_properties(share/ShareAction.qml PROPERTIES QT_RESOURCE_ALIAS ShareAction.qml)
qt_add_qml_module(silicashareplugin
    URI Sailfish.Share
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET silicashareplugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Share"
    DEPENDENCIES Sailfish.Silica QtQuick
    QML_FILES share/ShareAction.qml
    SOURCES share/keelshare.cpp share/keelshare.h
)
target_include_directories(silicashareplugin PRIVATE share)
target_link_libraries(silicashareplugin PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
add_dependencies(silicashareplugin silicaplugin)

# ---------------------------------------------------------------------------
# Install into Qt6's QML import path.
# ---------------------------------------------------------------------------
foreach(_mod IN ITEMS "Keel:keelplugin" "Keel/SilicaScreen:silicascreenplugin" "Keel/SilicaCore:silicacoreplugin" "Sailfish/Silica:silicaplugin" "Sailfish/Silica/private:silicaprivateplugin" "Sailfish/Silica/Background:silicabackgroundplugin" "Sailfish/Share:silicashareplugin")
    string(REPLACE ":" ";" _parts "${_mod}")
    list(GET _parts 0 _dir)
    list(GET _parts 1 _tgt)
    install(TARGETS ${_tgt} LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_dir}")
    install(DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_dir}/"
            DESTINATION "${KEEL_QML_INSTALL_DIR}/${_dir}"
            FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes")
endforeach()

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
