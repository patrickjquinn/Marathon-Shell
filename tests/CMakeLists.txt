cmake_minimum_required(VERSION 3.16)

project(MarathonTests)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Test DBus)

# When configuring tests standalone (cmake -S tests), CMAKE_SOURCE_DIR points at ./tests.
# Compute repository root explicitly so paths work both standalone and when included by a parent.
set(REPO_ROOT "${CMAKE_CURRENT_LIST_DIR}/..")

# Build/link MarathonCore from the repo so tests always have the target available.
add_subdirectory("${REPO_ROOT}/marathon-core" "${CMAKE_CURRENT_BINARY_DIR}/marathon-core-build")

# Include source directories
include_directories(
    "${REPO_ROOT}/shell/src"
    "${REPO_ROOT}/marathon-core/src"
)

# Test for AppPackager
add_executable(test_apppackager
    test_apppackager.cpp
)

target_link_libraries(test_apppackager
    Qt6::Core
    Qt6::Test
    MarathonCore
)

add_test(NAME AppPackager COMMAND test_apppackager)

# Test for AppVerifier
add_executable(test_appverifier
    test_appverifier.cpp
)

target_link_libraries(test_appverifier
    Qt6::Core
    Qt6::Test
    MarathonCore
)

add_test(NAME AppVerifier COMMAND test_appverifier)

# Test for PermissionManager
add_executable(test_permissionmanager
    test_permissionmanager.cpp
    ${REPO_ROOT}/shell/src/marathonpermissionmanager.cpp
    ${REPO_ROOT}/shell/src/portalmanager.cpp
)

target_link_libraries(test_permissionmanager
    Qt6::Core
    Qt6::Test
    Qt6::DBus
)

add_test(NAME PermissionManager COMMAND test_permissionmanager)

# Enable testing
enable_testing()

# Test execution message
message(STATUS "Tests configured. Run 'ctest' or 'make test' to execute.")

