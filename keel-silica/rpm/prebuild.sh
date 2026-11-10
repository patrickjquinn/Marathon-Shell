#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Pre-build hook for tools/build/sdk/build-rpms.sh (tools/build/sdk/README.md,
# "Per-spec hooks and specs.conf"): run from the repository root with the
# spec as $1. The Silica module needs its CXX-Qt native part, staged in
# target/keel-native (specs.conf passes it as keel_native_dir).
set -euo pipefail
case "$1" in
    */shipwright-keel-silica.spec)
        keel/rpm/build-native.sh --target-name "${SAILFISH_TARGET:-SailfishOS-5.2.0.15-aarch64}" target/keel-native ;;
esac
