# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# keel-test-compositor: a headless Lipstick stand-in (wl_shell +
# qt_surface_extension, plain libwayland-server, no Qt) for the direct-mode
# test (keel/tests/direct) and the start-up and latency measurements
# (tools/perf). Built only when libwayland-server and wayland-scanner exist.

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_WAYLAND_SERVER QUIET IMPORTED_TARGET wayland-server)
endif()
find_program(KEEL_WAYLAND_SCANNER wayland-scanner)
if(NOT KEEL_WAYLAND_SERVER_FOUND OR NOT KEEL_WAYLAND_SCANNER)
    message(STATUS "keel-test-compositor: libwayland-server or wayland-scanner missing; "
                   "the direct-mode test is not built (apt install libwayland-dev)")
    return()
endif()

# The protocol Lipstick (QtCompositor 5.6) serves; BSD-3-Clause, copied
# unmodified from sailfishos/qtwayland (see keel/shell/PROVENANCE.md).
set(_proto "${CMAKE_CURRENT_SOURCE_DIR}/../shell/tests/e2e/fake-lipstick/surface-extension.xml")
set(_gen "${CMAKE_CURRENT_BINARY_DIR}/gen")
file(MAKE_DIRECTORY "${_gen}")
add_custom_command(
    OUTPUT "${_gen}/surface-extension-server-protocol.h" "${_gen}/surface-extension-protocol.c"
    COMMAND "${KEEL_WAYLAND_SCANNER}" server-header "${_proto}" "${_gen}/surface-extension-server-protocol.h"
    COMMAND "${KEEL_WAYLAND_SCANNER}" private-code "${_proto}" "${_gen}/surface-extension-protocol.c"
    DEPENDS "${_proto}")
enable_language(C)

add_executable(keel-test-compositor keel-test-compositor.cpp
    "${_gen}/surface-extension-protocol.c" "${_gen}/surface-extension-server-protocol.h")
set_target_properties(keel-test-compositor PROPERTIES AUTOMOC OFF)
target_include_directories(keel-test-compositor PRIVATE "${_gen}")
target_link_libraries(keel-test-compositor PRIVATE PkgConfig::KEEL_WAYLAND_SERVER)
set(KEEL_TEST_COMPOSITOR "$<TARGET_FILE:keel-test-compositor>" PARENT_SCOPE)
