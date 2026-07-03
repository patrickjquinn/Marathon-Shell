cmake_minimum_required(VERSION 3.10)
project(asyncfutureunittests VERSION 1.0.0 LANGUAGES CXX)

# Specify the C++ standard
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Find the Qt package
#find_package(Qt6 6.5 REQUIRED COMPONENTS Test QuickTest Concurrent Qml Quick)

# Initialize variables to store required Qt components
set(QT_COMPONENTS Test Gui Concurrent Qml Quick QuickTest)

# Attempt to find Qt6 first
find_package(Qt6 6.0 QUIET COMPONENTS ${QT_COMPONENTS})
#find_package(Qt6 6.0 COMPONENTS ${QT_COMPONENTS})

if(Qt6_FOUND)
  message(STATUS "Using Qt6")
else()
  # If Qt6 is not found, attempt to find Qt5
  find_package(Qt5 5.15 REQUIRED COMPONENTS ${QT_COMPONENTS})
  if(Qt5_FOUND)
    message(STATUS "Using Qt5")
  else()
    message(FATAL_ERROR "Neither Qt6 nor Qt5 was found!")
  endif()
endif()

# Add qtshell
add_library(qtshell STATIC
    asyncfutureunittests/qtshell/qtshell.cpp
    asyncfutureunittests/qtshell/qtshell.h
    asyncfutureunittests/qtshell/priv/qtshellmv.cpp
    asyncfutureunittests/qtshell/priv/qtshellpriv.h
    asyncfutureunittests/qtshell/priv/qtshellpriv.cpp
    asyncfutureunittests/qtshell/priv/qtshellrealpath.cpp
)

target_link_libraries(qtshell
    Qt::Core
)

target_include_directories(qtshell PUBLIC asyncfutureunittests/qtshell)

# Add testrunner
add_library(testrunner STATIC
    asyncfutureunittests/testable/automator.cpp
    asyncfutureunittests/testable/automator.h
    asyncfutureunittests/testable/testablefunctions.cpp
    asyncfutureunittests/testable/testablefunctions.h
    asyncfutureunittests/testable/testrunner.cpp
    asyncfutureunittests/testable/testrunner.h
    asyncfutureunittests/testable/priv/objectutils.cpp
    asyncfutureunittests/testable/priv/objectutils.h
    asyncfutureunittests/testable/priv/testableutils.cpp
    asyncfutureunittests/testable/priv/testableutils.h
    asyncfutureunittests/testable/priv/testrunnerwrapper.cpp
    asyncfutureunittests/testable/priv/testrunnerwrapper.h
)

target_link_libraries(testrunner
    Qt::Qml
    Qt::Test
    Qt::QuickTest
    Qt::Quick
    Qt::Core
)

target_include_directories(testrunner PUBLIC asyncfutureunittests/testable)
target_include_directories(testrunner PRIVATE asyncfutureunittests/testable/priv)


# List of source files
set(SOURCE_FILES
    asyncfutureunittests/main.cpp
    asyncfutureunittests/FinishedAndCancelThread.cpp
    asyncfutureunittests/example.cpp
    asyncfutureunittests/bugtests.cpp
    asyncfutureunittests/samplecode.cpp
    asyncfutureunittests/cookbook.cpp
    asyncfutureunittests/testclass.cpp
    asyncfutureunittests/trackingdata.cpp
    asyncfutureunittests/spec.cpp
)

# Define the executable target
add_executable(asyncfutureunittests ${SOURCE_FILES})
set_target_properties(asyncfutureunittests PROPERTIES AUTOMOC TRUE)
set_target_properties(qtshell PROPERTIES AUTOMOC TRUE)
set_target_properties(testrunner PROPERTIES AUTOMOC TRUE)

# Specify the include directories and compile definitions
target_include_directories(asyncfutureunittests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_include_directories(asyncfutureunittests PRIVATE ${CMAKE_SOURCE_DIR})
target_compile_definitions(asyncfutureunittests PRIVATE "SRCDIR=\"${CMAKE_CURRENT_SOURCE_DIR}/\"" "QUICK_TEST_SOURCE_DIR=\"${CMAKE_CURRENT_SOURCE_DIR}/qmltests\"")

# Link against Qt modules and any other dependencies
target_link_libraries(asyncfutureunittests
    PRIVATE
    Qt::Test
    Qt::Concurrent
    Qt::Qml
    qtshell
    testrunner
)

# Additional includes
#include(vendor/vendor.pri)  # You'll have to convert this to CMake too
#include(../../asyncfuture.pri)  # You'll have to convert this to CMake too

# For additional files to be visible in some IDEs
#set(DISTFILES
#    qpm.json
#    ../../README.md
#    ../../.travis.yml
#    ../../qpm.json
#)

# Specify headers for the project
set(HEADERS
    asyncfutureunittests/FinishedAndCancelThread.h
    asyncfutureunittests/example.h
    asyncfutureunittests/testclass.h
    asyncfutureunittests/testfunctions.h
    asyncfutureunittests/bugtests.h
    asyncfutureunittests/samplecode.h
    asyncfutureunittests/cookbook.h
    asyncfutureunittests/trackingdata.h
    asyncfutureunittests/spec.h
    asyncfutureunittests/tools.h
)

# Make headers visible in IDEs
target_sources(asyncfutureunittests PRIVATE ${HEADERS})
