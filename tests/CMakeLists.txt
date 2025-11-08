cmake_minimum_required(VERSION 3.16)

project(MarathonTests)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Test)

# Include shell source directories
include_directories(${CMAKE_SOURCE_DIR}/shell/src)

# Test for AppPackager
add_executable(test_apppackager
    test_apppackager.cpp
    ${CMAKE_SOURCE_DIR}/shell/src/marathonapppackager.cpp
)

target_link_libraries(test_apppackager
    Qt6::Core
    Qt6::Test
)

add_test(NAME AppPackager COMMAND test_apppackager)

# Test for AppVerifier
add_executable(test_appverifier
    test_appverifier.cpp
    ${CMAKE_SOURCE_DIR}/shell/src/marathonappverifier.cpp
)

target_link_libraries(test_appverifier
    Qt6::Core
    Qt6::Test
)

add_test(NAME AppVerifier COMMAND test_appverifier)

# Test for PermissionManager
add_executable(test_permissionmanager
    test_permissionmanager.cpp
    ${CMAKE_SOURCE_DIR}/shell/src/marathonpermissionmanager.cpp
)

target_link_libraries(test_permissionmanager
    Qt6::Core
    Qt6::Test
)

add_test(NAME PermissionManager COMMAND test_permissionmanager)

# Enable testing
enable_testing()

# Test execution message
message(STATUS "Tests configured. Run 'ctest' or 'make test' to execute.")

