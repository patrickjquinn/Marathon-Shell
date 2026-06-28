cmake_minimum_required(VERSION 3.16)
project(marathon-webview-runner VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC OFF)

# Per project_wpe_webview_plan: Marathon's webview path is WPE WebKit
# 2.52.4 (custom main/wpewebkit aport — Alpine dropped it 2025-07-09)
# + WPEBackend-fdo 1.16.1, embedded out-of-process per app. This
# runner is the per-app host process. It links the WPE engine and
# forwards rendered dmabufs to Marathon's existing
# zwp_linux_dmabuf_v1 v4 server (shell/src/wayland/linuxdmabufv1.*).
find_package(PkgConfig REQUIRED)
pkg_check_modules(WPE_WEBKIT REQUIRED wpe-webkit-2.0)
pkg_check_modules(WPE_FDO REQUIRED wpebackend-fdo-1.0)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(GLIB REQUIRED glib-2.0 gobject-2.0)

add_executable(marathon-webview-runner main.cpp)

target_include_directories(marathon-webview-runner PRIVATE
    ${WPE_WEBKIT_INCLUDE_DIRS}
    ${WPE_FDO_INCLUDE_DIRS}
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
    ${GLIB_INCLUDE_DIRS}
)

target_link_libraries(marathon-webview-runner PRIVATE
    ${WPE_WEBKIT_LIBRARIES}
    ${WPE_FDO_LIBRARIES}
    ${WAYLAND_CLIENT_LIBRARIES}
    ${GLIB_LIBRARIES}
)

target_compile_options(marathon-webview-runner PRIVATE
    ${WPE_WEBKIT_CFLAGS_OTHER}
    ${WPE_FDO_CFLAGS_OTHER}
)

install(TARGETS marathon-webview-runner
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
