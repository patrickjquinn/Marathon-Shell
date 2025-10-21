# Additional clean files
cmake_minimum_required(VERSION 3.16)

if("${CONFIG}" STREQUAL "" OR "${CONFIG}" STREQUAL "Release")
  file(REMOVE_RECURSE
  "terminal/CMakeFiles/terminal-plugin_autogen.dir/AutogenUsed.txt"
  "terminal/CMakeFiles/terminal-plugin_autogen.dir/ParseCache.txt"
  "terminal/CMakeFiles/terminal-pluginplugin_autogen.dir/AutogenUsed.txt"
  "terminal/CMakeFiles/terminal-pluginplugin_autogen.dir/ParseCache.txt"
  "terminal/terminal-plugin_autogen"
  "terminal/terminal-pluginplugin_autogen"
  )
endif()
