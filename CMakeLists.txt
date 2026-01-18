cmake_minimum_required(VERSION 3.21)

project(MarathonOS VERSION 1.0.0 LANGUAGES C CXX)

enable_testing()


if(POLICY CMP0071)
    cmake_policy(SET CMP0071 NEW)
endif()

if(COMMAND qt_policy)
    qt_policy(SET QTP0001 NEW)
    qt_policy(SET QTP0004 NEW)
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

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

set(QML_IMPORT_PATH
    "${CMAKE_BINARY_DIR}"
    "${CMAKE_BINARY_DIR}/shell/qml"
    CACHE STRING "" FORCE
)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Optional: Qt private API usage is sometimes needed for low-level platform hooks (e.g. screen power).
# Qt prints a warning when GuiPrivate headers are used because it ties you to the exact Qt build.
option(MARATHON_USE_QT_GUI_PRIVATE "Use Qt GuiPrivate (Qt internal headers) for platform hooks" ON)
option(MARATHON_SUPPRESS_QT_PRIVATE_WARNINGS "Silence Qt warning about using private modules" ON)
if(MARATHON_SUPPRESS_QT_PRIVATE_WARNINGS)
    set(QT_NO_PRIVATE_MODULE_WARNING ON CACHE BOOL "Silence Qt private module warning" FORCE)
endif()

# LunaSVG - Lightweight SVG rendering library with full clipPath support
# Qt's SVG module doesn't support clipPath, which breaks GNOME icon rendering
include(FetchContent)
set(LUNASVG_BUILD_EXAMPLES OFF CACHE BOOL "Disable lunasvg examples (svg2png) in Marathon builds" FORCE)
FetchContent_Declare(
    lunasvg
    GIT_REPOSITORY https://github.com/sammycage/lunasvg.git
    GIT_TAG v3.2.0
)
FetchContent_MakeAvailable(lunasvg)
# Our project enables CMake AUTOGEN globally for Qt, but lunasvg is a non-Qt library.
# Disable Qt AUTOGEN on lunasvg targets to avoid noisy dev warnings.
if(TARGET lunasvg)
    set_target_properties(lunasvg PROPERTIES AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
endif()
if(TARGET svg2png)
    set_target_properties(svg2png PROPERTIES AUTOMOC OFF AUTOUIC OFF AUTORCC OFF)
endif()
message(STATUS "LunaSVG fetched for proper SVG icon rendering")

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

find_package(Qt6 6.4...6.10.1 REQUIRED COMPONENTS
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

# GuiPrivate is optional: it's a Qt-internal module (unstable across Qt versions).
# We only use it when explicitly enabled.
if(MARATHON_USE_QT_GUI_PRIVATE)
    find_package(Qt6 6.4 COMPONENTS GuiPrivate QUIET)
endif()
if(TARGET Qt6::GuiPrivate)
    message(STATUS "Qt6::GuiPrivate found - enabling private API features")
    set(HAVE_GUI_PRIVATE TRUE)
else()
    message(STATUS "Qt6::GuiPrivate not found/disabled - private API features disabled")
    set(HAVE_GUI_PRIVATE FALSE)
endif()

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

    # Also find the private module for text-input-v3 support
    find_package(Qt6 6.4 COMPONENTS WaylandCompositorPrivate QUIET)
    if(TARGET Qt6::WaylandCompositorPrivate)
        message(STATUS "Qt WaylandCompositorPrivate found - enabling text-input-v3 for native apps")
        set(HAVE_WAYLAND_PRIVATE TRUE)
    else()
        message(STATUS "Qt WaylandCompositorPrivate not found - text-input-v3 disabled")
        set(HAVE_WAYLAND_PRIVATE FALSE)
    endif()
else()
        message(STATUS "Qt WaylandCompositor not found - Wayland support disabled")
    set(HAVE_WAYLAND FALSE)
    endif()
endif()

# Marathon Core library (shared app management logic)
add_subdirectory(marathon-core)
message(STATUS "Marathon Core library added for app management")

add_subdirectory(marathon-services)

add_subdirectory(marathon-ui)
add_subdirectory(shell)
add_subdirectory(tools/marathon-dev)
add_subdirectory(tools/marathon-app-runner)
add_subdirectory(tools/marathon-sandbox)

message(STATUS "=== Marathon OS ===")
message(STATUS "Qt version: ${Qt6_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "==================")

# Installation for production Linux mobile deployment
include(GNUInstallDirs)

# Install session launcher script
install(PROGRAMS platforms/generic/marathon-shell-session
    DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install Wayland session file
install(FILES platforms/generic/marathon.desktop
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

# Install shared system assets (Option C: filesystem assets shared across processes)
# Wallpapers
install(DIRECTORY shell/resources/wallpapers/
    DESTINATION ${CMAKE_INSTALL_DATADIR}/marathon-shell/wallpapers
    FILES_MATCHING PATTERN "*.jpg" PATTERN "*.png" PATTERN "*.jpeg" PATTERN "*.webp"
)

# Sounds
install(DIRECTORY shell/resources/sounds/
    DESTINATION ${CMAKE_INSTALL_DATADIR}/marathon-shell/sounds
    FILES_MATCHING PATTERN "*.wav" PATTERN "*.ogg" PATTERN "*.mp3" PATTERN "*.m4a"
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
install(FILES platforms/generic/marathon-shell.toml
    DESTINATION ${CMAKE_INSTALL_DATADIR}/greetd
    RENAME marathon-shell-example.toml
)

# Install EGLFS KMS config (used by marathon-shell-session when running under eglfs_kms)
install(FILES platforms/generic/eglfs.json
    DESTINATION ${CMAKE_INSTALL_DATADIR}/marathon
)

# Install documentation
install(FILES README.md
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
)

install(DIRECTORY docs/
    DESTINATION ${CMAKE_INSTALL_DOCDIR}
    FILES_MATCHING PATTERN "*.md"
)

# Tests
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()
