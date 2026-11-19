# Radio: the world's stations on a globe and the phone's FM tuner, through
# marathon-radiod. The globe's shader (shaders/) goes in by convention; its
# land mask is a resource of the module too.

set(APP_NAME radio)

file(GLOB_RECURSE QML_FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/*.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/*.js"
)
list(FILTER QML_FILES EXCLUDE REGEX "/tests/")

add_marathon_app(${APP_NAME}
    URI "MarathonApp.Radio"
    VERSION "1.0"
    QML_FILES ${QML_FILES}
    RESOURCES assets/land.png
)

install_keel_actions(${APP_NAME} keel-actions.json)
