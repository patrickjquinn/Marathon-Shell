# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# QML tests run with the Qt6 qmltestrunner on the offscreen platform against
# the modules staged in ${KEEL_QML_OUTPUT_DIR}.

set(_keel_test_env
    "QT_QPA_PLATFORM=offscreen"
    "QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "QML2_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/runtime" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

# Component, navigation, Theme default and compatibility tests (no ambience
# overrides in the environment).
add_test(NAME keel_silica_qml
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/qml")
set_tests_properties(keel_silica_qml PROPERTIES
    ENVIRONMENT "${_keel_test_env}" TIMEOUT 300)

# Ambience plumbing: keel-shell style forwarded dconf keys plus a
# KEEL_THEME_ override, read by the Rust Ambience object.
add_test(NAME keel_silica_ambience_env
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/ambience")
set_tests_properties(keel_silica_ambience_env PROPERTIES
    ENVIRONMENT "${_keel_test_env};KEEL_AMBIENCE_KEYS=/desktop/jolla/theme/color/highlight:/desktop/jolla/theme/color_scheme:/desktop/sailfish/silica/theme_pixel_ratio;KEEL_AMBIENCE_COLOR_HIGHLIGHT=#0055aa;KEEL_AMBIENCE_COLOR_SCHEME=darkonlight;KEEL_SILICA_THEME_PIXEL_RATIO=2.0;KEEL_THEME_ERROR_COLOR=#ff00ff"
    TIMEOUT 120)

# Screen's cutouts and rounded corners (screen.h), from the values the
# Jolla Phone's dconf has, on a screen of its size.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/jollaphone-screen.json"
    "{\"screens\":[{\"name\":\"phone\",\"x\":0,\"y\":0,\"width\":1032,\"height\":2272,\"logicalDpi\":96,\"logicalBaseDpi\":96,\"dpr\":1}]}\n")
add_test(NAME keel_silica_screencutouts
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/screencutouts")
set_tests_properties(keel_silica_screencutouts PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen:configfile=${CMAKE_CURRENT_BINARY_DIR}/jollaphone-screen.json;QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR};QML2_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR};XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime;KEEL_SCREEN_CUTOUTS=[[310, 0, 414, 66]];KEEL_SCREEN_ROUNDED_CORNERS=[[35, 35, 35], [-35, 35, 35], [40, -40, 40], [-40, -40, 40]];KEEL_THEME_PIXEL_RATIO=1.5;KEEL_SCREEN_DIAGONAL=6.36"
    TIMEOUT 60)

# Look fidelity (Theme values, colours, ambience background, glass glow) on
# an Xperia 10 profile: a 1080x2520 offscreen screen of 6.0", pixelRatio 1.75.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/xperia10-screen.json"
    "{\"screens\":[{\"name\":\"phone\",\"x\":0,\"y\":0,\"width\":1080,\"height\":2520,\"logicalDpi\":96,\"logicalBaseDpi\":96,\"dpr\":1}]}\n")
add_test(NAME keel_silica_fidelity
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/fidelity")
set_tests_properties(keel_silica_fidelity PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen:configfile=${CMAKE_CURRENT_BINARY_DIR}/xperia10-screen.json;QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR};QML2_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR};XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime;KEEL_SCREEN_DIAGONAL=6.0;KEEL_THEME_PIXEL_RATIO=1.75"
    TIMEOUT 120)

