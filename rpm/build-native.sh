#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Cross-compiles Keel's CXX-Qt native part (keel/silica/plugin) for a
# Sailfish target, inside the Sailfish platform SDK container, and stages it
# for shipwright-keel-silica.spec (KEEL_RUST_PREBUILT_DIR):
#   <outdir>/libkeel_silica_native.a and <outdir>/cxxqt-export
#
# The method (qmake stand-in, Qt tools under sb2) is shared by every CXX-Qt
# crate: tools/build/sdk/cxxqt-sailfish.sh. tools/build/sdk/build-rpms.sh
# runs this through keel/rpm/prebuild.sh.
#
# Usage (in the container, from the repository root or a copy of it):
#   keel/rpm/build-native.sh [--target-name SailfishOS-5.2.0.15-aarch64] <outdir>
# Then:
#   mb2 -t SailfishOS-5.2.0.15-aarch64 --snapshot=<you> \
#       -s keel/rpm/shipwright-keel-silica.spec \
#       build -- --define "keel_native_dir <outdir>"
set -euo pipefail

target_args=()
if [ "${1:-}" = "--target-name" ]; then
    target_args=(--target-name "$2")
    shift 2
fi
out=${1:?usage: build-native.sh [--target-name T] <outdir>}
repo=$(cd "$(dirname "$0")/../.." && pwd)
"$repo/tools/build/sdk/cxxqt-sailfish.sh" "${target_args[@]}" \
    "$repo/keel/silica/plugin" "$out"
test -f "$out/libkeel_silica_native.a"
