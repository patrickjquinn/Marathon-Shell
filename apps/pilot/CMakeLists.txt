# Pilot, Marathon's assistant. Its client of pilotd is the runner's
# MarathonOS.Pilot (crates/marathon-app-native/src/pilot.rs).

set(APP_NAME shoal-pilot)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")
set_source_files_properties(components/Conversation.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Pilot"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    # The pages import components/ by directory, which declares the singleton.
    RESOURCES components/qmldir
)

install(FILES shoal-pilot.desktop DESTINATION ${CMAKE_INSTALL_PREFIX}/share/applications)
foreach(_size 86 108 128 172)
    install(FILES icons/${_size}x${_size}/shoal-pilot.png
        DESTINATION ${CMAKE_INSTALL_PREFIX}/share/icons/hicolor/${_size}x${_size}/apps)
endforeach()
