# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel.WebEngine 1.0 (Keel internal): ProfilePolicy applies Sailfish's
# cookieBehavior, doNotTrack and colorScheme WebEngineSettings to a Qt
# WebEngine profile through Qt WebEngine's C++ API. Built only where
# Qt6WebEngineQuick is found; Sailfish.WebView works without it (those
# settings then keep their values without effect).

find_package(Qt6 ${KEEL_QT_MIN_VERSION} QUIET COMPONENTS WebEngineQuick)
option(KEEL_REQUIRE_WEBENGINE "Fail if Qt6WebEngineQuick is missing" OFF)
if(NOT TARGET Qt6::WebEngineQuick)
    if(KEEL_REQUIRE_WEBENGINE)
        message(FATAL_ERROR "Qt6WebEngineQuick not found (qt6-qtwebengine-devel)")
    endif()
    message(STATUS "Keel.WebEngine: Qt WebEngine not found, ProfilePolicy is not built")
    return()
endif()
qt_add_qml_module(keelwebengineplugin
    URI Keel.WebEngine
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET keelwebengineplugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Keel/WebEngine"
    SOURCES profilepolicy.cpp profilepolicy.h
)
target_link_libraries(keelwebengineplugin PRIVATE Qt6::Core Qt6::Qml Qt6::WebEngineQuick)
keel_platform_install(keelwebengineplugin Keel/WebEngine)
