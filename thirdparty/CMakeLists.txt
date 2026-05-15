# Vendored third-party sources used by Marathon-Shell.
#
# Each subdirectory under thirdparty/ is a separate vendored project,
# pulled at a pinned ref and built as a static library or interface
# target. The top-level shell CMake adds whatever subset Marathon
# needs via `add_subdirectory(thirdparty)`.

cmake_minimum_required(VERSION 3.21)

# ── Oxford C-Step-Counter (MIT) ─────────────────────────────────────
# Embeddable step-detection algorithm from Brondin & Nordström, used
# by Marathon's MotionDaemon to derive Move/Exercise/Stand ring data
# from raw accelerometer samples (typically off iio-sensor-proxy or
# /sys/bus/iio/devices/iio:device*). Builds as a static library so
# the algorithm links directly into marathon-shell.
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/oxford-step-counter")
    file(GLOB OXFORD_STEP_COUNTER_SOURCES
        "${CMAKE_CURRENT_SOURCE_DIR}/oxford-step-counter/src/*.c")
    add_library(oxford-step-counter STATIC ${OXFORD_STEP_COUNTER_SOURCES})
    target_include_directories(oxford-step-counter PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/oxford-step-counter/include")
    set_target_properties(oxford-step-counter PROPERTIES
        POSITION_INDEPENDENT_CODE ON
        C_STANDARD 11)
    message(STATUS "Marathon: Oxford C-Step-Counter enabled")
endif()

# ── MapLibre Native Qt (BSD-2 / LGPLv3) ─────────────────────────────
# Vector-tile basemap rendering with a QtLocation Plugin (`name:
# "maplibre"`) the Maps app can drop-replace the stock `osm` plugin
# with. Opt-in because the submodule chain (~700 MB) is heavy and
# only worth pulling when the device build needs vector tiles.
option(MARATHON_WITH_MAPLIBRE "Build vendored maplibre-native-qt" OFF)
if(MARATHON_WITH_MAPLIBRE AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/maplibre-native-qt/CMakeLists.txt")
    add_subdirectory(maplibre-native-qt)
    message(STATUS "Marathon: maplibre-native-qt enabled (vector tiles)")
endif()
