# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# libkeel-sailfishapp: the SailfishApp API for Qt6 apps on Keel.
#
# Installed names avoid the system (Qt5) libsailfishapp:
#   ${libdir}/libkeel-sailfishapp.so.1
#   ${includedir}/keel/sailfishapp/sailfishapp.h
#   ${libdir}/keel/pkgconfig/sailfishapp.pc  (drop-in: PKG_CONFIG_PATH first)
#   ${libdir}/pkgconfig/keel-sailfishapp.pc  (explicit name)

set(KEEL_SAILFISHAPP_SHARE_DIR "${CMAKE_INSTALL_FULL_DATADIR}" CACHE PATH
    "Parent of the per-app data directories that SailfishApp::pathTo() resolves into")

add_library(keel-sailfishapp SHARED src/sailfishapp.cpp include/sailfishapp.h
    src/keellauncher.cpp src/keellauncher_p.h include/keellauncher.h)
set_target_properties(keel-sailfishapp PROPERTIES
    VERSION 1.0.0 SOVERSION 1
    # Installed as Keel::SailfishApp, the name keel/README.md documents.
    EXPORT_NAME SailfishApp
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_compile_definitions(keel-sailfishapp PRIVATE
    KEEL_SAILFISHAPP_LIBRARY
    KEEL_SAILFISHAPP_SHARE_DIR="${KEEL_SAILFISHAPP_SHARE_DIR}"
    KEEL_QT5COMPAT_DIR="${CMAKE_INSTALL_FULL_LIBDIR}/keel/qt5compat")
target_include_directories(keel-sailfishapp PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/keel/sailfishapp>)
target_link_libraries(keel-sailfishapp PUBLIC Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick)
# Qt 5 source rewrite for the app's QML (keel/qt5compat/src/qt5source.h),
# linked in statically.
target_link_libraries(keel-sailfishapp PRIVATE $<BUILD_INTERFACE:keel-qt5compat-source>)
add_library(Keel::SailfishApp ALIAS keel-sailfishapp)

install(TARGETS keel-sailfishapp EXPORT KeelSailfishAppTargets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(FILES include/sailfishapp.h include/keellauncher.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/keel/sailfishapp)
install(EXPORT KeelSailfishAppTargets NAMESPACE Keel::
        FILE KeelSailfishAppConfig.cmake
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/KeelSailfishApp)

foreach(_pc_name sailfishapp keel-sailfishapp)
    set(KEEL_PC_NAME ${_pc_name})
    configure_file(sailfishapp.pc.in "${CMAKE_CURRENT_BINARY_DIR}/${_pc_name}.pc" @ONLY)
endforeach()
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/sailfishapp.pc" DESTINATION ${CMAKE_INSTALL_LIBDIR}/keel/pkgconfig)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/keel-sailfishapp.pc" DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)

# Keel's Qt Wayland shell integration for Lipstick (direct mode).
add_subdirectory(waylandshell)

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
