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

# QML suites that need Keel's Silica: set KEEL_QML to a Keel build's qml dir,
# or install keel-silica.
set(KEEL_QML "$ENV{KEEL_QML}" CACHE PATH "Keel build qml directory for the Silica QML tests")
find_path(_SILICA_QMLDIR Sailfish/Silica/qmldir PATHS ${KEEL_QML} /usr/lib/qt6/qml /usr/lib64/qt6/qml NO_DEFAULT_PATH)
if(_SILICA_QMLDIR)
    foreach(suite marathon-silica/tests tests/ui apps/notes/tests apps/clock/tests apps/calculator/tests apps/gallery/tests apps/music/tests apps/phone/tests apps/messages/tests apps/calendar/tests)
        string(REPLACE "/" "_" name "Qml_${suite}")
        add_test(NAME ${name} COMMAND sh ${CMAKE_SOURCE_DIR}/${suite}/run.sh)
        set_tests_properties(${name} PROPERTIES ENVIRONMENT "KEEL_QML=${_SILICA_QMLDIR}")
    endforeach()
endif()

# Every theme icon name used by Keel's Silica or our QML has a Marathon icon
add_test(NAME Lint_IconMap COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-icon-map.sh ${CMAKE_SOURCE_DIR} ${_SILICA_QMLDIR}/Sailfish/Silica)
