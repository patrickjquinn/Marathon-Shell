# Browser App - Pure QML for now

set(APP_NAME browser)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
)

# C++ sources for browser plugin (future)
set(SOURCES
    # Future: src/browserengine.cpp
    # Future: src/downloadmanager.cpp
    # Future: src/bookmarkmanager.cpp
)

if(SOURCES)
    add_marathon_app(${APP_NAME}
        HAS_CPP
        URI "MarathonApp.Browser"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
        SOURCES ${SOURCES}
    )
    
    # Link WebEngine if available
    if(HAVE_WEBENGINE)
        target_link_libraries(${APP_NAME}-plugin PRIVATE Qt6::WebEngineQuick)
        target_compile_definitions(${APP_NAME}-plugin PRIVATE HAVE_WEBENGINE)
    endif()
else()
    add_marathon_app(${APP_NAME}
        URI "MarathonApp.Browser"
        VERSION "1.0"
        QML_FILES ${QML_FILES}
    )
endif()

