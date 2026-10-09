# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel Actions (ADR-0018, docs/specs/pilot.md section 9):
#   plugin/   the `Keel.Actions 1.0` QML module: KeelAction, KeelParam,
#             KeelResult, KeelEntity, KeelContext, KeelShortcut, KeelCall,
#             the KeelActions singleton and the in-app runtime
#   schema/, codegen/, rust/, mcp/   Rust crates (root Cargo workspace)
# A module of its own (not part of `Keel 1.0`, which keel/silica owns).

qt_add_qml_module(keelactionsplugin
    URI Keel.Actions
    RESOURCE_PREFIX /
    VERSION 1.0
    PLUGIN_TARGET keelactionsplugin
    NO_GENERATE_PLUGIN_SOURCE
    CLASS_NAME KeelActionsPlugin
    OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/Keel/Actions"
    SOURCES
        plugin/plugin.cpp
        plugin/keeldeclarations.cpp plugin/keeldeclarations.h
        plugin/keelcall.cpp plugin/keelcall.h
        plugin/keelregistry.cpp plugin/keelregistry.h
        plugin/keelschema.cpp plugin/keelschema.h
        plugin/keeladaptor.cpp plugin/keeladaptor.h
        plugin/keelnative.cpp plugin/keelnative.h
)
target_include_directories(keelactionsplugin PRIVATE plugin)
target_link_libraries(keelactionsplugin PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::DBus ${CMAKE_DL_LIBS})
set_target_properties(keelactionsplugin PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON)

install(TARGETS keelactionsplugin LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/Keel/Actions")
install(FILES
    "${KEEL_QML_OUTPUT_DIR}/Keel/Actions/qmldir"
    "${KEEL_QML_OUTPUT_DIR}/Keel/Actions/keelactionsplugin.qmltypes"
    DESTINATION "${KEEL_QML_INSTALL_DIR}/Keel/Actions")

if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
