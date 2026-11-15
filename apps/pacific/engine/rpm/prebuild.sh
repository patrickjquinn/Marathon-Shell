#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Pre-build hook for tools/build/sdk/build-rpms.sh, run from the repository
# root: puts the engine RPMs the spec repackages into target/pacific-engine/rpms
# (kept between native builds). PACIFIC_ENGINE_RPMS names a local mirror.
set -eu
shoal/pacific/engine/fetch-rpms.sh target/pacific-engine/rpms
