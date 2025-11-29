cmake_minimum_required(VERSION 3.21)

project(MarathonOS VERSION 1.0.0 LANGUAGES CXX)

if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# ARM optimizations for older mobile devices
if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm|aarch64|ARM")
    message(STATUS " Enabling ARM optimizations for mobile device")
    
    # Use NEON SIMD for better performance
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "armv7")
        add_compile_options(-mfpu=neon -mfloat-abi=hard)
        message(STATUS "   ✓ ARM NEON SIMD enabled")
    endif()
    
    # Optimize for size on embedded (older ARM has limited RAM)
    if(CMAKE_BUILD_TYPE MATCHES "Release")
        add_compile_options(-Os -fdata-sections -ffunction-sections)
        add_link_options(-Wl,--gc-sections)
        message(STATUS "   ✓ Size optimization (-Os) enabled for embedded")
    endif()
    
    # Disable debug output to reduce overhead
    add_compile_definitions(
        QT_NO_DEBUG_OUTPUT
        QT_NO_INFO_OUTPUT
    )
    message(STATUS "   ✓ Debug output disabled for performance")
endif()

# Enable QML Language Server support for IDE/VS Code
set(QT_QML_GENERATE_QMLLS_INI ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Qt6 detection - support both Homebrew (macOS) and system installations (Linux)
if(APPLE)
    # Try environment variable first, then Homebrew default
    if(DEFINED ENV{QT_ROOT})
        set(CMAKE_PREFIX_PATH "$ENV{QT_ROOT}" ${CMAKE_PREFIX_PATH})
        message(STATUS "Using Qt from QT_ROOT: $ENV{QT_ROOT}")
    else()
        set(CMAKE_PREFIX_PATH "/opt/homebrew/opt/qt@6" ${CMAKE_PREFIX_PATH})
        message(STATUS "Using Homebrew Qt 6.9.3 for WebEngine compatibility on macOS")
    endif()
elseif(UNIX)
    # On Linux, try standard Qt6 installation paths
    if(NOT DEFINED Qt6_DIR)
        set(Qt6_DIR "/usr/lib/cmake/Qt6" CACHE PATH "Qt6 installation directory")
    endif()
    message(STATUS "Using system Qt6 at ${Qt6_DIR}")
endif()

find_package(Qt6 6.4...6.9.3 REQUIRED COMPONENTS
    Core
    Gui
    Widgets
    Qml
    Quick
    QuickControls2
    Svg
    DBus
    Sql
    Multimedia
    Location
    Positioning
    Sensors
)

# Try to find Qt6WebEngineQuick
find_package(Qt6 6.4 COMPONENTS WebEngineQuick)
if(TARGET Qt6::WebEngineQuick)
    message(STATUS "Qt WebEngineQuick found - enabling web browser")
    set(HAVE_WEBENGINE TRUE)
else()
    message(STATUS "Qt WebEngineQuick not found - browser will use mockup UI")
    set(HAVE_WEBENGINE FALSE)
endif()

# Hunspell for spell-checking and word predictions
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(HUNSPELL QUIET hunspell)
endif()
if(HUNSPELL_FOUND)
    message(STATUS "Hunspell found - enabling spell-checking")
    set(HAVE_HUNSPELL TRUE)
else()
    message(STATUS "Hunspell not found - spell-checking disabled (keyboard will use basic dictionary)")
    set(HAVE_HUNSPELL FALSE)
endif()

# WaylandCompositor is only available on Linux, skip on macOS
if(APPLE)
    message(STATUS "Skipping WaylandCompositor search on macOS (not supported)")
    set(HAVE_WAYLAND FALSE)
else()
find_package(Qt6 6.4 COMPONENTS WaylandCompositor)
if(TARGET Qt6::WaylandCompositor)
    message(STATUS "Qt WaylandCompositor found - enabling Wayland support")
    set(HAVE_WAYLAND TRUE)
else()
        message(STATUS "Qt WaylandCompositor not found - Wayland support disabled")
    set(HAVE_WAYLAND FALSE)
    endif()
endif()

# Add asyncfuture library
add_subdirectory(third-party/asyncfuture)
message(STATUS "AsyncFuture library added for promise-based async operations")

# Marathon Core library (shared app management logic)
add_subdirectory(marathon-core)
message(STATUS "Marathon Core library added for app management")

add_subdirectory(marathon-ui)
add_subdirectory(shell)
add_subdirectory(tools/marathon-dev)

message(STATUS "=== Marathon OS ===")
message(STATUS "Qt version: ${Qt6_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "==================")

# Installation for production Linux mobile deployment
include(GNUInstallDirs)

# Install session launcher script
install(PROGRAMS marathon-shell-session
    DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install Wayland session file
install(FILES marathon.desktop
    DESTINATION ${CMAKE_INSTALL_DATADIR}/wayland-sessions
)

# Install systemd user service
install(FILES systemd/marathon-shell.service
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user
)

# Install polkit policy
install(FILES polkit/org.marathonos.shell.policy
    DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions
)

# Install XDG autostart
install(FILES xdg-autostart/marathon-notification-service.desktop
    DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/xdg/autostart
)

# Install udev rules
install(FILES udev/70-marathon-shell.rules
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/udev/rules.d
)

# Install PAM configuration (requires root privileges)
# Note: This installs to /etc/pam.d which requires sudo
# Manual installation: sudo cp pam.d/marathon-shell /etc/pam.d/marathon-shell
install(FILES pam.d/marathon-shell
    DESTINATION ${CMAKE_INSTALL_SYSCONFDIR}/pam.d
)

# Install greetd configuration example
install(FILES marathon-shell.toml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/greetd
    RENAME marathon-shell-example.toml
)

# Install documentation
install(FILES README.md
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
)

install(DIRECTORY docs/
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
    FILES_MATCHING PATTERN "*.md"
)

