# Marathon's Rust crates, built with cargo the way keel/silica/CMakeLists.txt
# builds keel_silica_native (docs/superpowers/specs/2026-10-13-rust-platform-migration.md).
find_program(MARATHON_CARGO cargo REQUIRED)
find_package(Threads REQUIRED)
option(MARATHON_CARGO_OFFLINE "Pass --offline to cargo (pre-fetched crates)" OFF)
if(DEFINED ENV{CARGO_TARGET_DIR})
    set(_cargo_default_target "$ENV{CARGO_TARGET_DIR}")
else()
    set(_cargo_default_target "${CMAKE_CURRENT_BINARY_DIR}/cargo")
endif()
set(MARATHON_CARGO_TARGET_DIR "${_cargo_default_target}" CACHE PATH "Cargo target directory for crates/")

if(CMAKE_BUILD_TYPE MATCHES "^(Release|RelWithDebInfo|MinSizeRel)$")
    set(_cargo_profile_flag --release)
    set(_cargo_profile_dir release)
else()
    set(_cargo_profile_flag)
    set(_cargo_profile_dir debug)
endif()
set(_cargo_flags --locked)
if(MARATHON_CARGO_OFFLINE)
    list(APPEND _cargo_flags --offline)
endif()
set(_cargo_env ${CMAKE_COMMAND} -E env
    "CARGO_TARGET_DIR=${MARATHON_CARGO_TARGET_DIR}" "CARGO_INCREMENTAL=0")

# libMarathonCore's Rust half. Link it with --exclude-libs so its copy of the
# Rust runtime stays private to the consuming .so.
set(MARATHON_CORE_NATIVE_LIB
    "${MARATHON_CARGO_TARGET_DIR}/${_cargo_profile_dir}/libmarathon_core_native.a")
add_custom_target(marathon_core_native_cargo ALL
    COMMAND ${_cargo_env} "${MARATHON_CARGO}" build -p marathon-core-native
            ${_cargo_flags} ${_cargo_profile_flag}
    BYPRODUCTS "${MARATHON_CORE_NATIVE_LIB}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building marathon-core-native (Rust)"
    USES_TERMINAL
    VERBATIM)
add_library(marathon_core_native INTERFACE)
add_dependencies(marathon_core_native marathon_core_native_cargo)
target_include_directories(marathon_core_native INTERFACE "${MARATHON_CARGO_TARGET_DIR}/cxxbridge")
target_link_libraries(marathon_core_native INTERFACE
    "${MARATHON_CORE_NATIVE_LIB}" Threads::Threads ${CMAKE_DL_LIBS} m)

# marathon-store:// URL handler (xdg-open target and the store refresh timer).
include(GNUInstallDirs)
set(MARATHON_STORE_HANDLER_BIN
    "${MARATHON_CARGO_TARGET_DIR}/${_cargo_profile_dir}/marathon-store-handler")
add_custom_target(marathon_store_handler_cargo ALL
    COMMAND ${_cargo_env} "${MARATHON_CARGO}" build -p marathon-store-handler
            ${_cargo_flags} ${_cargo_profile_flag}
    BYPRODUCTS "${MARATHON_STORE_HANDLER_BIN}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building marathon-store-handler (Rust)"
    USES_TERMINAL
    VERBATIM)
install(PROGRAMS "${MARATHON_STORE_HANDLER_BIN}" DESTINATION ${CMAKE_INSTALL_BINDIR})

# Weather service: org.marathonos.Weather on the session bus, bus-activated
# into a systemd user unit.
set(MARATHON_WEATHERD_BIN
    "${MARATHON_CARGO_TARGET_DIR}/${_cargo_profile_dir}/marathon-weatherd")
add_custom_target(marathon_weatherd_cargo ALL
    COMMAND ${_cargo_env} "${MARATHON_CARGO}" build -p marathon-weatherd
            ${_cargo_flags} ${_cargo_profile_flag}
    BYPRODUCTS "${MARATHON_WEATHERD_BIN}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building marathon-weatherd (Rust)"
    USES_TERMINAL
    VERBATIM)
install(PROGRAMS "${MARATHON_WEATHERD_BIN}" DESTINATION ${CMAKE_INSTALL_BINDIR})
configure_file(marathon-weatherd/data/marathon-weatherd.service.in
    marathon-weatherd.service @ONLY)
configure_file(marathon-weatherd/data/org.marathonos.Weather.service.in
    org.marathonos.Weather.service @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/marathon-weatherd.service"
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/user)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/org.marathonos.Weather.service"
    DESTINATION ${CMAKE_INSTALL_DATADIR}/dbus-1/services)

# Boot health check: holds boot-complete.target until the shell's first frame.
set(MARATHON_HEALTH_BIN
    "${MARATHON_CARGO_TARGET_DIR}/${_cargo_profile_dir}/marathon-health")
add_custom_target(marathon_health_cargo ALL
    COMMAND ${_cargo_env} "${MARATHON_CARGO}" build -p marathon-health
            ${_cargo_flags} ${_cargo_profile_flag}
    BYPRODUCTS "${MARATHON_HEALTH_BIN}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    COMMENT "Building marathon-health (Rust)"
    USES_TERMINAL
    VERBATIM)
install(PROGRAMS "${MARATHON_HEALTH_BIN}" DESTINATION ${CMAKE_INSTALL_BINDIR})
configure_file(marathon-health/data/marathon-boot-health.service.in
    marathon-boot-health.service @ONLY)
install(FILES "${CMAKE_CURRENT_BINARY_DIR}/marathon-boot-health.service"
    DESTINATION ${CMAKE_INSTALL_PREFIX}/lib/systemd/system)

if(BUILD_TESTING)
    add_test(NAME Rust_Crates
        COMMAND ${_cargo_env} "${MARATHON_CARGO}" test --workspace ${_cargo_flags}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
endif()
