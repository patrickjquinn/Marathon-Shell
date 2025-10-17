# Maps App - Navigation and location services

set(APP_NAME maps)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

set(SOURCES
    # Future: src/locationmanager.cpp
    # Future: src/routingengine.cpp
    # Future: src/geocoder.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Maps"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
    
    # Link Positioning for GPS/location
    find_package(Qt6 COMPONENTS Positioning)
    if(TARGET Qt6::Positioning)
        target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::Positioning)
    endif()
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Maps"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

