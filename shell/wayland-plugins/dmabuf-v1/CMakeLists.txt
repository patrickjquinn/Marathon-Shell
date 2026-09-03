cmake_minimum_required(VERSION 3.16)
# C must be enabled: qt6_generate_wayland_protocol_server_sources emits a C
# protocol file (wayland-linux-dmabuf-v1-protocol.c) defining the wl_interface
# structs the C++ wrapper dereferences (zwp_linux_dmabuf_v1_interface,
# zwp_linux_buffer_params_v1_interface, ...). With only CXX enabled CMake
# silently drops that .c, the .so fails to relocate ("symbol not found"), and
# QPluginLoader discards the plugin -> keys() never lists linux-dmabuf-v1 ->
# compositor falls back to wayland-egl (v3 / no feedback -> Mesa llvmpipe).
project(marathon_linux_dmabuf_v1 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui WaylandCompositor
             CorePrivate GuiPrivate WaylandCompositorPrivate)
find_package(PkgConfig REQUIRED)
pkg_check_modules(EGL REQUIRED egl)
pkg_check_modules(WLSERVER REQUIRED wayland-server)
pkg_check_modules(LIBDRM REQUIRED libdrm)

# Build the client-buffer-integration plugin as a runtime-loadable module.
# Named to match Qt's convention so the compositor's plugin loader finds it
# under wayland-graphics-integration-server. Selected at runtime via the
# QT_WAYLAND_HARDWARE_INTEGRATION list (Keys "linux-dmabuf-v1" in the .json).
add_library(qt-wayland-compositor-linux-dmabuf-v1 MODULE
    linuxdmabuf.cpp
    linuxdmabufclientbufferintegration.cpp
    main.cpp
)

# Generate the C++ QtWaylandServer wrapper AND the C wl_interface definitions
# (v4 feedback interfaces) from the stable protocol. This is what 6.11's
# bundled unstable-v1 plugin lacks.
qt6_generate_wayland_protocol_server_sources(qt-wayland-compositor-linux-dmabuf-v1
    PRIVATE_CODE
    FILES /usr/share/wayland-protocols/stable/linux-dmabuf/linux-dmabuf-v1.xml
)

target_include_directories(qt-wayland-compositor-linux-dmabuf-v1 PRIVATE
    ${EGL_INCLUDE_DIRS} ${WLSERVER_INCLUDE_DIRS} ${LIBDRM_INCLUDE_DIRS}
)

target_link_libraries(qt-wayland-compositor-linux-dmabuf-v1 PRIVATE
    Qt6::Core Qt6::CorePrivate
    Qt6::Gui  Qt6::GuiPrivate
    Qt6::WaylandCompositor Qt6::WaylandCompositorPrivate
    ${EGL_LIBRARIES} ${WLSERVER_LIBRARIES} ${LIBDRM_LIBRARIES}
)

# Match Qt's plugin filename: libqt-wayland-compositor-linux-dmabuf-v1.so
set_target_properties(qt-wayland-compositor-linux-dmabuf-v1 PROPERTIES PREFIX "lib")
