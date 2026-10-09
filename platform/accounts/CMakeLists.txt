# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Accounts for Keel apps (../PROVENANCE.md), built only where
# libaccounts-glib is found (Sailfish has it; on a host install
# libaccounts-glib-dev):
#   libaccounts-qt6.so.1        libaccounts-qt 1.17 (LGPL-2.1), unchanged,
#                               the Qt 6 build of the library Sailfish ships
#                               as libaccounts-qt5 1.17
#   org.nemomobile.accounts 1.0 nemo-qml-plugin-accounts (BSD), ported to Qt 6
# Both read and write the system accounts database through
# libaccounts-glib (SQLite plus D-Bus change notifications), so they see the
# accounts the Settings app manages. Sign-in (signond, Sailfish.Accounts) is
# not built: see PROVENANCE.md.

find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_ACCOUNTS_GLIB IMPORTED_TARGET libaccounts-glib)
endif()
option(KEEL_REQUIRE_ACCOUNTS "Fail if libaccounts-glib is missing (device builds)" OFF)
if(NOT KEEL_ACCOUNTS_GLIB_FOUND)
    if(KEEL_REQUIRE_ACCOUNTS)
        message(FATAL_ERROR "libaccounts-glib not found (pkg-config libaccounts-glib)")
    endif()
    message(STATUS "Accounts: libaccounts-glib not found, accounts-qt6 and org.nemomobile.accounts are not built")
    return()
endif()
find_package(Qt6 ${KEEL_QT_MIN_VERSION} REQUIRED COMPONENTS Xml)

set(KEEL_ACCOUNTS_INCLUDEDIR "${CMAKE_INSTALL_INCLUDEDIR}/accounts-qt6")
file(GLOB _accounts_src CONFIGURE_DEPENDS libaccounts-qt/Accounts/*.cpp libaccounts-qt/Accounts/*.h)
add_library(accounts-qt6 SHARED ${_accounts_src})
set_target_properties(accounts-qt6 PROPERTIES VERSION 1.5.0 SOVERSION 1
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
# As upstream's Accounts.pro.
target_compile_definitions(accounts-qt6 PRIVATE BUILDING_ACCOUNTS_QT
    QT_NO_CAST_TO_ASCII QT_NO_CAST_FROM_ASCII QT_NO_KEYWORDS)
target_compile_options(accounts-qt6 PRIVATE -fno-exceptions)
target_include_directories(accounts-qt6 PUBLIC
    "$<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/libaccounts-qt>"
    "$<INSTALL_INTERFACE:${KEEL_ACCOUNTS_INCLUDEDIR}>")
target_link_libraries(accounts-qt6 PUBLIC Qt6::Core Qt6::Xml PkgConfig::KEEL_ACCOUNTS_GLIB)
install(TARGETS accounts-qt6 LIBRARY DESTINATION "${CMAKE_INSTALL_LIBDIR}")
file(GLOB _accounts_headers libaccounts-qt/Accounts/*.h)
list(FILTER _accounts_headers EXCLUDE REGEX "(_p|utils)\\.h$")
install(FILES ${_accounts_headers}
        libaccounts-qt/Accounts/Account libaccounts-qt/Accounts/AccountService
        libaccounts-qt/Accounts/Application libaccounts-qt/Accounts/AuthData
        libaccounts-qt/Accounts/Error libaccounts-qt/Accounts/Manager
        libaccounts-qt/Accounts/Provider libaccounts-qt/Accounts/Service
        libaccounts-qt/Accounts/ServiceType
        DESTINATION "${KEEL_ACCOUNTS_INCLUDEDIR}/Accounts")
configure_file(accounts-qt6.pc.in "${CMAKE_CURRENT_BINARY_DIR}/accounts-qt6.pc" @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/accounts-qt6.pc" DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig")

# org.nemomobile.accounts 1.0
file(GLOB _nemo_accounts_src CONFIGURE_DEPENDS nemo/*.cpp nemo/*.h)
add_library(nemoaccounts MODULE ${_nemo_accounts_src})
set_target_properties(nemoaccounts PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${KEEL_QML_OUTPUT_DIR}/org/nemomobile/accounts"
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN ON)
target_compile_definitions(nemoaccounts PRIVATE QT_VERSION_5)
target_compile_options(nemoaccounts PRIVATE -Wno-deprecated-declarations)
target_include_directories(nemoaccounts PRIVATE nemo)
target_link_libraries(nemoaccounts PRIVATE accounts-qt6 Qt6::Core Qt6::Qml)
configure_file(nemoaccounts.qmldir "${KEEL_QML_OUTPUT_DIR}/org/nemomobile/accounts/qmldir" COPYONLY)
# The types the plugin registers at run time (keel/tools/qmltypes.py).
configure_file(nemoaccounts.qmltypes "${KEEL_QML_OUTPUT_DIR}/org/nemomobile/accounts/plugins.qmltypes" COPYONLY)
install(TARGETS nemoaccounts LIBRARY DESTINATION "${KEEL_QML_INSTALL_DIR}/org/nemomobile/accounts")
install(FILES "${KEEL_QML_OUTPUT_DIR}/org/nemomobile/accounts/qmldir"
              "${KEEL_QML_OUTPUT_DIR}/org/nemomobile/accounts/plugins.qmltypes"
        DESTINATION "${KEEL_QML_INSTALL_DIR}/org/nemomobile/accounts")
