# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
# Checks the generated sailfishapp.pc with pkg-config itself.
find_program(PKG_CONFIG pkg-config REQUIRED)
get_filename_component(_dir "${PC_FILE}" DIRECTORY)
set(ENV{PKG_CONFIG_PATH} "${_dir}:$ENV{PKG_CONFIG_PATH}")
execute_process(COMMAND ${PKG_CONFIG} --libs --cflags sailfishapp
                OUTPUT_VARIABLE _out RESULT_VARIABLE _rc OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "pkg-config failed on ${PC_FILE}")
endif()
if(NOT _out MATCHES "-l${EXPECT_LIB}" OR NOT _out MATCHES "-I[^ ]*/keel/sailfishapp")
    message(FATAL_ERROR "unexpected pkg-config output: ${_out}")
endif()
message(STATUS "pkg-config sailfishapp: ${_out}")
