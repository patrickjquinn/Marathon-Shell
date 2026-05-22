# MarathonUI.Theme module

set(THEME_QML_FILES
    MColors.qml
    MTypography.qml
    MSpacing.qml
    MRadius.qml
    MElevation.qml
    MMotion.qml
)

# Mark singletons
set_source_files_properties(${THEME_QML_FILES} PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt6_add_qml_module(marathon-ui-theme
    URI MarathonUI.Theme
    VERSION 2.0
    QML_FILES ${THEME_QML_FILES}
    RESOURCES
        halo-teal.svg
        fonts/Sora.ttf
        fonts/JetBrainsMono-Medium.ttf
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/MarathonUI/Theme
)

# Add qmllint validation target - runs BEFORE building
if(QMLLINT_AVAILABLE)
    add_qmllint_target(marathon-ui-theme ${THEME_QML_FILES})
endif()

install(TARGETS marathon-ui-theme
    LIBRARY DESTINATION ${MARATHON_UI_DIR}/Theme
    RUNTIME DESTINATION ${MARATHON_UI_DIR}/Theme
)

install(FILES
    ${CMAKE_BINARY_DIR}/MarathonUI/Theme/qmldir
    ${CMAKE_BINARY_DIR}/MarathonUI/Theme/marathon-ui-theme.qmltypes
    DESTINATION ${MARATHON_UI_DIR}/Theme
)

install(FILES ${THEME_QML_FILES}
    DESTINATION ${MARATHON_UI_DIR}/Theme
)

# halo-teal.svg is listed in qt6_add_qml_module's RESOURCES so it lands
# in the plugin's compiled-in qrc. But MHaloedDisplay's Image element
# loaded early on shell startup couldn't open the qrc URL — the plugin
# .so registers its resources at dlopen, and there's a window where
# the QML engine has resolved the Image source before the resource
# bundle is live. Ship the file on disk too so the same QML can load
# it as a plain file URL when the qrc isn't yet ready. Symptom on
# r80-r90 boot logs: "QML Image: Cannot open: qrc:/qt/qml/MarathonUI/
# Theme/halo-teal.svg". MHaloedDisplay now resolves through the file
# URL (Qt.resolvedUrl resolves both at runtime).
install(FILES halo-teal.svg
    DESTINATION ${MARATHON_UI_DIR}/Theme
)

install(FILES
    fonts/Sora.ttf
    fonts/JetBrainsMono-Medium.ttf
    DESTINATION ${MARATHON_UI_DIR}/Theme/fonts
)

# Also install Sora + JetBrains Mono into the system fonts directory so
# fontconfig finds them via fc-match. Without this, anything that goes
# through fontconfig (greetd, console messages, foot/alacritty before
# the user has any font config, third-party apps) falls back to Noto
# Sans / DejaVu. Sora.ttf is the same file shipped via the QML qrc —
# duplicated here so the system can resolve it by family name.
install(FILES
    fonts/Sora.ttf
    fonts/JetBrainsMono-Medium.ttf
    DESTINATION share/fonts/marathon
)