# Rust unit tests of the ambience and palette logic (not with a prebuilt
# cross-compiled native part).
if(NOT KEEL_RUST_PREBUILT_DIR)
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)
    add_test(NAME keel_silica_native_cargo_test
        COMMAND ${CMAKE_COMMAND} -E env "QMAKE=${_keel_qmake}"
                "CARGO_TARGET_DIR=${CMAKE_BINARY_DIR}/silica/cargo" "CARGO_INCREMENTAL=0"
                "CARGO_PROFILE_DEV_DEBUG=0" "CARGO_PROFILE_TEST_DEBUG=0"
                ${KEEL_CARGO} test --manifest-path "${CMAKE_CURRENT_SOURCE_DIR}/../plugin/Cargo.toml" --locked
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../plugin")
    set_tests_properties(keel_silica_native_cargo_test PROPERTIES TIMEOUT 1800)
endif()

# keel-shell contract (keel/shell/PROTOCOL.md): cover window title, peer
# D-Bus (CoverStatus, Orientation, Active, Activate, AmbienceChanged,
# CloseRequested) against a fake keel-shell, plus graceful degradation.
qt_add_executable(tst_keel_shellcontract
    shell/tst_shellcontract.cpp shell/fakeshell.cpp shell/fakeshell.h)
target_compile_definitions(tst_keel_shellcontract PRIVATE
    KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
    KEEL_COMPATAPP_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml/compatapp")
target_link_libraries(tst_keel_shellcontract PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::DBus Qt6::Test)
add_dependencies(tst_keel_shellcontract silicaplugin keelplugin)
foreach(_mode shell nodbus noshell)
    add_test(NAME keel_silica_shellcontract_${_mode} COMMAND tst_keel_shellcontract)
    set_tests_properties(keel_silica_shellcontract_${_mode} PROPERTIES
        ENVIRONMENT "${_keel_test_env};KEEL_TEST_MODE=${_mode}" TIMEOUT 120)
endforeach()

# Sailfish.Share on a private session bus: ShareAction against a fake
# system share dialog (and its clipboard fallback), ShareProvider as a share
# target.
find_program(KEEL_SILICA_DBUS_RUN_SESSION dbus-run-session)
if(KEEL_SILICA_DBUS_RUN_SESSION)
    qt_add_executable(tst_keel_share share/tst_share.cpp)
    target_compile_definitions(tst_keel_share PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_keel_share PRIVATE Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml Qt6::Test)
    add_dependencies(tst_keel_share silicashareplugin silicaplugin)
    add_test(NAME keel_silica_share COMMAND ${KEEL_SILICA_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_keel_share>)
    set_tests_properties(keel_silica_share PROPERTIES ENVIRONMENT "${_keel_test_env};XDG_CACHE_HOME=${CMAKE_CURRENT_BINARY_DIR}/share-cache" TIMEOUT 120)
endif()

# Label's TruncationMode.Fade: on the offscreen (software) scene graph, and
# with OpenGL under Xvfb where xvfb-run is found (the opacity ramp shader).
add_test(NAME keel_silica_labelfade
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}" -input "${CMAKE_CURRENT_SOURCE_DIR}/labelfade")
set_tests_properties(keel_silica_labelfade PROPERTIES ENVIRONMENT "${_keel_test_env}" TIMEOUT 120)
find_program(KEEL_XVFB_RUN xvfb-run)
if(KEEL_XVFB_RUN)
    add_test(NAME keel_silica_labelfade_gl
        COMMAND ${KEEL_XVFB_RUN} -a ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
                -input "${CMAKE_CURRENT_SOURCE_DIR}/labelfade")
    set_tests_properties(keel_silica_labelfade_gl PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=xcb;QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR};XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime"
        TIMEOUT 120)
endif()

# Label text format: markup in a PlainText Label (or under a window's
# _defaultLabelFormat: Text.PlainText) loads no images, remote or local.
find_package(Qt6 REQUIRED COMPONENTS Network)
qt_add_executable(tst_keel_labelformat labelformat/tst_labelformat.cpp)
target_compile_definitions(tst_keel_labelformat PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_keel_labelformat PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml Qt6::Quick Qt6::Test)
add_dependencies(tst_keel_labelformat silicaplugin keelplugin)
add_test(NAME keel_silica_labelformat COMMAND tst_keel_labelformat)
set_tests_properties(keel_silica_labelformat PROPERTIES
    ENVIRONMENT "${_keel_test_env}" TIMEOUT 60)

# The theme image provider (colour scheme variants, substitutes, monochrome
# tint) and theme icons in a light ambience, on icons the test writes.
qt_add_executable(tst_keel_themeicons themeicons/tst_themeicons.cpp ../plugin/cpp/themeimageprovider.cpp
    ../plugin/cpp/keeldconf.cpp ../plugin/cpp/keeldconf.h)
keel_use_dconf(tst_keel_themeicons)
target_include_directories(tst_keel_themeicons PRIVATE ../plugin/cpp)
target_compile_definitions(tst_keel_themeicons PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_keel_themeicons PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
add_dependencies(tst_keel_themeicons silicaplugin keelplugin)
add_test(NAME keel_silica_themeicons COMMAND tst_keel_themeicons)
set_tests_properties(keel_silica_themeicons PROPERTIES ENVIRONMENT "${_keel_test_env}" TIMEOUT 60)

# Reference screenshots (keel/README.md, "Look (tier C)"): keel-silica-shot renders each
# scene offscreen with grabToImage(). The test renders every scene into the
# build tree and fails if a scene does not load; the committed PNGs are made
# with screenshots/render.sh.
qt_add_executable(keel-silica-shot screenshots/shot.cpp)
target_link_libraries(keel-silica-shot PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::Test)
add_dependencies(keel-silica-shot silicaplugin keelplugin)
file(GLOB _keel_scenes CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/screenshots/scenes/*.qml")
foreach(_scene IN LISTS _keel_scenes)
    get_filename_component(_name "${_scene}" NAME_WE)
    add_test(NAME keel_silica_screenshot_${_name}
        COMMAND keel-silica-shot "${_scene}" "${CMAKE_CURRENT_BINARY_DIR}/screenshot-${_name}.png")
    set_tests_properties(keel_silica_screenshot_${_name} PROPERTIES
        ENVIRONMENT "${_keel_test_env}" TIMEOUT 60 LABELS screenshots)
endforeach()
