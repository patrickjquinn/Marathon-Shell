# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Host build of keel-shell: Qt 5.15 QtWaylandCompositor backend (qt515),
# unit tests and the headless end-to-end test. The Sailfish (Qt 5.6.3,
# QtCompositor) build uses keel-shell.pro and rpm/shipwright-keel-shell.spec.

cmake_minimum_required(VERSION 3.16)
project(keel-shell VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

option(KEEL_SHELL_TESTS "Build unit tests" ON)
option(KEEL_SHELL_E2E "Build the headless end-to-end test (needs Qt6 + wayland-scanner)" ON)

find_package(Qt5 5.15 REQUIRED COMPONENTS Core Gui DBus WaylandCompositor)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_SERVER REQUIRED IMPORTED_TARGET wayland-server)

# Links the Qt 5 compositor with libwayland-server ahead of it. Qt 5.15's
# compositor library exports its own copy of the core protocol tables, where
# wl_shm is version 1; loaded first, it overrides libwayland's, and libwayland
# 1.23+ (wl_shm version 2) then refuses to create the wl_shm global, so no
# client gets shared-memory buffers (Fedora 44; libwayland 1.22 on Ubuntu
# 24.04 and Sailfish's are not affected). Kept in DT_NEEDED order regardless
# of --as-needed.
function(keel_link_qt5_compositor target)
    target_link_libraries(${target} PRIVATE
        "-Wl,--push-state,--no-as-needed" ${WAYLAND_SERVER_LINK_LIBRARIES} "-Wl,--pop-state"
        PkgConfig::WAYLAND_SERVER Qt5::WaylandCompositor)
endfunction()

include(GNUInstallDirs)
# keel/qt5compat's import directory, which keel-shell puts first on the app's
# QML_IMPORT_PATH. keel/CMakeLists.txt installs it to <libdir>/keel/qt5compat;
# keel-shell.pro takes the same from Qt's library directory (%{_libdir}).
set(KEEL_QT5COMPAT_LIBDIR "${CMAKE_INSTALL_FULL_LIBDIR}" CACHE PATH
    "Library directory that holds keel/qt5compat")

add_library(keelshell_core STATIC
    src/core/ambience.cpp
    src/core/backend.cpp
    src/core/containerstate.cpp
    src/core/coverpolicy.cpp
    src/core/graphics.cpp
    src/core/launchconfig.cpp
    src/core/lipstickwindow.cpp
    src/core/logging.cpp
    src/core/orientation.cpp
    src/core/runner.cpp
    src/core/shellservice.cpp
    src/core/shellstate.cpp
    src/core/unixsignals.cpp
    src/core/windowmapper.cpp
)
target_include_directories(keelshell_core PUBLIC src ${Qt5Gui_PRIVATE_INCLUDE_DIRS})
target_compile_definitions(keelshell_core PRIVATE
    KEEL_QT5COMPAT_DIR="${KEEL_QT5COMPAT_LIBDIR}/keel/qt5compat")
target_link_libraries(keelshell_core PUBLIC Qt5::Core Qt5::Gui Qt5::DBus)

add_executable(keel-shell
    src/main.cpp
    src/backend/qt515/backend515.cpp
)
target_compile_definitions(keel-shell PRIVATE KEEL_BACKEND_QT515
    KEEL_SHELL_VERSION="${PROJECT_VERSION}")
keel_link_qt5_compositor(keel-shell)
target_link_libraries(keel-shell PRIVATE keelshell_core)
install(TARGETS keel-shell RUNTIME DESTINATION bin)

if(KEEL_SHELL_TESTS)
    enable_testing()
    find_package(Qt5 5.15 REQUIRED COMPONENTS Test Network)
    foreach(t coverpolicy windowmapper ambience graphics launchconfig orientation shellservice shellstate)
        add_executable(tst_${t} tests/unit/tst_${t}.cpp)
        target_link_libraries(tst_${t} PRIVATE keelshell_core Qt5::Test)
        target_compile_definitions(tst_${t} PRIVATE
            KEEL_TEST_EXPECTED_LIBDIR="${KEEL_QT5COMPAT_LIBDIR}")
        add_test(NAME ${t} COMMAND tst_${t})
        set_tests_properties(${t} PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    endforeach()
    # QLocalSocket speaks raw D-Bus SASL to check that anonymous auth fails.
    target_link_libraries(tst_shellservice PRIVATE Qt5::Network)
endif()

if(KEEL_SHELL_TESTS AND KEEL_SHELL_E2E)
    add_subdirectory(tests/e2e)
endif()
