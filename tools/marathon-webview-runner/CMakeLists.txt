cmake_minimum_required(VERSION 3.16)
project(marathon-webview-runner VERSION 1.0.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC OFF)

# Per project_wpe_phase_2_validated: Phase 2 scaffold proved WPE WebKit
# boots on etnaviv. Phase 2.1 (this file) wires the
# wpe_view_backend_exportable_fdo_egl_client pipeline: WebProcess renders
# into an EGLImage, host receives it via export_fdo_egl_image, converts
# to a wl_buffer with eglCreateWaylandBufferFromImageWL, attaches it to
# the runner's xdg_surface, lets Marathon's compositor adopt the result.
# Mirrors Cog's platform/wayland/cog-view-wl.c pattern.
find_package(PkgConfig REQUIRED)
pkg_check_modules(WPE_WEBKIT REQUIRED wpe-webkit-2.0)
pkg_check_modules(WPE_FDO REQUIRED wpebackend-fdo-1.0)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WAYLAND_EGL REQUIRED wayland-egl)
pkg_check_modules(EGL REQUIRED egl)
pkg_check_modules(GLIB REQUIRED glib-2.0 gobject-2.0)
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols)
pkg_get_variable(WAYLAND_PROTOCOLS_DATADIR wayland-protocols pkgdatadir)

# Codegen xdg-shell client glue (xdg_wm_base / xdg_surface / xdg_toplevel).
# wayland-scanner ships with wayland-dev — already in marathon-shell makedeps.
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

set(_xdg_xml "${WAYLAND_PROTOCOLS_DATADIR}/stable/xdg-shell/xdg-shell.xml")
set(_xdg_header "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-client-protocol.h")
set(_xdg_source "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-protocol.c")
set(_dmabuf_xml "${WAYLAND_PROTOCOLS_DATADIR}/stable/linux-dmabuf/linux-dmabuf-v1.xml")
set(_dmabuf_header "${CMAKE_CURRENT_BINARY_DIR}/linux-dmabuf-v1-client-protocol.h")
set(_dmabuf_source "${CMAKE_CURRENT_BINARY_DIR}/linux-dmabuf-v1-protocol.c")

add_custom_command(
    OUTPUT  "${_xdg_header}"
    COMMAND "${WAYLAND_SCANNER}" client-header "${_xdg_xml}" "${_xdg_header}"
    DEPENDS "${_xdg_xml}"
    VERBATIM)

add_custom_command(
    OUTPUT  "${_xdg_source}"
    COMMAND "${WAYLAND_SCANNER}" private-code "${_xdg_xml}" "${_xdg_source}"
    DEPENDS "${_xdg_xml}"
    VERBATIM)

add_custom_command(
    OUTPUT  "${_dmabuf_header}"
    COMMAND "${WAYLAND_SCANNER}" client-header "${_dmabuf_xml}" "${_dmabuf_header}"
    DEPENDS "${_dmabuf_xml}"
    VERBATIM)

add_custom_command(
    OUTPUT  "${_dmabuf_source}"
    COMMAND "${WAYLAND_SCANNER}" private-code "${_dmabuf_xml}" "${_dmabuf_source}"
    DEPENDS "${_dmabuf_xml}"
    VERBATIM)

add_executable(marathon-webview-runner
    main.cpp
    "${_xdg_source}"
    "${_xdg_header}"
    "${_dmabuf_source}"
    "${_dmabuf_header}"
)

target_include_directories(marathon-webview-runner PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    ${WPE_WEBKIT_INCLUDE_DIRS}
    ${WPE_FDO_INCLUDE_DIRS}
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${WAYLAND_EGL_INCLUDE_DIRS}
    ${EGL_INCLUDE_DIRS}
    ${GLIB_INCLUDE_DIRS}
)

target_link_libraries(marathon-webview-runner PRIVATE
    ${WPE_WEBKIT_LIBRARIES}
    ${WPE_FDO_LIBRARIES}
    ${WAYLAND_CLIENT_LIBRARIES}
    ${WAYLAND_EGL_LIBRARIES}
    ${EGL_LIBRARIES}
    ${GLIB_LIBRARIES}
)

target_compile_options(marathon-webview-runner PRIVATE
    ${WPE_WEBKIT_CFLAGS_OTHER}
    ${WPE_FDO_CFLAGS_OTHER}
)

install(TARGETS marathon-webview-runner
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
