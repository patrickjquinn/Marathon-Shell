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
target_link_libraries(test_shell_notificationmodel Qt6::Test Qt6::Core Qt6::Sql)
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
target_link_libraries(test_shell_taskmodel Qt6::Test Qt6::Core Qt6::Gui)
target_include_directories(test_shell_taskmodel PRIVATE
    ${CMAKE_SOURCE_DIR}/shell/src/models
)
add_test(NAME Shell_TaskModel COMMAND test_shell_taskmodel)
