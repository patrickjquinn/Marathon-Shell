# sailfish-qml: Sailfish's launcher for QML-only apps, on Keel's sailfishapp.
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
    pkg_check_modules(KEEL_SAILFISHAPP QUIET IMPORTED_TARGET keel-sailfishapp)
endif()
if(NOT KEEL_SAILFISHAPP_FOUND)
    message(STATUS "keel-sailfishapp not found - sailfish-qml will not be built")
    return()
endif()

find_package(Qt6 REQUIRED COMPONENTS Gui Quick)
qt6_add_executable(sailfish-qml main.cpp)
target_link_libraries(sailfish-qml PRIVATE Qt6::Gui Qt6::Quick PkgConfig::KEEL_SAILFISHAPP)
install(TARGETS sailfish-qml RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
