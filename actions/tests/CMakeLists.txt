# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel.Actions tests: the QML types and the in-app runtime, with the Qt6
# qmltestrunner on the offscreen platform.

set(_keel_actions_test_env
    "QT_QPA_PLATFORM=offscreen"
    "QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "QML2_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    "KEEL_ACTIONS_APP_ID=org.example.notes"
    "KEEL_ACTIONS_FOREGROUND=1")

add_test(NAME keel_actions_qml
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/qml")
set_tests_properties(keel_actions_qml PROPERTIES
    ENVIRONMENT "${_keel_actions_test_env}" TIMEOUT 120)

# The runtime's describe() equals the generator's golden actions.json.
qt_add_executable(tst_keel_actions_describe_golden golden/tst_describe_golden.cpp)
target_compile_definitions(tst_keel_actions_describe_golden PRIVATE
    KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
    KEEL_ACTIONS_TEST_APP="${CMAKE_CURRENT_SOURCE_DIR}/app/NotesActions.qml"
    KEEL_ACTIONS_GOLDEN="${CMAKE_CURRENT_SOURCE_DIR}/../codegen/tests/golden/qml-notes/actions.json")
target_link_libraries(tst_keel_actions_describe_golden PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Test)
add_dependencies(tst_keel_actions_describe_golden keelactionsplugin)
add_test(NAME keel_actions_describe_golden COMMAND tst_keel_actions_describe_golden)
set_tests_properties(keel_actions_describe_golden PROPERTIES
    ENVIRONMENT "${_keel_actions_test_env}" TIMEOUT 60)

# The test stub the generator writes for the test app runs green against it
# (keel/actions/codegen/tests/golden/qml-notes/tst_keel_actions.qml).
add_test(NAME keel_actions_generated_stub
    COMMAND ${KEEL_QMLTESTRUNNER} -import "${KEEL_QML_OUTPUT_DIR}"
            -input "${CMAKE_CURRENT_SOURCE_DIR}/../codegen/tests/golden/qml-notes/tst_keel_actions.qml")
set_tests_properties(keel_actions_generated_stub PROPERTIES
    ENVIRONMENT "${_keel_actions_test_env}" TIMEOUT 120)

# D-Bus round trip on a private session bus: activation of the test host
# (headless), every method of org.shipwright.Keel.Actions, idle exit.
qt_add_executable(keel-actions-test-host dbus/keel-actions-test-host.cpp)
target_compile_definitions(keel-actions-test-host PRIVATE
    KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
    KEEL_ACTIONS_TEST_APP="${CMAKE_CURRENT_SOURCE_DIR}/app/NotesActions.qml")
target_link_libraries(keel-actions-test-host PRIVATE Qt6::Core Qt6::Gui Qt6::Qml)
add_dependencies(keel-actions-test-host keelactionsplugin)

if(KEEL_DBUS_DAEMON)
    find_program(KEEL_DBUS_RUN_SESSION dbus-run-session)
endif()
if(KEEL_DBUS_RUN_SESSION)
    set(KEEL_ACTIONS_SERVICE_DIR "${CMAKE_CURRENT_BINARY_DIR}/dbus-services")
    set(KEEL_ACTIONS_TEST_HOST "$<TARGET_FILE:keel-actions-test-host>")
    configure_file(dbus/session.conf.in "${CMAKE_CURRENT_BINARY_DIR}/dbus-session.conf" @ONLY)
    configure_file(dbus/org.example.notes.service.in "${CMAKE_CURRENT_BINARY_DIR}/org.example.notes.service.gen" @ONLY)
    file(GENERATE OUTPUT "${KEEL_ACTIONS_SERVICE_DIR}/org.example.notes.service"
         INPUT "${CMAKE_CURRENT_BINARY_DIR}/org.example.notes.service.gen")
    set(KEEL_ACTIONS_BUS_ENV
        "QT_QPA_PLATFORM=offscreen"
        "KEEL_ACTIONS_MANIFEST=${CMAKE_CURRENT_SOURCE_DIR}/../codegen/tests/golden/qml-notes/actions.json"
        "KEEL_ACTIONS_FOREGROUND=1"
        "KEEL_ACTIONS_IDLE_MS=1500")
    set(KEEL_ACTIONS_BUS_CONFIG "${CMAKE_CURRENT_BINARY_DIR}/dbus-session.conf")

    qt_add_executable(tst_keel_actions_dbus dbus/tst_dbus.cpp)
    target_link_libraries(tst_keel_actions_dbus PRIVATE Qt6::Core Qt6::DBus Qt6::Test)
    add_dependencies(tst_keel_actions_dbus keel-actions-test-host)
    add_test(NAME keel_actions_dbus
        COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ACTIONS_BUS_CONFIG}
                -- $<TARGET_FILE:tst_keel_actions_dbus>)
    set_tests_properties(keel_actions_dbus PROPERTIES ENVIRONMENT "${KEEL_ACTIONS_BUS_ENV}" TIMEOUT 120)

    # Rust actions through the same runtime: keel/actions/tests/native, a
    # cdylib built by Cargo whose build.rs runs the generator.
    find_program(KEEL_ACTIONS_CARGO cargo)
    if(KEEL_ACTIONS_CARGO)
        if(DEFINED ENV{CARGO_TARGET_DIR})
            set(_ka_target "$ENV{CARGO_TARGET_DIR}")
        else()
            set(_ka_target "${CMAKE_SOURCE_DIR}/../target")
        endif()
        set(KEEL_ACTIONS_TEST_NATIVE "${_ka_target}/debug/libkeel_actions_test_native.so")
        configure_file(dbus/org.example.rustnotes.service.in "${CMAKE_CURRENT_BINARY_DIR}/org.example.rustnotes.service.gen" @ONLY)
        file(GENERATE OUTPUT "${KEEL_ACTIONS_SERVICE_DIR}/org.example.rustnotes.service"
             INPUT "${CMAKE_CURRENT_BINARY_DIR}/org.example.rustnotes.service.gen")
        add_test(NAME keel_actions_native_build
            COMMAND ${CMAKE_COMMAND} -E env "CARGO_TARGET_DIR=${_ka_target}" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0
                    ${KEEL_ACTIONS_CARGO} build -p keel-actions-test-native
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/..")
        set_tests_properties(keel_actions_native_build PROPERTIES FIXTURES_SETUP keel_actions_native TIMEOUT 1800)
        qt_add_executable(tst_keel_actions_native dbus/tst_native.cpp)
        target_link_libraries(tst_keel_actions_native PRIVATE Qt6::Core Qt6::DBus Qt6::Test)
        add_dependencies(tst_keel_actions_native keel-actions-test-host)
        add_test(NAME keel_actions_dbus_native
            COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ACTIONS_BUS_CONFIG}
                    -- $<TARGET_FILE:tst_keel_actions_native>)
        set_tests_properties(keel_actions_dbus_native PROPERTIES
            ENVIRONMENT "${KEEL_ACTIONS_BUS_ENV}" FIXTURES_REQUIRED keel_actions_native TIMEOUT 120)

        # keel-mcp's conformance test against the real test app over the
        # private bus (activation included), not the stand-in backend.
        add_test(NAME keel_mcp_conformance
            COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ACTIONS_BUS_CONFIG}
                    -- ${KEEL_ACTIONS_CARGO} test -p keel-mcp --test conformance --test transports
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/..")
        set(_ka_mcp_env ${KEEL_ACTIONS_BUS_ENV})
        list(FILTER _ka_mcp_env EXCLUDE REGEX "^KEEL_ACTIONS_IDLE_MS=")
        set_tests_properties(keel_mcp_conformance PROPERTIES
            ENVIRONMENT "${_ka_mcp_env};KEEL_ACTIONS_IDLE_MS=20000;KEEL_MCP_BUS_TEST=1;CARGO_TARGET_DIR=${_ka_target};CARGO_INCREMENTAL=0;CARGO_PROFILE_DEV_DEBUG=0"
            DEPENDS keel-actions-test-host TIMEOUT 1800)
    endif()
endif()
