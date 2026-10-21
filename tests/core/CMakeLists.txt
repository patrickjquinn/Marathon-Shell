# Marathon Core Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core DBus Gui Network)

# Permissions1 authorisation: self-only, except Settings

# Marathon.Platform: the runner's service clients under their QML names
find_package(Qt6 REQUIRED COMPONENTS Qml)
add_executable(test_core_platformtypes
    test_platformtypes.cpp
    ../../tools/marathon-app-runner/platformtypes.cpp
)
target_link_libraries(test_core_platformtypes Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_core_platformtypes PRIVATE
    ${CMAKE_SOURCE_DIR}/tools/marathon-app-runner
)
add_test(NAME Core_PlatformTypes COMMAND test_core_platformtypes)

# WAKE_ON_KEY: a key wakes a blanked screen without reaching apps
add_executable(test_core_wakeonkeyfilter
    test_wakeonkeyfilter.cpp
    ../../shell/src/services/wakeonkeyfilter.cpp
)
set_target_properties(test_core_wakeonkeyfilter PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_wakeonkeyfilter Qt6::Test Qt6::Gui Qt6::GuiPrivate)
target_include_directories(test_core_wakeonkeyfilter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_WakeOnKeyFilter COMMAND test_core_wakeonkeyfilter)
set_tests_properties(Core_WakeOnKeyFilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

# Music's MPRIS publisher, on a private session bus
find_program(DBUS_RUN_SESSION dbus-run-session)
if(DBUS_RUN_SESSION)
    find_package(Qt6 REQUIRED COMPONENTS DBus Qml)
    add_executable(test_core_mprisplayer
        test_mprisplayer.cpp
        ../../apps/music/src/MprisPlayer.cpp
        ../../apps/music/src/MprisPlayer.h
    )
    target_link_libraries(test_core_mprisplayer Qt6::Test Qt6::Core Qt6::DBus Qt6::Qml)
    target_include_directories(test_core_mprisplayer PRIVATE ${CMAKE_SOURCE_DIR}/apps/music/src)
    add_test(NAME Core_MprisPlayer COMMAND ${DBUS_RUN_SESSION} -- $<TARGET_FILE:test_core_mprisplayer>)
endif()

# Music album art: embedded art cached to disk, or a cover file beside the track
find_package(Qt6 REQUIRED COMPONENTS Gui Qml)
add_executable(test_core_musicartwork
    test_musicartwork.cpp
    ../../apps/music/src/Artwork.cpp
    ../../apps/music/src/Artwork.h
)
target_link_libraries(test_core_musicartwork Qt6::Test Qt6::Core Qt6::Gui Qt6::Qml)
target_include_directories(test_core_musicartwork PRIVATE ${CMAKE_SOURCE_DIR}/apps/music/src)
add_test(NAME Core_MusicArtwork COMMAND test_core_musicartwork)

# Sound names format locally, shared by the shell and the app runner


# Wake touch hygiene: no touch for 100 ms after wake, none until a fresh one
add_executable(test_core_waketouchfilter
    test_waketouchfilter.cpp
    ../../shell/src/services/waketouchfilter.cpp
)
set_target_properties(test_core_waketouchfilter PROPERTIES AUTOMOC ON)
target_link_libraries(test_core_waketouchfilter Qt6::Test Qt6::Gui Qt6::Qml Qt6::Quick)
target_include_directories(test_core_waketouchfilter PRIVATE ${CMAKE_SOURCE_DIR}/shell/src)
add_test(NAME Core_WakeTouchFilter COMMAND test_core_waketouchfilter)
set_tests_properties(Core_WakeTouchFilter PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
