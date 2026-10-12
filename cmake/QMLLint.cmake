# QMLLint.cmake - Build-time QML validation
# This module integrates qmllint into the CMake build process to catch QML errors before runtime

# Find qmllint executable (Fedora uses qmllint-qt6 or /usr/lib64/qt6/bin/qmllint)
find_program(QMLLINT_EXECUTABLE
    NAMES qmllint-qt6 qmllint
    PATHS
        /usr/lib64/qt6/bin
        ${Qt6_DIR}/../../../bin
        ${Qt6_DIR}/../../../libexec/qt6/bin
        /opt/homebrew/opt/qt@6/bin
        /usr/bin
        /usr/local/bin
    DOC "Path to qmllint executable"
)

if(NOT QMLLINT_EXECUTABLE)
    message(WARNING "qmllint not found - QML validation will be skipped. Install Qt6 QmlTools to enable.")
    set(QMLLINT_AVAILABLE FALSE)
else()
    message(STATUS "Found qmllint: ${QMLLINT_EXECUTABLE}")
    set(QMLLINT_AVAILABLE TRUE)
endif()

# Function to add qmllint validation target
# Usage: add_qmllint_target(target_name qml_files_list)
function(add_qmllint_target target_name)
    if(NOT QMLLINT_AVAILABLE)
        return()
    endif()

    set(qml_files ${ARGN})
    
    # Filter out non-QML files (like qmldir)
    list(FILTER qml_files INCLUDE REGEX "\\.qml$")
    
    if(NOT qml_files)
        return()
    endif()

    # Build import paths for qmllint
    set(import_paths "")
    
    # Add Qt6 QML import path
    if(TARGET Qt6::Qml)
        get_target_property(qt_qml_import_path Qt6::Qml IMPORTED_LOCATION)
        if(qt_qml_import_path)
            get_filename_component(qt_qml_path ${qt_qml_import_path} DIRECTORY)
            get_filename_component(qt_qml_path ${qt_qml_path} DIRECTORY)
            list(APPEND import_paths "${qt_qml_path}/qml")
        endif()
    endif()
    
    if(EXISTS "${CMAKE_BINARY_DIR}/shell/qml")
        list(APPEND import_paths "${CMAKE_BINARY_DIR}/shell/qml")
    endif()
    
    # Add MarathonOS.Shell import path (for shell QML files)
    # Shell modules are in shell/qml/ directory
    if(EXISTS "${CMAKE_SOURCE_DIR}/shell/qml")
        list(APPEND import_paths "${CMAKE_SOURCE_DIR}/shell/qml")
    endif()
    
    # Also check if shell is in a subdirectory relative to current source
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../shell/qml")
        list(APPEND import_paths "${CMAKE_CURRENT_SOURCE_DIR}/../shell/qml")
    endif()
    
    # If we're in shell directory, add its qml directory
    if(CMAKE_CURRENT_SOURCE_DIR MATCHES "shell")
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/qml")
            list(APPEND import_paths "${CMAKE_CURRENT_SOURCE_DIR}/qml")
        endif()
    endif()
    
    # Remove duplicates while preserving order
    if(import_paths)
        list(REMOVE_DUPLICATES import_paths)
    endif()
    
    # Debug: log import paths when CMAKE_VERBOSE_MAKEFILE is set
    if(CMAKE_VERBOSE_MAKEFILE)
        message(STATUS "[qmllint] Import paths for ${target_name}:")
        foreach(path ${import_paths})
            message(STATUS "  - ${path}")
        endforeach()
    endif()
    
    # Build QML_IMPORT_PATH environment variable
    string(REPLACE ";" ":" import_path_env "${import_paths}")
    if(NOT import_path_env STREQUAL "")
        set(env_vars "QML_IMPORT_PATH=${import_path_env}")
    else()
        set(env_vars "")
    endif()

    # Create a custom target that runs qmllint
    # Check if target already exists to avoid duplicates
    if(NOT TARGET ${target_name}_qmllint)
        set(qmllint_dependencies "")
        if(TARGET marathon-shell)
            list(APPEND qmllint_dependencies marathon-shell)
        endif()
        
        add_custom_target(${target_name}_qmllint
            COMMAND ${CMAKE_COMMAND} -E echo "🔍 Running qmllint validation for ${target_name}..."
            COMMAND ${CMAKE_COMMAND} -E echo "   Import paths: ${import_path_env}"
            COMMAND ${CMAKE_COMMAND} -E env ${env_vars}
                ${QMLLINT_EXECUTABLE}
                ${qml_files}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            COMMENT "Validating QML files with qmllint"
            VERBATIM
            DEPENDS ${qmllint_dependencies}
        )

        # Make the main target depend on qmllint validation
        if(TARGET ${target_name})
            add_dependencies(${target_name} ${target_name}_qmllint)
        endif()
    endif()
    
    # Note: qmllint exits with non-zero code only on errors, not warnings
    # Warnings are shown but don't fail the build unless configured in .qmllint.ini
endfunction()

# Function to validate QML files in a directory
# Usage: validate_qml_directory(target_name directory_path)
function(validate_qml_directory target_name directory_path)
    if(NOT QMLLINT_AVAILABLE)
        return()
    endif()

    # Find all QML files in the directory
    file(GLOB_RECURSE qml_files "${directory_path}/*.qml")
    
    if(NOT qml_files)
        return()
    endif()

    # Build import paths (same as above)
    set(import_paths "")
    if(TARGET Qt6::Qml)
        get_target_property(qt_qml_import_path Qt6::Qml IMPORTED_LOCATION)
        if(qt_qml_import_path)
            get_filename_component(qt_qml_path ${qt_qml_import_path} DIRECTORY)
            get_filename_component(qt_qml_path ${qt_qml_path} DIRECTORY)
            list(APPEND import_paths "${qt_qml_path}/qml")
        endif()
    endif()
    
    string(REPLACE ";" ":" import_path_env "${import_paths}")

    # Create validation target
    # Check if target already exists to avoid duplicates
    if(NOT TARGET ${target_name}_qmllint)
        add_custom_target(${target_name}_qmllint
            COMMAND ${CMAKE_COMMAND} -E echo "🔍 Running qmllint validation for ${target_name}..."
            COMMAND ${CMAKE_COMMAND} -E env QML_IMPORT_PATH=${import_path_env}
                ${QMLLINT_EXECUTABLE}
                ${qml_files}
            WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
            COMMENT "Validating QML files in ${directory_path} with qmllint"
            VERBATIM
        )

        # Make the main target depend on validation
        if(TARGET ${target_name})
            add_dependencies(${target_name} ${target_name}_qmllint)
        endif()
    endif()
endfunction()


