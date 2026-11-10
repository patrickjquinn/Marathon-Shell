# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# keel_direct_mode: a Keel app in direct mode against keel-test-compositor
# (wl_shell + qt_surface_extension, like Lipstick); see test_direct.py.
# Needs libwayland-dev (the compositor) and Qt 6's Wayland client plugin
# (qt6-wayland) at run time; without the plugin the test reports SKIP.

if(NOT TARGET keel-test-compositor)
    return()
endif()
find_package(Python3 COMPONENTS Interpreter)
if(NOT Python3_Interpreter_FOUND)
    message(STATUS "keel_direct_mode: no python3; test not registered")
    return()
endif()

# An app built the SDK-template way (main() is SailfishApp::main()), named
# after its QML file data/qml/harbour-keeldirect.qml.
add_executable(harbour-keeldirect ../../sailfishapp/tests/probe/main.cpp)
target_link_libraries(harbour-keeldirect PRIVATE Keel::SailfishApp)
# Boostable like a Sailfish app: a PIE that exports main (mapplauncherd
# dlopen()s it); see keel/booster and tools/perf.
set_target_properties(harbour-keeldirect PROPERTIES POSITION_INDEPENDENT_CODE ON ENABLE_EXPORTS ON)
target_link_options(harbour-keeldirect PRIVATE -pie)
add_dependencies(harbour-keeldirect keel-test-compositor silicaplugin keelplugin)
if(TARGET keel-wl-shell)
    add_dependencies(harbour-keeldirect keel-wl-shell)
endif()

add_test(NAME keel_direct_mode
    COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/test_direct.py"
        --compositor "$<TARGET_FILE:keel-test-compositor>"
        --app "$<TARGET_FILE:harbour-keeldirect>" --test-app
        --qml-import "${KEEL_QML_OUTPUT_DIR}"
        --data-dir "${CMAKE_CURRENT_SOURCE_DIR}/data"
        --qt-version "${Qt6_VERSION}" --qt-plugins "${KEEL_QT_PLUGINS_DIR}"
                --keel-plugins "${CMAKE_BINARY_DIR}/plugins")
set_tests_properties(keel_direct_mode PROPERTIES TIMEOUT 120 SKIP_RETURN_CODE 77)
