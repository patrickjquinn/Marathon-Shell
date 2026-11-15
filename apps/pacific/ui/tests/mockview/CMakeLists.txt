# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: Apache-2.0
#
# A stand-in for Shipwright.Pacific.WebView (apps/pacific/webview) with
# the same QML API: pages are drawn from fixtures, not loaded. For the UI's
# tests, qmllint and screenshots on hosts without the WPE engine.
#
#   cmake -S apps/pacific/ui/tests/mockview -B <build> && cmake --build <build>
#   then import <build>/qml
cmake_minimum_required(VERSION 3.21)
project(pacific-mockview LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick)
qt_policy(SET QTP0001 NEW)

set_source_files_properties(WebEngine.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(pacificmockview
    URI Shipwright.Pacific.WebView
    VERSION 1.0
    PLUGIN_TARGET pacificmockview
    OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/qml/Shipwright/Pacific/WebView"
    SOURCES mockwebviewbase.h
    QML_FILES
        WebView.qml WebProfile.qml WebEngine.qml LoadRequest.qml PermissionRequest.qml
        NavigationRequest.qml NewWindowRequest.qml Download.qml ScriptDialog.qml
        FileChooserRequest.qml AuthenticationRequest.qml
)
target_link_libraries(pacificmockview PRIVATE Qt6::Quick)
