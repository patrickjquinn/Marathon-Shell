# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT

cmake_minimum_required(VERSION 3.16)
project(keel-test-client LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)
find_package(Qt6 REQUIRED COMPONENTS Gui DBus)
add_executable(keel-test-client main.cpp)
target_link_libraries(keel-test-client PRIVATE Qt6::Gui Qt6::DBus)
