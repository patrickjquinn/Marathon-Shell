# Marathon Tests
# Logically grouped tests for the mono repo

cmake_minimum_required(VERSION 3.21)
enable_testing()

# Core library tests (registry, packager, permissions, installer, scanner, desktop parser)
add_subdirectory(core)

# Shell component tests (router, models)
add_subdirectory(shell)

# Keyboard component tests
add_subdirectory(keyboard)

# Every file importing Sailfish.Silica also imports Marathon.Silica after it
add_test(NAME Lint_SilicaImports COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-silica-imports.sh ${CMAKE_SOURCE_DIR})

# WebEngineView backgrounds must be opaque or fully transparent
add_test(NAME Lint_WebEngineBackground COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-webengine-background.sh ${CMAKE_SOURCE_DIR})

# Every in-tree app meets the manifest contract (docs/APP_MANIFEST_SCHEMA.md)
file(GLOB _app_manifests CONFIGURE_DEPENDS ${CMAKE_SOURCE_DIR}/apps/*/manifest.json)
list(TRANSFORM _app_manifests REPLACE "/manifest.json$" "")
add_test(NAME Lint_AppManifests COMMAND marathon-dev lint --system-app ${_app_manifests})
add_test(NAME Lint_DevInit COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-dev-init.sh $<TARGET_FILE:marathon-dev>)

# The modem's suspend hook (marathon-base-config) against stub mmcli/systemctl
add_test(NAME Script_ModemSleep COMMAND sh ${CMAKE_SOURCE_DIR}/tests/packaging/test-modem-sleep.sh ${CMAKE_SOURCE_DIR}/packaging/packages/marathon-base-config/marathon-modem-sleep)

# The splash's "Finishing update…" after an OS update (marathon-plymouth-theme)
add_test(NAME Script_UpdateSplash COMMAND sh ${CMAKE_SOURCE_DIR}/tests/packaging/test-update-splash.sh ${CMAKE_SOURCE_DIR}/packaging/packages/marathon-plymouth-theme/marathon-update-splash)

# QML suites that need Keel's Silica: set KEEL_QML to a Keel build's qml dir,
# or install keel-silica.
set(KEEL_QML "$ENV{KEEL_QML}" CACHE PATH "Keel build qml directory for the Silica QML tests")
find_path(_SILICA_QMLDIR Sailfish/Silica/qmldir PATHS ${KEEL_QML} /usr/lib/qt6/qml /usr/lib64/qt6/qml NO_DEFAULT_PATH)
if(_SILICA_QMLDIR)
    foreach(suite marathon-silica/tests tests/ui apps/notes/tests apps/clock/tests apps/calculator/tests apps/gallery/tests apps/music/tests apps/phone/tests apps/messages/tests apps/calendar/tests apps/email/tests apps/store/tests apps/camera/tests apps/browser/tests apps/settings/tests apps/template/tests apps/test/tests apps/maps/tests apps/terminal/tests)
        string(REPLACE "/" "_" name "Qml_${suite}")
        add_test(NAME ${name} COMMAND sh ${CMAKE_SOURCE_DIR}/${suite}/run.sh)
        set_tests_properties(${name} PROPERTIES ENVIRONMENT "KEEL_QML=${_SILICA_QMLDIR}")
    endforeach()
    if(TARGET test_keyboard_qml)
        add_test(NAME Keyboard_QML COMMAND test_keyboard_qml
            -import ${CMAKE_SOURCE_DIR}/tests/ui/stubs -import ${CMAKE_SOURCE_DIR}/marathon-silica
            -import ${_SILICA_QMLDIR} -input ${CMAKE_SOURCE_DIR}/tests/keyboard/qml)
        set_tests_properties(Keyboard_QML PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QT_FORCE_STDERR_LOGGING=1")
    endif()
    if(TARGET test_keyboard_textinput)
        add_test(NAME Keyboard_TextInput COMMAND test_keyboard_textinput)
        set_tests_properties(Keyboard_TextInput PROPERTIES ENVIRONMENT
            "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software;MARATHON_TEST_QML_IMPORTS=${CMAKE_SOURCE_DIR}/tests/ui/stubs:${CMAKE_SOURCE_DIR}/marathon-silica:${_SILICA_QMLDIR}")
    endif()
    if(TARGET test_shell_keelshow AND TARGET marathon-app-runner)
        add_test(NAME Shell_KeelShow COMMAND test_shell_keelshow)
        set_tests_properties(Shell_KeelShow PROPERTIES ENVIRONMENT
            "KEEL_QML=${_SILICA_QMLDIR};MARATHON_APP_RUNNER=$<TARGET_FILE:marathon-app-runner>")
    endif()
    if(TARGET marathon-shell)
        add_test(NAME Shell_Loads COMMAND sh ${CMAKE_SOURCE_DIR}/tests/shell/loads.sh $<TARGET_FILE:marathon-shell> "${_SILICA_QMLDIR}:${CMAKE_SOURCE_DIR}/marathon-silica")
    endif()
endif()

# Every theme icon name used by Keel's Silica or our QML has a Marathon icon
add_test(NAME Lint_IconMap COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-icon-map.sh ${CMAKE_SOURCE_DIR} ${_SILICA_QMLDIR}/Sailfish/Silica)

# Sailfish RPM installer (needs rpmbuild to build its fixture; skips without)
find_package(Python3 COMPONENTS Interpreter)
if(Python3_FOUND)
    add_test(NAME Sailfish_Install COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/sailfish-install/test_install.py)
    # Every test source is registered here, and every registered path exists
    add_test(NAME Lint_TestReachability COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/lint/check-test-reachability.py ${CMAKE_SOURCE_DIR})
    add_test(NAME Lint_TestReachabilityCheck COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tests/lint/test_check_test_reachability.py)
    add_test(NAME Flash_PinePhone COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/flash/test_flash_pinephone.py)
    # devices/ and socs/ manifests (needs the jsonschema module)
    add_test(NAME Devices_Check COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/devices/devices.py check)
    add_test(NAME Devices_Tests COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/tools/devices/test_devices.py)
endif()

# OTA feed publisher, and the image's sysupdate transfers run against its feed
if(Python3_FOUND)
    add_test(NAME Ota_Publish COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/ota/test_marathon_ota.py)
    add_test(NAME Ota_PiInitramfsHooks COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/ota/test_pi_hooks.py)
    add_test(NAME Ota_PiFactoryReset COMMAND ${Python3_EXECUTABLE} ${CMAKE_SOURCE_DIR}/scripts/ota/test_factory_reset.py)
endif()
