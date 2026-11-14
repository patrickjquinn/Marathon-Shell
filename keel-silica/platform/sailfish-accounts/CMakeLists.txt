# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Sailfish.Accounts 1.0: sailfish-components-accounts (BSD-3-Clause, see
# ../PROVENANCE.md) built for Qt 6 on Keel's accounts-qt6, with what it
# needs compiled in (no C++ library is installed):
#   ../signon         libsignon-qt (LGPL-2.1, accounts-sso signond, with
#                     Sailfish's client patches): sign-in through signond
#   ../buteosyncfw    libbuteosyncfw's profile and client parts (LGPL-2.1):
#                     the sync profiles AccountSyncManager edits for msyncd
# Built where accounts-qt6 is (libaccounts-glib found).

if(NOT TARGET accounts-qt6)
    message(STATUS "Sailfish.Accounts: accounts-qt6 is not built (libaccounts-glib missing), skipped")
    return()
endif()
find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Xml Sql Network)
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_KEYPROVIDER QUIET IMPORTED_TARGET libsailfishkeyprovider)
    pkg_check_modules(KEEL_ACCESSCONTROL QUIET IMPORTED_TARGET sailfishaccesscontrol)
endif()
option(KEEL_REQUIRE_SAILFISH_ACCOUNTS_DEPS
       "Fail if libsailfishkeyprovider or sailfishaccesscontrol is missing (device builds)" OFF)
if(KEEL_REQUIRE_SAILFISH_ACCOUNTS_DEPS AND NOT (KEEL_KEYPROVIDER_FOUND AND KEEL_ACCESSCONTROL_FOUND))
    message(FATAL_ERROR "libsailfishkeyprovider and sailfishaccesscontrol are required (pkg-config)")
endif()

# libsignon-qt, as upstream's lib/SignOn/libsignon-qt.pri with Sailfish's
# enable-p2p (signon-qt5.spec): never falls back to the session bus.
set(_signon_dir "${CMAKE_CURRENT_SOURCE_DIR}/../signon")
file(GLOB _signon_src CONFIGURE_DEPENDS "${_signon_dir}/SignOn/*.cpp" "${_signon_dir}/SignOn/*.h")
add_library(keelsignon STATIC ${_signon_src})
set_target_properties(keelsignon PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON AUTOMOC ON)
target_compile_definitions(keelsignon PRIVATE QT_NO_CAST_TO_ASCII QT_NO_CAST_FROM_ASCII
    DEBUG_ENABLED ENABLE_P2P SIGNON_LIBRARY_BUILD)
target_include_directories(keelsignon PUBLIC "${_signon_dir}" PRIVATE "${_signon_dir}/SignOn")
target_link_libraries(keelsignon PUBLIC Qt6::Core Qt6::DBus)
target_compile_options(keelsignon PRIVATE -Wno-deprecated-declarations)

# libbuteosyncfw: profiles (ProfileManager, SyncProfile, SyncSchedule) and the
# msyncd client (SyncClientInterface).
set(_buteo_dir "${CMAKE_CURRENT_SOURCE_DIR}/../buteosyncfw")
file(GLOB _buteo_src CONFIGURE_DEPENDS "${_buteo_dir}/profile/*.cpp" "${_buteo_dir}/profile/*.h"
     "${_buteo_dir}/clientfw/*.cpp" "${_buteo_dir}/clientfw/*.h" "${_buteo_dir}/common/*.cpp" "${_buteo_dir}/common/*.h")
add_library(keelbuteosyncfw STATIC ${_buteo_src})
set_target_properties(keelbuteosyncfw PROPERTIES POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON AUTOMOC ON)
# sailfish-components-accounts includes <buteosyncfw5/SyncClientInterface.h>.
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/include/buteosyncfw5/SyncClientInterface.h"
     "#include \"${_buteo_dir}/clientfw/SyncClientInterface.h\"\n")
target_include_directories(keelbuteosyncfw PUBLIC "${_buteo_dir}/profile" "${_buteo_dir}/clientfw"
    "${_buteo_dir}/common" "${CMAKE_CURRENT_BINARY_DIR}/include")
target_link_libraries(keelbuteosyncfw PUBLIC Qt6::Core Qt6::DBus Qt6::Xml Qt6::Sql Qt6::Network)
target_compile_options(keelbuteosyncfw PRIVATE -Wno-deprecated-declarations)

file(GLOB _accounts_lib_src CONFIGURE_DEPENDS lib/*.cpp lib/*.h)
add_library(sailfishaccountsplugin MODULE plugin/plugin.cpp ${_accounts_lib_src})
set(_sa_dir Sailfish/Accounts)
set_target_properties(sailfishaccountsplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/${_sa_dir}"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON AUTOMOC ON)
target_include_directories(sailfishaccountsplugin PRIVATE lib)
target_link_libraries(sailfishaccountsplugin PRIVATE keelsignon keelbuteosyncfw accounts-qt6
    Qt6::Core Qt6::DBus Qt6::Gui Qt6::Xml Qt6::Qml)
target_compile_options(sailfishaccountsplugin PRIVATE -Wno-deprecated-declarations)
if(KEEL_KEYPROVIDER_FOUND)
    target_compile_definitions(sailfishaccountsplugin PRIVATE USE_SAILFISHKEYPROVIDER)
    target_link_libraries(sailfishaccountsplugin PRIVATE PkgConfig::KEEL_KEYPROVIDER)
endif()
if(KEEL_ACCESSCONTROL_FOUND)
    target_link_libraries(sailfishaccountsplugin PRIVATE PkgConfig::KEEL_ACCESSCONTROL)
else()
    target_sources(sailfishaccountsplugin PRIVATE compat/sailfishaccesscontrol.cpp compat/sailfishaccesscontrol.h)
    target_include_directories(sailfishaccountsplugin PRIVATE compat)
endif()
set(_sa_files qmldir plugins.qmltypes AccountIcon.qml AccountProviderPicker.qml AccountProviderPickerDelegate.qml
    AccountsFlowView.qml AccountsListDelegate.qml AccountsListView.qml)
foreach(_f IN LISTS _sa_files)
    configure_file(plugin/${_f} "${KEEL_QML_OUTPUT_DIR}/${_sa_dir}/${_f}" COPYONLY)
    list(APPEND _sa_staged "${KEEL_QML_OUTPUT_DIR}/${_sa_dir}/${_f}")
endforeach()
install(TARGETS sailfishaccountsplugin LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/${_sa_dir}")
install(FILES ${_sa_staged} DESTINATION "${KEEL_QML_INSTALL_DIR}/${_sa_dir}")
