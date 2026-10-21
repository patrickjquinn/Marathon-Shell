# Marathon Shell Component Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core Gui Qml Sql)

find_program(DBUS_RUN_SESSION dbus-run-session)

# Which keys the compositor keeps for system navigation
add_executable(test_shell_keyrouting test_keyrouting.cpp)
target_link_libraries(test_shell_keyrouting Qt6::Test Qt6::Core)
target_include_directories(test_shell_keyrouting PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_KeyRouting COMMAND test_shell_keyrouting)

# System back for native apps: the key per toolkit, and what counts as handled
add_executable(test_shell_nativeback test_nativeback.cpp)
target_link_libraries(test_shell_nativeback Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_nativeback PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_NativeBack COMMAND test_shell_nativeback)

# Keel cover windows (keel/shell/PROTOCOL.md section 3)
add_executable(test_shell_keelcover test_keelcover.cpp)
target_link_libraries(test_shell_keelcover Qt6::Test Qt6::Core)
target_include_directories(test_shell_keelcover PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_KeelCover COMMAND test_shell_keelcover)

find_package(Qt6 REQUIRED COMPONENTS Gui DBus)

add_executable(test_shell_processtree test_processtree.cpp)
target_link_libraries(test_shell_processtree Qt6::Test Qt6::Core)
target_include_directories(test_shell_processtree PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_ProcessTree COMMAND test_shell_processtree)

find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBDRM REQUIRED libdrm)



# SecurityManager: quick PIN failures count towards the lockout
find_package(Qt6 REQUIRED COMPONENTS Concurrent)
add_executable(test_shell_securitymanager
    test_securitymanager.cpp
)
target_link_libraries(test_shell_securitymanager Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml Qt6::Concurrent ${PAM_LIBRARY})
target_include_directories(test_shell_securitymanager PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/managers ${CMAKE_SOURCE_DIR}/shell/src/components ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_SecurityManager COMMAND test_shell_securitymanager)

# A call for a Keel app that is not running is bus-activated through the shell
find_program(BUSCTL busctl)
find_program(DBUS_DAEMON dbus-daemon)
if(BUSCTL AND DBUS_DAEMON)
    set(_services ${CMAKE_CURRENT_BINARY_DIR}/keel-activation-services)
    set(MARATHON_ACTIVATE ${CMAKE_SOURCE_DIR}/systemd/marathon-activate)
    foreach(KEEL_APP notes refused)
        configure_file(${CMAKE_SOURCE_DIR}/apps/keel-actions.service.in
            ${_services}/org.marathonos.${KEEL_APP}.service @ONLY)
    endforeach()
    add_executable(test_shell_keelactivation test_keelactivation.cpp)
    target_link_libraries(test_shell_keelactivation Qt6::Test Qt6::Core Qt6::DBus)
    target_compile_definitions(test_shell_keelactivation PRIVATE SERVICES_DIR="${_services}")
    add_test(NAME Shell_KeelActivation COMMAND test_shell_keelactivation)
endif()

# app.show for an app that is not running, through the real runner (registered
# in tests/CMakeLists.txt, which finds Keel's Silica)
if(DBUS_DAEMON)
    add_executable(test_shell_keelshow test_keelshow.cpp)
    target_link_libraries(test_shell_keelshow Qt6::Test Qt6::Core Qt6::DBus)
endif()

# Gesture engine: velocity window, commit decisions, settle spring
add_executable(test_shell_gesturetracker
    test_gesturetracker.cpp
    ../../shell/src/services/gesturetracker.cpp
)
target_link_libraries(test_shell_gesturetracker Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_gesturetracker PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_GestureTracker COMMAND test_shell_gesturetracker)

