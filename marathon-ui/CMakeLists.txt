cmake_minimum_required(VERSION 3.21)

project(MarathonUI VERSION 2.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS
    Core
    Qml
    Quick
)

# Installation directory - system-wide for production, user-local for dev
if(CMAKE_INSTALL_PREFIX STREQUAL "/usr" OR CMAKE_INSTALL_PREFIX STREQUAL "/usr/local")
    set(MARATHON_UI_DIR "${CMAKE_INSTALL_PREFIX}/lib/qt6/qml/MarathonUI" CACHE PATH "MarathonUI installation directory")
else()
    # Default to user-local for development
    set(MARATHON_UI_DIR "$ENV{HOME}/.local/share/marathon-ui" CACHE PATH "MarathonUI installation directory")
endif()

# Override if explicitly set via cmake
if(DEFINED ENV{MARATHON_UI_DIR})
    set(MARATHON_UI_DIR "$ENV{MARATHON_UI_DIR}" CACHE PATH "MarathonUI installation directory" FORCE)
endif()

# Singleton files will be marked in individual module CMakeLists.txt files

# Build all MarathonUI modules (order matters for dependencies)
add_subdirectory(Theme)
add_subdirectory(Core)
add_subdirectory(Controls)
add_subdirectory(Lists)
add_subdirectory(Navigation)
add_subdirectory(Feedback)
add_subdirectory(Modals)
add_subdirectory(Effects)
add_subdirectory(Containers)  # Last - depends on Controls

message(STATUS "==========================================")
message(STATUS "MarathonUI Build Configuration")
message(STATUS "Version: ${PROJECT_VERSION}")
message(STATUS "Installation directory: ${MARATHON_UI_DIR}")
message(STATUS "==========================================")

