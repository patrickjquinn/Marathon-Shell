set(APP_NAME email)

file(GLOB_RECURSE QML_FILES "${CMAKE_CURRENT_SOURCE_DIR}/*.qml")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Email"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
)

if(HAVE_WEBENGINE)
    target_link_libraries(${APP_NAME} PRIVATE Qt6::WebEngineQuick)
    target_compile_definitions(${APP_NAME} PRIVATE HAVE_WEBENGINE)
endif()
