cmake_minimum_required(VERSION 3.21)

project(MarathonOS VERSION 0.1.0 LANGUAGES CXX)

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Svg
    DBus
)

find_package(Qt6 6.5 COMPONENTS VirtualKeyboard)
if(TARGET Qt6::VirtualKeyboard)
    message(STATUS "Qt VirtualKeyboard found - enabling on-screen keyboard")
    set(HAVE_VIRTUALKEYBOARD TRUE)
else()
    message(STATUS "Qt VirtualKeyboard not found - keyboard support disabled")
    set(HAVE_VIRTUALKEYBOARD FALSE)
endif()

add_subdirectory(shell)

message(STATUS "=== Marathon OS ===")
message(STATUS "Qt version: ${Qt6_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "==================")

