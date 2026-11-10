# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Keel Actions for a CMake (C++/QML) app (ADR-0018): runs `keel actions`
# (tools/keel-dev) at build time, compiles the generated adaptor into the
# target and installs the manifest, the D-Bus files and nothing else.
#
#   include(/path/to/keel/actions/cmake/KeelActions.cmake)
#   keel_add_actions(my-app
#       APP_ID org.example.my-app                 # OrganizationName.ApplicationName
#       DESKTOP ${CMAKE_SOURCE_DIR}/my-app.desktop
#       QML ${CMAKE_SOURCE_DIR}/qml)
#
# KEEL_DEV_EXECUTABLE: the `keel` tool (default: found on PATH). Add the
# ExecDBus line it prints to the desktop file's [X-Sailjail] section.

function(keel_add_actions target)
    cmake_parse_arguments(KA "" "APP_ID;DESKTOP" "QML;RUST" ${ARGN})
    if(NOT KA_APP_ID OR NOT KA_DESKTOP)
        message(FATAL_ERROR "keel_add_actions: APP_ID and DESKTOP are required")
    endif()
    if(NOT KEEL_DEV_EXECUTABLE)
        find_program(KEEL_DEV_EXECUTABLE keel REQUIRED)
    endif()
    set(_out "${CMAKE_CURRENT_BINARY_DIR}/keel-actions")
    set(_args actions --desktop "${KA_DESKTOP}" --app-id "${KA_APP_ID}" --out "${_out}")
    set(_deps "${KA_DESKTOP}")
    foreach(_d IN LISTS KA_QML)
        list(APPEND _args --qml "${_d}")
        file(GLOB_RECURSE _f CONFIGURE_DEPENDS "${_d}/*.qml")
        list(APPEND _deps ${_f})
    endforeach()
    foreach(_d IN LISTS KA_RUST)
        list(APPEND _args --rust "${_d}")
        file(GLOB_RECURSE _f CONFIGURE_DEPENDS "${_d}/*.rs")
        list(APPEND _deps ${_f})
    endforeach()
    set(_outputs
        "${_out}/actions.json" "${_out}/keel_actions.c"
        "${_out}/${KA_APP_ID}.actions.xml" "${_out}/${KA_APP_ID}.service")
    add_custom_command(
        OUTPUT ${_outputs}
        COMMAND "${KEEL_DEV_EXECUTABLE}" ${_args}
        DEPENDS ${_deps}
        COMMENT "Keel Actions: generating ${KA_APP_ID}"
        VERBATIM)
    target_sources(${target} PRIVATE "${_out}/keel_actions.c")
    if(NOT DEFINED CMAKE_INSTALL_DATADIR)
        include(GNUInstallDirs)
    endif()
    install(FILES "${_out}/actions.json"
            DESTINATION "${CMAKE_INSTALL_DATADIR}/keel/actions" RENAME "${KA_APP_ID}.json")
    install(FILES "${_out}/${KA_APP_ID}.service" DESTINATION "${CMAKE_INSTALL_DATADIR}/dbus-1/services")
    install(FILES "${_out}/${KA_APP_ID}.actions.xml" DESTINATION "${CMAKE_INSTALL_DATADIR}/dbus-1/interfaces")
endfunction()
