# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# booster-keel: mapplauncherd booster for Keel apps (ADR-0016). Built as part
# of keel/ when mapplauncherd's libapplauncherd is found (pkg-config
# applauncherd: the SDK's mapplauncherd-devel; on a host,
# tools/perf/build-mapplauncherd.sh), or on its own against an installed
# libkeel-sailfishapp (keel/rpm/shipwright-keel-booster.spec):
#   cmake -S keel/booster -B build -DCMAKE_INSTALL_PREFIX=/usr
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    cmake_minimum_required(VERSION 3.19)
    project(booster-keel VERSION 0.1.0 LANGUAGES CXX)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    include(GNUInstallDirs)
    find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Qml Quick)
    find_package(KeelSailfishApp REQUIRED)
endif()

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(APPLAUNCHERD QUIET IMPORTED_TARGET applauncherd)
endif()
if(NOT APPLAUNCHERD_FOUND)
    message(STATUS "booster-keel: libapplauncherd (pkg-config applauncherd) not found; not built")
    return()
endif()

add_executable(booster-keel booster-keel.cpp)
set_target_properties(booster-keel PROPERTIES AUTOMOC OFF)
target_compile_definitions(booster-keel PRIVATE
    BOOSTER_TYPE="keel"
    KEEL_BOOSTER_PRELOAD="${CMAKE_INSTALL_FULL_DATADIR}/booster-keel/preload.qml")
target_link_libraries(booster-keel PRIVATE PkgConfig::APPLAUNCHERD Keel::SailfishApp
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
# As mapplauncherd-booster-silica: resolve every relocation before the
# fork, so that they are not private dirty pages in each boosted app.
target_link_options(booster-keel PRIVATE "LINKER:-z,now")

# keel_booster_mode: the direct-mode test with the app launched through
# `invoker --type=keel` and this booster (keel/tests/direct/test_direct.py).
if(BUILD_TESTING AND TARGET harbour-keeldirect)
    find_package(Python3 COMPONENTS Interpreter)
    find_program(KEEL_INVOKER invoker HINTS "${APPLAUNCHERD_PREFIX}/bin")
    if(KEEL_INVOKER AND Python3_Interpreter_FOUND)
        add_test(NAME keel_booster_mode
            COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/../tests/direct/test_direct.py"
                --compositor "$<TARGET_FILE:keel-test-compositor>"
                --app "$<TARGET_FILE:harbour-keeldirect>" --test-app
                --booster "$<TARGET_FILE:booster-keel>" --invoker "${KEEL_INVOKER}"
                --qml-import "${KEEL_QML_OUTPUT_DIR}"
                --data-dir "${CMAKE_CURRENT_SOURCE_DIR}/../tests/direct/data"
                --qt-version "${Qt6_VERSION}" --qt-plugins "${KEEL_QT_PLUGINS_DIR}"
                --keel-plugins "${CMAKE_BINARY_DIR}/plugins")
        set_tests_properties(keel_booster_mode PROPERTIES TIMEOUT 180 SKIP_RETURN_CODE 77)
    endif()
endif()

install(TARGETS booster-keel RUNTIME DESTINATION "${CMAKE_INSTALL_LIBEXECDIR}/mapplauncherd")
install(FILES preload.qml DESTINATION "${CMAKE_INSTALL_DATADIR}/booster-keel")
# The sandbox profile of booster-keel@<app>.service (Sailjail).
install(FILES booster-keel.profile DESTINATION "${CMAKE_INSTALL_FULL_SYSCONFDIR}/sailjail/permissions")
install(FILES booster-keel.service booster-keel@.service
        DESTINATION "${CMAKE_INSTALL_PREFIX}/lib/systemd/user")
