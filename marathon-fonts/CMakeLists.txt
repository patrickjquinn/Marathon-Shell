# Source Sans 3 (OFL) standing in for Sailfish's Sail Sans Pro.
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/source-sans-3
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/fonts)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/60-marathon-sail-sans.conf
    DESTINATION ${CMAKE_INSTALL_PREFIX}/share/fontconfig/conf.avail)
install(CODE "file(MAKE_DIRECTORY \"\$ENV{DESTDIR}/etc/fonts/conf.d\")
    file(CREATE_LINK /usr/share/fontconfig/conf.avail/60-marathon-sail-sans.conf
         \"\$ENV{DESTDIR}/etc/fonts/conf.d/60-marathon-sail-sans.conf\" SYMBOLIC)")
