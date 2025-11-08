cmake_minimum_required(VERSION 3.16)

project(marathon-dev VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core)

# Simple CLI tool - just links to MarathonCore library
set(SOURCES
    main.cpp
)

qt6_add_executable(marathon-dev ${SOURCES})

target_include_directories(marathon-dev PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../../marathon-core/src
)

target_link_libraries(marathon-dev PRIVATE
    Qt6::Core
    MarathonCore
)

install(TARGETS marathon-dev
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