# WindowTextureItem: rounded, cropped texture geometry and the corner shader
find_package(Qt6 REQUIRED COMPONENTS Quick)
add_executable(test_shell_windowtextureitem
    test_windowtextureitem.cpp
    ../../shell/src/components/windowtextureitem.cpp
)
qt_add_resources(test_shell_windowtextureitem "test_shell_shaders"
    PREFIX "/marathon/shaders"
    BASE "${CMAKE_SOURCE_DIR}/shell/shaders"
    FILES
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.vert.qsb
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.frag.qsb
)
target_link_libraries(test_shell_windowtextureitem Qt6::Test Qt6::Quick)
add_test(NAME Shell_WindowTextureItem COMMAND test_shell_windowtextureitem)
set_tests_properties(Shell_WindowTextureItem PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# WindowTextureItem under QtWayland's commit pattern: texture deleted, then
# textureChanged, inside the source's updatePaintNode. Null RHI: the batch
# renderer without a GPU.
add_executable(test_shell_windowtexturestress
    test_windowtexturestress.cpp
    ../../shell/src/components/windowtextureitem.cpp
)
qt_add_resources(test_shell_windowtexturestress "test_shell_stress_shaders"
    PREFIX "/marathon/shaders"
    BASE "${CMAKE_SOURCE_DIR}/shell/shaders"
    FILES
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.vert.qsb
        ${CMAKE_SOURCE_DIR}/shell/shaders/windowcorner.frag.qsb
)
target_link_libraries(test_shell_windowtexturestress Qt6::Test Qt6::Quick)
add_test(NAME Shell_WindowTextureStress COMMAND test_shell_windowtexturestress)
set_tests_properties(Shell_WindowTextureStress PROPERTIES ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=rhi;QSG_RHI_BACKEND=null;QSG_RENDER_LOOP=basic")

# Touch moves resampled to one a frame
add_executable(test_shell_touchresampler test_touchresampler.cpp
    ../../shell/src/services/touchresampler.cpp)
set_target_properties(test_shell_touchresampler PROPERTIES AUTOMOC ON)
target_link_libraries(test_shell_touchresampler Qt6::Test Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::Qml)
target_include_directories(test_shell_touchresampler PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_TouchResampler COMMAND test_shell_touchresampler)

# The touch CPU boost's resting floor

# Frame callbacks of hidden surfaces: about once a second
add_executable(test_shell_hiddenframethrottle test_hiddenframethrottle.cpp)
target_link_libraries(test_shell_hiddenframethrottle Qt6::Test Qt6::Core)
add_test(NAME Shell_HiddenFrameThrottle COMMAND test_shell_hiddenframethrottle)

# NativeClientScale: the scale native apps get, and a client being told it
find_package(Qt6 COMPONENTS WaylandCompositor)
find_package(PkgConfig REQUIRED)
pkg_check_modules(WAYLAND_CLIENT wayland-client)
find_program(WAYLAND_SCANNER wayland-scanner)
if(TARGET Qt6::WaylandCompositor AND WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER)
    set(_fractional_xml ${CMAKE_SOURCE_DIR}/shell/protocols/fractional-scale-v1.xml)
    set(_fractional_gen ${CMAKE_CURRENT_BINARY_DIR}/fractional-scale)
    file(MAKE_DIRECTORY ${_fractional_gen})
    add_custom_command(
        OUTPUT ${_fractional_gen}/fractional-scale-v1-server.h
               ${_fractional_gen}/fractional-scale-v1-client.h
               ${_fractional_gen}/fractional-scale-v1.c
        COMMAND ${WAYLAND_SCANNER} server-header ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1-server.h
        COMMAND ${WAYLAND_SCANNER} client-header ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_fractional_xml} ${_fractional_gen}/fractional-scale-v1.c
        DEPENDS ${_fractional_xml})
    add_executable(test_shell_nativeclientscale
        test_nativeclientscale.cpp
        ../../shell/src/wayland/nativeclientscale.cpp
        ${_fractional_gen}/fractional-scale-v1-server.h
        ${_fractional_gen}/fractional-scale-v1-client.h
        ${_fractional_gen}/fractional-scale-v1.c
    )
    target_link_libraries(test_shell_nativeclientscale
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_nativeclientscale PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_fractional_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_NativeClientScale COMMAND test_shell_nativeclientscale)
    set_tests_properties(Shell_NativeClientScale PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # security-context-v1: sandboxed clients are tagged and miss privileged globals
    set(_security_xml ${CMAKE_SOURCE_DIR}/shell/protocols/security-context-v1.xml)
    set(_security_gen ${CMAKE_CURRENT_BINARY_DIR}/security-context)
    file(MAKE_DIRECTORY ${_security_gen})
    add_custom_command(
        OUTPUT ${_security_gen}/security-context-v1-server.h
               ${_security_gen}/security-context-v1-client.h
               ${_security_gen}/security-context-v1.c
        COMMAND ${WAYLAND_SCANNER} server-header ${_security_xml} ${_security_gen}/security-context-v1-server.h
        COMMAND ${WAYLAND_SCANNER} client-header ${_security_xml} ${_security_gen}/security-context-v1-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_security_xml} ${_security_gen}/security-context-v1.c
        DEPENDS ${_security_xml})
    add_executable(test_shell_securitycontext
        test_securitycontext.cpp
        ../../shell/src/wayland/securitycontextv1.cpp
        ${_security_gen}/security-context-v1-server.h
        ${_security_gen}/security-context-v1-client.h
        ${_security_gen}/security-context-v1.c
    )
    target_link_libraries(test_shell_securitycontext
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_securitycontext PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_security_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_SecurityContext COMMAND test_shell_securitycontext)
    set_tests_properties(Shell_SecurityContext PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # A toplevel is sent a configure only when its size or states change
    pkg_get_variable(_protocols_dir wayland-protocols pkgdatadir)
    set(_xdg_shell_xml ${_protocols_dir}/stable/xdg-shell/xdg-shell.xml)
    find_package(Qt6 COMPONENTS WaylandCompositorPrivate QUIET)
    if(EXISTS ${_xdg_shell_xml} AND TARGET Qt6::WaylandCompositorPrivate)
        set(_xdg_shell_gen ${CMAKE_CURRENT_BINARY_DIR}/xdg-shell)
        file(MAKE_DIRECTORY ${_xdg_shell_gen})
        add_custom_command(
            OUTPUT ${_xdg_shell_gen}/xdg-shell-client.h ${_xdg_shell_gen}/xdg-shell.c
            COMMAND ${WAYLAND_SCANNER} client-header ${_xdg_shell_xml} ${_xdg_shell_gen}/xdg-shell-client.h
            COMMAND ${WAYLAND_SCANNER} private-code ${_xdg_shell_xml} ${_xdg_shell_gen}/xdg-shell.c
            DEPENDS ${_xdg_shell_xml})
        add_executable(test_shell_toplevelconfigure
            test_toplevelconfigure.cpp
            ../../shell/src/wayland/toplevelconfigure.cpp
            ${_xdg_shell_gen}/xdg-shell-client.h
            ${_xdg_shell_gen}/xdg-shell.c
        )
        target_compile_definitions(test_shell_toplevelconfigure PRIVATE HAVE_WAYLAND_PRIVATE)
        target_link_libraries(test_shell_toplevelconfigure
            Qt6::Test Qt6::Gui Qt6::WaylandCompositor Qt6::WaylandCompositorPrivate
            ${WAYLAND_CLIENT_LIBRARIES})
        target_include_directories(test_shell_toplevelconfigure PRIVATE
            ${CMAKE_SOURCE_DIR}/shell/src/wayland ${_xdg_shell_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
        add_test(NAME Shell_ToplevelConfigure COMMAND test_shell_toplevelconfigure)
        set_tests_properties(Shell_ToplevelConfigure PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
    endif()

    # Server and client headers plus marshalling code for a protocol XML,
    # appended to the list named by OUT.
    function(marathon_test_protocol XML STEM OUT)
        set(_gen ${CMAKE_CURRENT_BINARY_DIR}/protocols)
        file(MAKE_DIRECTORY ${_gen})
        add_custom_command(
            OUTPUT ${_gen}/${STEM}-server.h ${_gen}/${STEM}-client.h ${_gen}/${STEM}.c
            COMMAND ${WAYLAND_SCANNER} server-header ${XML} ${_gen}/${STEM}-server.h
            COMMAND ${WAYLAND_SCANNER} client-header ${XML} ${_gen}/${STEM}-client.h
            COMMAND ${WAYLAND_SCANNER} private-code ${XML} ${_gen}/${STEM}.c
            DEPENDS ${XML})
        set(${OUT} ${${OUT}} ${_gen}/${STEM}-server.h ${_gen}/${STEM}-client.h ${_gen}/${STEM}.c
            PARENT_SCOPE)
    endfunction()

    # xdg-activation-v1: launch tokens, and the focus rule for client tokens
    set(_activation_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/xdg-activation-v1.xml
        xdg-activation-v1 _activation_protocol)
    add_executable(test_shell_xdgactivation
        test_xdgactivation.cpp
        ../../shell/src/wayland/xdgactivationv1.cpp
        ${_activation_protocol}
    )
    target_link_libraries(test_shell_xdgactivation
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_xdgactivation PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${CMAKE_CURRENT_BINARY_DIR}/protocols
        ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_XdgActivation COMMAND test_shell_xdgactivation)
    set_tests_properties(Shell_XdgActivation PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    add_executable(test_shell_foreignfocus test_foreignfocus.cpp)
    target_link_libraries(test_shell_foreignfocus
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_foreignfocus PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_ForeignFocus COMMAND test_shell_foreignfocus)
    set_tests_properties(Shell_ForeignFocus PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    # marathon-surface-v1: bind policy, window flags, insets, back events
    set(_marathon_surface_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/marathon-surface-v1.xml
        marathon-surface-v1 _marathon_surface_protocol)
    marathon_test_protocol(${CMAKE_SOURCE_DIR}/shell/protocols/xdg-shell.xml
        xdg-shell _marathon_surface_protocol)
    add_executable(test_shell_marathonsurface
        test_marathonsurface.cpp
        ../../shell/src/wayland/marathonsurfacev1.cpp
        ../../shell/src/wayland/securitycontextv1.cpp
        ${_marathon_surface_protocol}
        ${_security_gen}/security-context-v1-server.h
        ${_security_gen}/security-context-v1.c
    )
    target_link_libraries(test_shell_marathonsurface
        Qt6::Test Qt6::Gui Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_marathonsurface PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src/wayland ${CMAKE_CURRENT_BINARY_DIR}/protocols
        ${_security_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_MarathonSurface COMMAND test_shell_marathonsurface)
    set_tests_properties(Shell_MarathonSurface PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

# The keyboard's replacements reach a text-input-v3 client as byte deletions
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
set(_text_input_xml ${WAYLAND_PROTOCOLS_DIR}/unstable/text-input/text-input-unstable-v3.xml)
if(TARGET Qt6::WaylandCompositor AND WAYLAND_CLIENT_FOUND AND WAYLAND_SCANNER AND EXISTS ${_text_input_xml})
    set(_text_input_gen ${CMAKE_CURRENT_BINARY_DIR}/text-input)
    file(MAKE_DIRECTORY ${_text_input_gen})
    add_custom_command(
        OUTPUT ${_text_input_gen}/text-input-unstable-v3-client.h
               ${_text_input_gen}/text-input-unstable-v3.c
        COMMAND ${WAYLAND_SCANNER} client-header ${_text_input_xml} ${_text_input_gen}/text-input-unstable-v3-client.h
        COMMAND ${WAYLAND_SCANNER} private-code ${_text_input_xml} ${_text_input_gen}/text-input-unstable-v3.c
        DEPENDS ${_text_input_xml})
    add_executable(test_shell_textinputreplace
        test_textinputreplace.cpp
        ../../shell/src/services/inputcontext.cpp
        ${_text_input_gen}/text-input-unstable-v3-client.h
        ${_text_input_gen}/text-input-unstable-v3.c
    )
    target_link_libraries(test_shell_textinputreplace
        Qt6::Test Qt6::Quick Qt6::WaylandCompositor ${WAYLAND_CLIENT_LIBRARIES})
    target_include_directories(test_shell_textinputreplace PRIVATE
        ${CMAKE_SOURCE_DIR}/shell/src ${_text_input_gen} ${WAYLAND_CLIENT_INCLUDE_DIRS})
    add_test(NAME Shell_TextInputReplace COMMAND test_shell_textinputreplace)
    set_tests_properties(Shell_TextInputReplace PROPERTIES ENVIRONMENT
        "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")
endif()

# One screen state, blanked and woken through the backlight, and touch works
# again after a blank and wake
find_package(Qt6 REQUIRED COMPONENTS Quick)
add_executable(test_shell_screenstate test_screenstate.cpp
    ../../shell/src/services/waketouchfilter.cpp)
target_link_libraries(test_shell_screenstate Qt6::Test Qt6::Core Qt6::Gui Qt6::DBus Qt6::Qml
    Qt6::Quick)
target_include_directories(test_shell_screenstate PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Shell_ScreenState COMMAND test_shell_screenstate)
set_tests_properties(Shell_ScreenState PROPERTIES ENVIRONMENT
    "QT_QPA_PLATFORM=offscreen;QT_QUICK_BACKEND=software")

# Power against fake logind, power profiles and systemd: locks, profiles, wake-ups
add_executable(test_shell_powermanager test_powermanager.cpp)
target_link_libraries(test_shell_powermanager Qt6::Test Qt6::Core Qt6::DBus)
add_test(NAME Shell_PowerManager COMMAND test_shell_powermanager)

# Brightness lands on hardware levels; auto-brightness only with a light sensor
add_executable(test_shell_brightness test_brightness.cpp)
target_link_libraries(test_shell_brightness Qt6::Test Qt6::Core)
add_test(NAME Shell_Brightness COMMAND test_shell_brightness)

# The shell's Rust half (crates/marathon-shell-native) backs classes most
# of these tests compile; every shell test links it.
get_property(_shell_tests DIRECTORY PROPERTY BUILDSYSTEM_TARGETS)
foreach(_t IN LISTS _shell_tests)
    get_target_property(_type ${_t} TYPE)
    if(_t MATCHES "^test_shell_" AND _type STREQUAL "EXECUTABLE")
        target_link_libraries(${_t} marathon_shell_native)
    endif()
endforeach()
