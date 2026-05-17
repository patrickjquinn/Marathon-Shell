cmake_minimum_required(VERSION 3.16)

project(marathon-compositor VERSION 1.0.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_INCLUDE_CURRENT_DIR ON)

find_package(Qt6 REQUIRED COMPONENTS
    Core
    Gui
    Qml
    Quick
    WaylandCompositor
    DBus
)

# wayland-scanner is what we use for our custom protocols (same as the shell's
# text-input-v3 pattern). qtwaylandscanner is a different beast that wraps
# things in QWaylandCompositorExtension — fine but less consistent with how
# textinputv3 already works here.
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

# libsystemd for sd_notify(READY=1) — Type=notify service unit needs this.
find_package(PkgConfig REQUIRED)
pkg_check_modules(SYSTEMD QUIET libsystemd)
pkg_check_modules(WAYLAND_SERVER REQUIRED wayland-server)

# Generates wayland-<name>-server.h and wayland-<name>.c for a given XML.
function(marathon_wayland_protocol target xml)
    get_filename_component(base "${xml}" NAME_WE)
    set(header "${CMAKE_CURRENT_BINARY_DIR}/${base}-server.h")
    set(source "${CMAKE_CURRENT_BINARY_DIR}/${base}.c")
    add_custom_command(
        OUTPUT  "${header}"
        COMMAND "${WAYLAND_SCANNER}" server-header "${xml}" "${header}"
        DEPENDS "${xml}"
        VERBATIM
    )
    add_custom_command(
        OUTPUT  "${source}"
        COMMAND "${WAYLAND_SCANNER}" private-code "${xml}" "${source}"
        DEPENDS "${xml}"
        VERBATIM
    )
    target_sources(${target} PRIVATE "${header}" "${source}")
endfunction()

set(SOURCES
    main.cpp
    compositor.cpp
    compositor.h
    textinputv3.cpp
    textinputv3.h
    layer_shell_v1.cpp
    layer_shell_v1.h
    session_lock_v1.cpp
    session_lock_v1.h
    foreign_toplevel_v1.cpp
    foreign_toplevel_v1.h
    screencopy_v1.cpp
    screencopy_v1.h
)

qt6_add_executable(marathon-compositor ${SOURCES})

marathon_wayland_protocol(marathon-compositor
    "${CMAKE_CURRENT_SOURCE_DIR}/../../shell/protocols/text-input-unstable-v3.xml")
marathon_wayland_protocol(marathon-compositor
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/wlr-layer-shell-unstable-v1.xml")
marathon_wayland_protocol(marathon-compositor
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/ext-session-lock-v1.xml")
marathon_wayland_protocol(marathon-compositor
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/wlr-foreign-toplevel-management-unstable-v1.xml")
marathon_wayland_protocol(marathon-compositor
    "${CMAKE_CURRENT_SOURCE_DIR}/protocols/wlr-screencopy-unstable-v1.xml")
# wlr-layer-shell references xdg_popup_interface from xdg-shell. Qt links
# its own private copy that doesn't expose the C symbol, so we generate
# the xdg-shell server stub ourselves to satisfy the reference. Symbol is
# wire-compatible across all xdg-shell consumers; only used as a vtable
# anchor here for get_popup.
marathon_wayland_protocol(marathon-compositor
    "/usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml")

qt6_add_qml_module(marathon-compositor
    URI MarathonCompositor
    VERSION 1.0
    QML_FILES Compositor.qml
    RESOURCE_PREFIX /qt/qml
)

target_include_directories(marathon-compositor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_BINARY_DIR}
    ${WAYLAND_SERVER_INCLUDE_DIRS}
)

target_link_libraries(marathon-compositor PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandCompositor
    Qt6::DBus
    ${WAYLAND_SERVER_LIBRARIES}
)

if(TARGET Qt6::WaylandCompositorPrivate)
    target_link_libraries(marathon-compositor PRIVATE Qt6::WaylandCompositorPrivate)
    target_compile_definitions(marathon-compositor PRIVATE MARATHON_HAVE_WAYLAND_PRIVATE=1)
endif()

if(SYSTEMD_FOUND)
    target_link_libraries(marathon-compositor PRIVATE ${SYSTEMD_LIBRARIES})
    target_include_directories(marathon-compositor PRIVATE ${SYSTEMD_INCLUDE_DIRS})
    target_compile_definitions(marathon-compositor PRIVATE MARATHON_HAVE_SD_NOTIFY=1)
endif()

install(TARGETS marathon-compositor RUNTIME DESTINATION bin)

# systemd user units + greetd launcher for the split-process session.
# Image-build pipelines pull these from $prefix/lib/systemd/user and
# $prefix/libexec/marathon-session into /usr/lib/systemd/user and
# /usr/libexec respectively.
install(FILES
    ${CMAKE_CURRENT_SOURCE_DIR}/../../platforms/duranium/systemd/marathon-compositor.service
    ${CMAKE_CURRENT_SOURCE_DIR}/../../platforms/duranium/systemd/marathon-shell.service
    ${CMAKE_CURRENT_SOURCE_DIR}/../../platforms/duranium/systemd/marathon-session.target
    DESTINATION lib/systemd/user
)
install(PROGRAMS
    ${CMAKE_CURRENT_SOURCE_DIR}/../../platforms/duranium/marathon-session
    DESTINATION libexec
)
