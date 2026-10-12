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

if(BUILD_TESTING)
    add_test(NAME Rust_Crates
        COMMAND ${_cargo_env} "${MARATHON_CARGO}" test --workspace ${_cargo_flags}
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
endif()
