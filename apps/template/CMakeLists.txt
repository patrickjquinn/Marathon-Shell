cmake_minimum_required(VERSION 3.16)
project(template VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Quick)

qt_add_qml_module(template
    URI TemplateApp
    VERSION 1.0
    QML_FILES
        TemplateApp.qml
        pages/MainPage.qml
        qmldir
    RESOURCES
        manifest.json
)

set_target_properties(template PROPERTIES
    QT_QML_MODULE_INSTALL_DIR "${CMAKE_INSTALL_PREFIX}/apps/template"
)

install(TARGETS template
    BUNDLE DESTINATION .
    LIBRARY DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template"
    RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template"
)

install(FILES
    manifest.json
    TemplateApp.qml
    qmldir
    DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template"
)

install(DIRECTORY pages/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template/pages"
    FILES_MATCHING PATTERN "*.qml"
)

install(DIRECTORY components/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template/components"
    FILES_MATCHING PATTERN "*.qml"
)

install(DIRECTORY assets/
    DESTINATION "${CMAKE_INSTALL_PREFIX}/apps/template/assets"
)

