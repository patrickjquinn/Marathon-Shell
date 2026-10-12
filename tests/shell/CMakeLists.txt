# Marathon Shell Component Test Suite

cmake_minimum_required(VERSION 3.21)
enable_testing()

find_package(Qt6 REQUIRED COMPONENTS Test Core Gui Qml Sql)

# Router tests (pure state machine, zero deps)
add_executable(test_shell_router
    test_router.cpp
    ../../shell/src/services/router.cpp
)
target_link_libraries(test_shell_router Qt6::Test Qt6::Core Qt6::Qml)
target_include_directories(test_shell_router PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_Router COMMAND test_shell_router)

# AppModel tests (data model with validation)
add_executable(test_shell_appmodel
    test_appmodel.cpp
    ../../shell/src/models/appmodel.cpp
    ../../marathon-core/src/marathonappregistry.cpp
)
target_link_libraries(test_shell_appmodel Qt6::Test Qt6::Core)
target_include_directories(test_shell_appmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/marathon-core/src
)
add_test(NAME Shell_AppModel COMMAND test_shell_appmodel)

# NotificationModel tests (data model, add/dismiss/read)
add_executable(test_shell_notificationmodel
    test_notificationmodel.cpp
    ../../shell/src/models/notificationmodel.cpp
    ../../shell/src/dbus/notificationdatabase.cpp
)
target_link_libraries(test_shell_notificationmodel Qt6::Test Qt6::Core Qt6::Sql Qt6::Qml)
target_include_directories(test_shell_notificationmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
    ${CMAKE_SOURCE_DIR}/shell/src
)
add_test(NAME Shell_NotificationModel COMMAND test_shell_notificationmodel)

# TaskModel tests (data model, launch/close/update)
add_executable(test_shell_taskmodel
    test_taskmodel.cpp
    ../../shell/src/models/taskmodel.cpp
)
target_link_libraries(test_shell_taskmodel Qt6::Test Qt6::Core Qt6::Gui Qt6::Qml)
target_include_directories(test_shell_taskmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
)
add_test(NAME Shell_TaskModel COMMAND test_shell_taskmodel)

# Ambience derivation from the wallpaper
add_executable(test_shell_ambiencederivation
    test_ambiencederivation.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambiencederivation Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambiencederivation PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_AmbienceDerivation COMMAND test_shell_ambiencederivation)

# Ambience service: wallpaper seed and debounced publishing
add_executable(test_shell_ambienceservice
    test_ambienceservice.cpp
    ../../shell/src/services/ambienceservice.cpp
    ../../shell/src/services/ambiencederivation.cpp
)
target_link_libraries(test_shell_ambienceservice Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_ambienceservice PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/services
)
add_test(NAME Shell_AmbienceService COMMAND test_shell_ambienceservice)

# Which keys the compositor keeps for system navigation
add_executable(test_shell_keyrouting test_keyrouting.cpp)
target_link_libraries(test_shell_keyrouting Qt6::Test Qt6::Core)
target_include_directories(test_shell_keyrouting PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/wayland)
add_test(NAME Shell_KeyRouting COMMAND test_shell_keyrouting)

# Nemo.Ngf events to vibration patterns
add_executable(test_shell_ngfevents test_ngfevents.cpp)
target_link_libraries(test_shell_ngfevents Qt6::Test Qt6::Core)
target_include_directories(test_shell_ngfevents PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_NgfEvents COMMAND test_shell_ngfevents)

# Nemo.Ngf backend (com.nokia.NonGraphicFeedback1)
add_executable(test_shell_ngfservice test_ngfservice.cpp ../../shell/src/services/ngfservice.cpp)
target_link_libraries(test_shell_ngfservice Qt6::Test Qt6::Core)
target_include_directories(test_shell_ngfservice PRIVATE ${CMAKE_SOURCE_DIR}/shell/src/services)
add_test(NAME Shell_NgfService COMMAND test_shell_ngfservice)
