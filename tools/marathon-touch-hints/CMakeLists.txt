# marathon-touch-hints: the touch slop and long press of every Qt app the
# shell starts, Keel or not (QT_QPA_GENERIC_PLUGINS=marathontouch).
find_package(Qt6 REQUIRED COMPONENTS Gui)
qt6_add_plugin(marathon-touch-hints SHARED PLUGIN_TYPE generic CLASS_NAME TouchHints main.cpp)
target_link_libraries(marathon-touch-hints PRIVATE Qt6::Gui)
install(TARGETS marathon-touch-hints LIBRARY DESTINATION ${QT6_INSTALL_PLUGINS}/generic)
