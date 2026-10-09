# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT

# An app built the SDK-template way: its main() is SailfishApp::main().
add_executable(harbour-keelprobe probe/main.cpp)
target_link_libraries(harbour-keelprobe PRIVATE Keel::SailfishApp)

qt_add_executable(tst_sailfishapp tst_sailfishapp.cpp)
target_link_libraries(tst_sailfishapp PRIVATE Keel::SailfishApp Qt6::Test)
target_compile_definitions(tst_sailfishapp PRIVATE
    KEEL_QML_DIR="${KEEL_QML_OUTPUT_DIR}"
    KEEL_TEST_DATA="${CMAKE_CURRENT_SOURCE_DIR}/data"
    KEEL_PROBE="$<TARGET_FILE:harbour-keelprobe>"
    KEEL_SHARE_DIR="${KEEL_SAILFISHAPP_SHARE_DIR}")
add_dependencies(tst_sailfishapp harbour-keelprobe)
if(TARGET silicaplugin)
    add_dependencies(tst_sailfishapp silicaplugin keelplugin)
else()
    # createView and mainRunsTheApp load a Silica ApplicationWindow.
    target_compile_definitions(tst_sailfishapp PRIVATE KEEL_TEST_NO_SILICA)
endif()

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/runtime")
file(CHMOD "${CMAKE_CURRENT_BINARY_DIR}/runtime" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
add_test(NAME keel_sailfishapp COMMAND tst_sailfishapp)
set_tests_properties(keel_sailfishapp PROPERTIES
    ENVIRONMENT "QT_QPA_PLATFORM=offscreen;XDG_RUNTIME_DIR=${CMAKE_CURRENT_BINARY_DIR}/runtime;QML_IMPORT_PATH=${KEEL_QML_OUTPUT_DIR}"
    TIMEOUT 60)

# The installed pkg-config file resolves to the installed library and header.
add_test(NAME keel_sailfishapp_pkgconfig
    COMMAND ${CMAKE_COMMAND}
        -DPC_FILE=${CMAKE_CURRENT_BINARY_DIR}/../sailfishapp.pc
        -DEXPECT_LIB=keel-sailfishapp
        -P ${CMAKE_CURRENT_SOURCE_DIR}/check_pc.cmake)
