# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Pacific engine: Fedora clang 22 + lld against a Sailfish OS sysroot.
# PACIFIC_CPU selects the processor: armv8.2 (default), the Jolla Phone's
# Cortex-A78/A55 (armv8.2-a with LSE atomics, RCpc, dot product and FP16);
# armv8.0, the Xperia 10 II's Kryo 260 (Cortex-A73/A53: armv8-a with CRC and
# crypto, no LSE). PACIFIC_PGO selects the profile stage.
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT /w/sysroot)
set(CMAKE_FIND_ROOT_PATH /w/sysroot/opt/pacific /w/sysroot/opt/woff2)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_AR llvm-ar)
set(CMAKE_NM llvm-nm)
set(CMAKE_RANLIB llvm-ranlib)

# The sysroot's GCC (13.4.0 on 5.2), for its libstdc++ and crt files.
file(GLOB _gcc_dirs /w/sysroot/usr/lib64/gcc/aarch64-meego-linux-gnu/*)
list(GET _gcc_dirs 0 _gcc_dir)
set(_gcc "--gcc-install-dir=${_gcc_dir}")
if(PACIFIC_CPU STREQUAL "armv8.0")
  set(_cpu "-march=armv8-a+crc+crypto -mtune=cortex-a73")
else()
  set(_cpu "-march=armv8.2-a+crypto+rcpc+dotprod+fp16 -mtune=cortex-a78")
endif()
set(_common "${_gcc} ${_cpu} -fno-semantic-interposition -ffunction-sections -fdata-sections -fno-plt")

set(_pgo "")
if(PACIFIC_PGO STREQUAL "generate")
  set(_pgo "-fprofile-generate -mllvm -vp-counters-per-site=3")
elseif(PACIFIC_PGO STREQUAL "use")
  set(_pgo "-fprofile-use=/w/pgo/pacific.profdata -Wno-backend-plugin -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date")
endif()

set(CMAKE_C_FLAGS_INIT "${_common} ${_pgo}")
set(CMAKE_CXX_FLAGS_INIT "${_common} ${_pgo}")
set(_ld "-fuse-ld=lld ${_gcc} ${_pgo} -Wl,-O2 -Wl,--gc-sections -Wl,-z,pack-relative-relocs -Wl,--hash-style=gnu -Wl,--as-needed")
if(PACIFIC_BOLT)
  set(_ld "${_ld} -Wl,--emit-relocs")
endif()
# ThinLTO's optimisation and code generation at O3 (lld's default is O2 for
# both): the release builds only, the instrumented one has no LTO.
if(NOT PACIFIC_PGO STREQUAL "generate")
  set(_ld "${_ld} -Wl,--lto-O3 -Wl,--lto-CGO3")
endif()
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_ld}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_ld}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_ld}")
