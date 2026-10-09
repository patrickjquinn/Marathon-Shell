# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Sailfish.Policy 1.0 and libsailfishpolicy-qt6 (Keel's own, see
# ../PROVENANCE.md): the API of Sailfish's libsailfishpolicy (PolicyValue,
# AccessPolicy, AccessPolicyPlugin, PolicyTypes), reading the policies MDM
# applications set (/var/lib/policy/policy.conf) and the privacy switch.
# Read only and fail-closed (lib/accesspolicy.h). The library name carries
# -qt6 and the headers go under include/sailfishpolicy-qt6/, so that they
# install next to Sailfish's Qt 5 libsailfishpolicy.

set(KEEL_POLICY_VERSION 0.4.26)
set(KEEL_POLICY_INCLUDEDIR "${CMAKE_INSTALL_INCLUDEDIR}/sailfishpolicy-qt6")
set(_policy_headers lib/accesspolicy.h lib/accesspolicyplugin.h lib/policytypes.h lib/policyvalue.h)

add_library(sailfishpolicy-qt6 SHARED
    ${_policy_headers}
    lib/accesspolicy.cpp lib/policyvalue.cpp lib/policystore.cpp lib/policystore_p.h)
set_target_properties(sailfishpolicy-qt6 PROPERTIES
    VERSION ${KEEL_POLICY_VERSION} SOVERSION 0
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON
    AUTOMOC ON
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
# Sailfish's Qt 5 access policy plugin; while it is installed Keel reports
# every policy as unknown.
target_compile_definitions(sailfishpolicy-qt6 PRIVATE
    KEEL_POLICY_PLUGIN_PATH="${CMAKE_INSTALL_FULL_LIBDIR}/libsailfishpolicy/plugin/libsailfishpolicyplugin.so")
target_include_directories(sailfishpolicy-qt6 PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/lib>"
    "$<INSTALL_INTERFACE:${KEEL_POLICY_INCLUDEDIR}>")
target_link_libraries(sailfishpolicy-qt6 PUBLIC Qt6::Core PRIVATE Qt6::DBus)
install(TARGETS sailfishpolicy-qt6 LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
install(FILES ${_policy_headers} DESTINATION "${KEEL_POLICY_INCLUDEDIR}")
configure_file(sailfishpolicy-qt6.pc.in "${CMAKE_CURRENT_BINARY_DIR}/sailfishpolicy-qt6.pc" @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/sailfishpolicy-qt6.pc" DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")

qt_add_library(sailfishpolicyplugin MODULE plugin/plugin.cpp)
set_target_properties(sailfishpolicyplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Sailfish/Policy"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_link_libraries(sailfishpolicyplugin PRIVATE sailfishpolicy-qt6 Qt6::Core Qt6::Qml)
configure_file(plugin/qmldir "${KEEL_QML_OUTPUT_DIR}/Sailfish/Policy/qmldir" COPYONLY)
configure_file(plugin/plugins.qmltypes "${KEEL_QML_OUTPUT_DIR}/Sailfish/Policy/plugins.qmltypes" COPYONLY)
keel_platform_install(sailfishpolicyplugin Sailfish/Policy)
