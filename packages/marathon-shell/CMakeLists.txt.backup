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

# Use Homebrew Qt 6.9.3 for compatibility with WebEngine
set(CMAKE_PREFIX_PATH "/opt/homebrew/opt/qt@6" ${CMAKE_PREFIX_PATH})
message(STATUS "Using Homebrew Qt 6.9.3 for WebEngine compatibility")

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    QuickControls2
    Svg
    DBus
    Multimedia
)

# Try to find Qt6WebEngineQuick
find_package(Qt6 6.5 COMPONENTS WebEngineQuick)
if(TARGET Qt6::WebEngineQuick)
    message(STATUS "Qt WebEngineQuick found - enabling web browser")
    set(HAVE_WEBENGINE TRUE)
else()
    message(STATUS "Qt WebEngineQuick not found - browser will use mockup UI")
    set(HAVE_WEBENGINE FALSE)
endif()

find_package(Qt6 6.5 COMPONENTS WaylandCompositor)
if(TARGET Qt6::WaylandCompositor)
    message(STATUS "Qt WaylandCompositor found - enabling Wayland support")
    set(HAVE_WAYLAND TRUE)
else()
    message(STATUS "Qt WaylandCompositor not found - Wayland support disabled (macOS doesn't support it)")
    set(HAVE_WAYLAND FALSE)
endif()

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

