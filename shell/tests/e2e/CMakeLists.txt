# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT

find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

set(proto ${CMAKE_CURRENT_SOURCE_DIR}/fake-lipstick/surface-extension.xml)
set(gen ${CMAKE_CURRENT_BINARY_DIR}/gen)
file(MAKE_DIRECTORY ${gen})
add_custom_command(
    OUTPUT ${gen}/surface-extension-server-protocol.h ${gen}/surface-extension-protocol.c
    COMMAND ${WAYLAND_SCANNER} server-header ${proto} ${gen}/surface-extension-server-protocol.h
    COMMAND ${WAYLAND_SCANNER} private-code ${proto} ${gen}/surface-extension-protocol.c
    DEPENDS ${proto})

add_executable(fake-lipstick fake-lipstick/main.cpp ${gen}/surface-extension-protocol.c
    ${gen}/surface-extension-server-protocol.h)
target_include_directories(fake-lipstick PRIVATE ${gen})
keel_link_qt5_compositor(fake-lipstick)

# The test client is a Qt6 app, built as a separate CMake project so Qt5 and
# Qt6 never share a target.
include(ExternalProject)
ExternalProject_Add(keel-test-client-build
    SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/client
    BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/client
    CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release
    INSTALL_COMMAND ""
    BUILD_ALWAYS ON)

add_executable(tst_e2e tst_e2e.cpp)
add_dependencies(tst_e2e fake-lipstick keel-test-client-build keel-shell)
target_link_libraries(tst_e2e PRIVATE Qt5::Test Qt5::Core)
target_compile_definitions(tst_e2e PRIVATE
    KEEL_SHELL_BIN="$<TARGET_FILE:keel-shell>"
    FAKE_LIPSTICK_BIN="$<TARGET_FILE:fake-lipstick>"
    TEST_CLIENT_BIN="${CMAKE_CURRENT_BINARY_DIR}/client/keel-test-client")
add_test(NAME e2e COMMAND tst_e2e)
set_tests_properties(e2e PROPERTIES TIMEOUT 240)
