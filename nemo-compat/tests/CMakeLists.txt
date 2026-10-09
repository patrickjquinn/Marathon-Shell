# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# nemo-compat tests: one private dbus-daemon per run (dbus-run-session),
# with fake Notifications, MCE, ngfd and echo services (fakeservices.*).
# Nemo.Configuration uses the host fallback store in runtime/dconf.json.

# Unit tests of Keel's host fallbacks, built only when the fallback is.
if(NOT KEEL_MLITE_FOUND)
    qt_add_executable(tst_dconfstore tst_dconfstore.cpp
        ../configuration/compat/keeldconfstore.cpp ../configuration/compat/keeldconfstore.h)
    target_include_directories(tst_dconfstore PRIVATE ../configuration/compat)
    target_link_libraries(tst_dconfstore PRIVATE Qt6::Core Qt6::Qml Qt6::Test)
    add_test(NAME keel_nemo_dconfstore COMMAND tst_dconfstore)
endif()
if(NOT KEEL_IPHB_FOUND)
    qt_add_executable(tst_iphbfallback tst_iphbfallback.cpp ../keepalive/compat/iphb_fallback.cpp)
    target_include_directories(tst_iphbfallback PRIVATE ../keepalive/compat)
    find_package(Threads REQUIRED)
    target_link_libraries(tst_iphbfallback PRIVATE Qt6::Core Qt6::Test Threads::Threads)
    add_test(NAME keel_nemo_iphbfallback COMMAND tst_iphbfallback)
endif()

# Nemo.DBus with no bus at all: calls fail through their error callback.
qt_add_executable(tst_nemodbus_nobus tst_nemodbus_nobus.cpp)
target_compile_definitions(tst_nemodbus_nobus PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_nemodbus_nobus PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Test)
add_dependencies(tst_nemodbus_nobus nemodbus)
add_test(NAME keel_nemo_dbus_nobus COMMAND tst_nemodbus_nobus)
set_tests_properties(keel_nemo_dbus_nobus PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/keel-no-bus;DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent/keel-no-bus"
    TIMEOUT 60)

find_program(KEEL_DBUS_RUN_SESSION dbus-run-session)
if(NOT KEEL_DBUS_RUN_SESSION)
    message(WARNING "dbus-run-session not found; nemo-compat tests are not registered")
    return()
endif()

qt_add_executable(tst_nemocompat tst_nemocompat.cpp fakeservices.cpp fakeservices.h)
target_compile_definitions(tst_nemocompat PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_nemocompat PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::DBus Qt6::Test)
add_dependencies(tst_nemocompat nemodbus nemonotifications keepaliveplugin nemoconfiguration nemongf nemopolicy)
if(TARGET keellipstick)
    add_dependencies(tst_nemocompat keellipstick)
endif()

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/runtime" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
add_test(NAME keel_nemo_compat
    COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_nemocompat>)
set_tests_properties(keel_nemo_compat PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime;KEEL_IPHB_FALLBACK_SCALE_MS=20;KEEL_DCONF_FILE=${CMAKE_CURRENT_BINARY_DIR}/runtime/dconf.json"
    TIMEOUT 120)

# org.nemomobile.lipstick's launcher types over a temporary applications
# directory (session bus for LauncherItem's sandboxing query).
if(TARGET keellipstick)
    qt_add_executable(tst_lipstick tst_lipstick.cpp)
    target_compile_definitions(tst_lipstick PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
    target_link_libraries(tst_lipstick PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Test)
    add_dependencies(tst_lipstick keellipstick)
    add_test(NAME keel_nemo_lipstick COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_lipstick>)
    set_tests_properties(keel_nemo_lipstick PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime"
        TIMEOUT 120)
endif()

# Nemo.Policy against a fake resource policy manager (the private daemon is
# the system bus here), and the engine's local grants without one.
qt_add_executable(tst_policy tst_policy.cpp)
target_compile_definitions(tst_policy PRIVATE KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}")
target_link_libraries(tst_policy PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::DBus Qt6::Test)
add_dependencies(tst_policy nemopolicy)
add_test(NAME keel_nemo_policy COMMAND ${KEEL_DBUS_RUN_SESSION} --config-file=${KEEL_ISOLATED_BUS_CONFIG} -- $<TARGET_FILE:tst_policy>)
set_tests_properties(keel_nemo_policy PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime"
    TIMEOUT 120)
