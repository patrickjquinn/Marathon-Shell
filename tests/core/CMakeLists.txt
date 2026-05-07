# Marathon Core Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core)

# AppRegistry tests (pure data model, no external deps)
add_executable(test_core_appregistry
    test_appregistry.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_appregistry Qt6::Test Qt6::Core)
target_include_directories(test_core_appregistry PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppRegistry COMMAND test_core_appregistry)

# AppPackager tests (validation + round-trip with zip/unzip)
add_executable(test_core_apppackager
    test_apppackager.cpp
    ../../marathon-core/src/marathonapppackager.cpp
)
target_link_libraries(test_core_apppackager Qt6::Test Qt6::Core)
target_include_directories(test_core_apppackager PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppPackager COMMAND test_core_apppackager)

# PermissionManager tests (grant/deny/revoke logic)
add_executable(test_core_permissionmanager
    test_permissionmanager.cpp
    ../../shell/src/marathonpermissionmanager.cpp
    ../../shell/src/components/portalmanager.cpp
)
target_link_libraries(test_core_permissionmanager Qt6::Test Qt6::Core Qt6::DBus)
target_include_directories(test_core_permissionmanager PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src
    ${CMAKE_SOURCE_DIR}/shell/src/components
)
add_test(NAME Core_PermissionManager COMMAND test_core_permissionmanager)

# AppInstaller security tests (path traversal, uninstall protection)
add_executable(test_core_installer_security
    test_installer_security.cpp
    ../../marathon-core/src/marathonappinstaller.cpp
    ../../marathon-core/src/marathonapppackager.cpp
    ../../marathon-core/src/marathonappverifier.cpp
    ../../marathon-core/src/marathonappregistry.cpp
    ../../marathon-core/src/marathonappscanner.cpp
)
target_link_libraries(test_core_installer_security Qt6::Test Qt6::Core)
target_include_directories(test_core_installer_security PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_InstallerSecurity COMMAND test_core_installer_security)

# AppScanner tests (manifest parsing, signal contracts, validation)
add_executable(test_core_appscanner
    test_appscanner.cpp
    ../../marathon-core/src/marathonappscanner.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_core_appscanner Qt6::Test Qt6::Core)
target_include_directories(test_core_appscanner PRIVATE
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Core_AppScanner COMMAND test_core_appscanner)

# DesktopFileParser tests (exec cleaning, .desktop parsing, icon resolution)
add_executable(test_core_desktopfileparser
    test_desktopfileparser.cpp
    ../../shell/src/components/desktopfileparser.cpp
)
target_link_libraries(test_core_desktopfileparser Qt6::Test Qt6::Core)
target_include_directories(test_core_desktopfileparser PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/components
)
add_test(NAME Core_DesktopFileParser COMMAND test_core_desktopfileparser)
