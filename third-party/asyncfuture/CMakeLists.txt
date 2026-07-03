cmake_minimum_required(VERSION 3.10)
project(asyncfuture VERSION 1.0.0 LANGUAGES CXX)

option(ENABLE_TESTING "Enable testing for the project" OFF)

add_library(asyncfuture INTERFACE)
target_include_directories(asyncfuture INTERFACE
    $<BUILD_INTERFACE:${PROJECT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>)

if(ENABLE_TESTING)
    add_subdirectory(tests)
endif()

set_target_properties(asyncfuture PROPERTIES PUBLIC_HEADER "asyncfuture.h")


install(TARGETS asyncfuture
    LIBRARY DESTINATION lib
    PUBLIC_HEADER DESTINATION include)

export(TARGETS asyncfuture NAMESPACE asyncfuture:: FILE asyncfutureConfig.cmake)
set(CMAKE_EXPORT_PACKAGE_REGISTRY ON)
export(PACKAGE asyncfuture)
