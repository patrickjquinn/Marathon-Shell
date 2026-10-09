# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel's Qt6 subprojects: the Sailfish.Silica compatibility module (with the
# Keel extension module and its CXX-Qt native part), the Nemo QML plugin
# equivalents, the libsailfishapp shim and Sailfish platform modules
# (keel/platform) and Keel Actions (keel/actions). keel-shell (keel/shell) is a
# system-Qt5 project and is built separately; see keel/README.md.
#
#   cmake -S keel -B build/keel -G Ninja
#   cmake --build build/keel
#   ctest --test-dir build/keel --output-on-failure
cmake_minimum_required(VERSION 3.19)
project(keel VERSION 0.1.0 LANGUAGES CXX)

# Qt floor: the host has 6.4, Chum ships 6.8.4 for Sailfish 5.2. Keel uses
# only APIs present in both.
set(KEEL_QT_MIN_VERSION 6.4)

option(KEEL_BUILD_SILICA "Build Sailfish.Silica and Keel QML modules" ON)
option(KEEL_BUILD_NEMO_COMPAT "Build Nemo.DBus, Nemo.Notifications, Nemo.KeepAlive" ON)
option(KEEL_BUILD_SAILFISHAPP "Build the libsailfishapp shim" ON)
option(KEEL_BUILD_PLATFORM "Build Keel's Sailfish platform modules (keel/platform)" ON)
option(KEEL_BUILD_ACTIONS "Build Keel Actions (keel/actions: Keel.Actions 1.0, ADR-0018)" ON)
option(BUILD_TESTING "Build and register tests" ON)

set(CMAKE_CXX_STANDARD 17)
# GCC 16 warns (-Wsfinae-incomplete) inside Qt's own headers: qmetatype.h
# probes whether a type is complete on purpose, before moc's code defines it.
include(CheckCXXCompilerFlag)
check_cxx_compiler_flag(-Wsfinae-incomplete KEEL_HAVE_WSFINAE_INCOMPLETE)
if(KEEL_HAVE_WSFINAE_INCOMPLETE)
    add_compile_options(-Wno-sfinae-incomplete)
endif()
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

include(GNUInstallDirs)

find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Core Gui Qml Quick DBus)
# Qt 6.10+ ships the private modules as their own packages (Qt6GuiPrivate) and
# no longer defines Qt6::GuiPrivate through Qt6Gui; Qt 6.4 defines it there
# and has no such package, so the lookup is quiet and the target checks below
# work on both.
set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 ${KEEL_QT_MIN_VERSION} QUIET COMPONENTS GuiPrivate)
if(BUILD_TESTING)
    enable_testing()
    find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS QuickTest Test)
    # Tests that run under dbus-run-session pass this config, so the private
    # bus cannot activate the host's own services.
    set(KEEL_ISOLATED_BUS_CONFIG "${CMAKE_CURRENT_SOURCE_DIR}/tests/dbus/isolated-session.conf")
    # The Qt this build uses, for tests whose checks depend on it (not the
    # first qmake on PATH, which may be another Qt).
    if(IS_ABSOLUTE "${QT6_INSTALL_PLUGINS}")
        set(KEEL_QT_PLUGINS_DIR "${QT6_INSTALL_PLUGINS}")
    else()
        set(KEEL_QT_PLUGINS_DIR "${QT6_INSTALL_PREFIX}/${QT6_INSTALL_PLUGINS}")
    endif()
endif()

# QML modules are staged under ${KEEL_QML_OUTPUT_DIR} in the build tree (tests
# import from there) and installed into Qt6's QML import path.
set(KEEL_QML_OUTPUT_DIR "${CMAKE_BINARY_DIR}/qml")
if(NOT DEFINED KEEL_QML_INSTALL_DIR)
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)
    execute_process(COMMAND "${_keel_qmake}" -query QT_INSTALL_QML
                    OUTPUT_VARIABLE _keel_qt_qml OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(KEEL_QML_INSTALL_DIR "${_keel_qt_qml}" CACHE PATH "Qt6 QML import path to install into")
endif()

# qmltestrunner from the Qt6 we build against (not the qtchooser shim).
if(BUILD_TESTING)
    get_target_property(_keel_qmake Qt6::qmake IMPORTED_LOCATION)
    execute_process(COMMAND "${_keel_qmake}" -query QT_INSTALL_BINS
                    OUTPUT_VARIABLE _keel_qt_bins OUTPUT_STRIP_TRAILING_WHITESPACE)
    find_program(KEEL_QMLTESTRUNNER qmltestrunner PATHS "${_keel_qt_bins}" NO_DEFAULT_PATH)
    if(NOT KEEL_QMLTESTRUNNER)
        find_program(KEEL_QMLTESTRUNNER qmltestrunner)
    endif()
    find_program(KEEL_DBUS_DAEMON dbus-daemon)
endif()

if(KEEL_BUILD_SILICA)
    add_subdirectory(silica)
endif()
if(KEEL_BUILD_NEMO_COMPAT)
    add_subdirectory(nemo-compat)
endif()
if(KEEL_BUILD_SAILFISHAPP)
    add_subdirectory(sailfishapp)
endif()
add_subdirectory(qt5compat)
if(KEEL_BUILD_PLATFORM)
    add_subdirectory(platform)
endif()
if(KEEL_BUILD_ACTIONS)
    add_subdirectory(actions)
endif()
# Direct mode (ADR-0016): the headless Lipstick stand-in and its test, and
# booster-keel (mapplauncherd; built when libapplauncherd is found).
if(BUILD_TESTING)
    add_subdirectory(testcompositor)
endif()
if(BUILD_TESTING AND KEEL_BUILD_SILICA AND KEEL_BUILD_SAILFISHAPP)
    add_subdirectory(tests/direct)
endif()
# The committed .qmltypes of the modules that register their types at run
# time still describe what the plugins register (keel/tools/qmltypes.py).
if(BUILD_TESTING AND NOT CMAKE_CROSSCOMPILING)
    find_package(Python3 COMPONENTS Interpreter)
    if(Python3_Interpreter_FOUND)
        get_target_property(_keel_qmake6 Qt6::qmake IMPORTED_LOCATION)
        add_test(NAME keel_qmltypes
            COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tools/qmltypes.py"
                    --qml "${KEEL_QML_OUTPUT_DIR}" --qmake "${_keel_qmake6}" --check)
        set_tests_properties(keel_qmltypes PROPERTIES TIMEOUT 300)
    endif()
endif()
option(KEEL_BUILD_BOOSTER "Build booster-keel (needs mapplauncherd's libapplauncherd)" ON)
if(KEEL_BUILD_BOOSTER AND KEEL_BUILD_SAILFISHAPP AND KEEL_BUILD_SILICA)
    add_subdirectory(booster)
endif()
