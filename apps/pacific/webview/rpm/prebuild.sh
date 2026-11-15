#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Pre-build hook for tools/build/sdk/build-rpms.sh, run from the repository
# root: a build prefix (headers, libraries, pkg-config) from the engine RPMs,
# in target/pacific-sdk, for when shipwright-pacific-engine-devel is not
# installed in the build root. PACIFIC_ENGINE_RPMS names a local mirror.
set -eu
shoal/pacific/engine/fetch-rpms.sh target/pacific-engine/rpms >/dev/null
shoal/pacific/webview/tools/sdk-prefix.sh target/pacific-sdk target/pacific-engine/rpms
