# Maps App - Navigation and location services

set(APP_NAME maps)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    src/mapsbridge.cpp
    src/mapsbridge.h
    src/valhallaroutingclient.cpp
    src/valhallaroutingclient.h
    # Future: src/geocoder.cpp
)

# Voice (Piper / QTextToSpeech) is optional. If qt6-qtspeech-devel
# isn't installed, skip the voice client entirely — Maps still ships,
# turn-by-turn just has no spoken cues. The marathon-image build pulls
# qt6-qtspeech + qt6-qtspeech-speechd so production has voice.
find_package(Qt6 6.4 COMPONENTS TextToSpeech)
if(TARGET Qt6::TextToSpeech)
    list(APPEND SOURCES src/voiceclient.cpp src/voiceclient.h)
    set(MAPS_HAS_VOICE TRUE)
endif()

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Maps"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    SOURCES ${SOURCES}
)

# Link Positioning for GPS/location fallback (QtLocation Map is replaced
# by a WebEngineView + MapLibre GL JS render, but PositionSource is still
# the no-Geoclue fallback path).
find_package(Qt6 COMPONENTS Positioning)
if(TARGET Qt6::Positioning)
    target_link_libraries(${APP_NAME} PRIVATE Qt6::Positioning)
endif()

# WebEngine + WebChannel power the MapLibre GL JS basemap render and
# the JS↔QML bridge. Required (not optional) — Maps cannot render its
# basemap without them. Marathon-image must ship qt6-qtwebengine +
# qt6-qtwebchannel. Network is for the Valhalla routing HTTP call.
# Multimedia + TextToSpeech power the nav voice client (Piper via
# subprocess + WAV playback, or QTextToSpeech fallback through
# speech-dispatcher → espeak-ng).
find_package(Qt6 REQUIRED COMPONENTS WebEngineQuick WebChannel WebChannelQuick Network)
target_link_libraries(${APP_NAME} PRIVATE
    Qt6::WebEngineQuick Qt6::WebChannel Qt6::WebChannelQuick Qt6::Network)
if(MAPS_HAS_VOICE)
    find_package(Qt6 REQUIRED COMPONENTS Multimedia)
    target_link_libraries(${APP_NAME} PRIVATE Qt6::TextToSpeech Qt6::Multimedia)
    target_compile_definitions(${APP_NAME} PRIVATE MAPS_HAS_VOICE)
    message(STATUS "Maps: voice client enabled (Qt6::TextToSpeech found)")
else()
    message(STATUS "Maps: voice client disabled (install qt6-qtspeech-devel to enable)")
endif()

# Web assets (Leaflet JS/CSS, marker PNGs, HTML harness, license) are
# loaded by WebEngineView from the app's install root via
# MARATHON_APP_PATH. They live under <app>/web/ at install time.
# Switched from MapLibre GL JS to Leaflet 1.9 because QtWebEngine on
# Librem 5 / etnaviv has --use-gl=disabled (no Mesa etnaviv_gbm, no
# SwiftShader) so WebGL is unavailable. Leaflet renders to Canvas2D.
install(DIRECTORY web
    DESTINATION "${MARATHON_APPS_DIR}/${APP_NAME}"
    FILES_MATCHING
        PATTERN "*.html"
        PATTERN "*.js"
        PATTERN "*.css"
        PATTERN "*.json"
        PATTERN "*.png"
        PATTERN "*.txt")
