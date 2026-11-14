# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Nemo.Mce 1.0: libmce-qt (BSD-3-Clause, see ../PROVENANCE.md) built for
# Qt 6, the library compiled into the QML plugin (no C++ library is
# installed). The types follow MCE (com.nokia.mce on the system bus): display
# and touch-lock state, battery, charger, cable, power save, call state.
#
# MCE's D-Bus names come from mce-headers (pkg-config mce) on the device; a
# host without them uses the copy of the same headers in mce-dev/.

set(_mce_dir Nemo/Mce)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_PLATFORM_MCE QUIET IMPORTED_TARGET mce)
endif()
if(KEEL_REQUIRE_MCE_HEADERS AND NOT KEEL_PLATFORM_MCE_FOUND)
    message(FATAL_ERROR "mce-headers not found (pkg-config mce)")
endif()

# As upstream's lib.pro: qdbusxml2cpp -N -c QMceRequestProxy / QMceSignalProxy,
# included as request_interface.h and signal_interface.h.
set_source_files_properties(lib/dbus/com.nokia.mce.request.xml PROPERTIES CLASSNAME QMceRequestProxy NO_NAMESPACE ON)
set_source_files_properties(lib/dbus/com.nokia.mce.signal.xml PROPERTIES CLASSNAME QMceSignalProxy NO_NAMESPACE ON)
set(_mce_dbus)
qt_add_dbus_interface(_mce_dbus lib/dbus/com.nokia.mce.request.xml request_interface)
qt_add_dbus_interface(_mce_dbus lib/dbus/com.nokia.mce.signal.xml signal_interface)

file(GLOB _mce_sources CONFIGURE_DEPENDS lib/src/*.cpp lib/src/*.h lib/include/*.h)
add_library(qmcedeclarative MODULE plugin/qmcedeclarativeplugin.cpp ${_mce_sources} ${_mce_dbus})
set_target_properties(qmcedeclarative PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_mce_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_compile_definitions(qmcedeclarative PRIVATE QMCE_LIBRARY)
target_include_directories(qmcedeclarative PRIVATE lib/include lib/src "${CMAKE_CURRENT_BINARY_DIR}")
# Upstream's flags (lib.pro, plugin.pro).
target_compile_options(qmcedeclarative PRIVATE -Wno-unused-parameter -Wno-psabi)
target_link_libraries(qmcedeclarative PRIVATE Qt6::Core Qt6::DBus Qt6::Qml)
if(KEEL_PLATFORM_MCE_FOUND)
    target_link_libraries(qmcedeclarative PRIVATE PkgConfig::KEEL_PLATFORM_MCE)
else()
    target_include_directories(qmcedeclarative PRIVATE mce-dev)
endif()
foreach(_f qmldir plugins.qmltypes)
    configure_file(plugin/${_f} "${KEEL_QML_OUTPUT_DIR}/${_mce_dir}/${_f}" COPYONLY)
endforeach()
install(TARGETS qmcedeclarative LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_mce_dir}")
install(FILES "${KEEL_QML_OUTPUT_DIR}/${_mce_dir}/qmldir" "${KEEL_QML_OUTPUT_DIR}/${_mce_dir}/plugins.qmltypes"
        DESTINATION "${KEEL_QML_INSTALL_DIR}/${_mce_dir}")
