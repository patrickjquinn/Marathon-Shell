#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Fetches the pinned maliit-framework source (sailfishos-open, branch qt6)
# into target/keel-maliit/ for qt6-sfos-maliit-platforminputcontext.spec,
# and checks it against its SHA-256. Kept between runs.
set -euo pipefail
commit=f5aa5d6e4b1ccfdadb631e5ab88782f8651d3443
sha256=49cc87ded53e98256cf7ca8f1de87036c58b3b52b3dad21b76f3a574add84fa3
out=target/keel-maliit
tarball=$out/maliit-framework-$commit.tar.gz
mkdir -p "$out"
if ! echo "$sha256  $tarball" | sha256sum -c --quiet - 2>/dev/null; then
    curl -fsSL --retry 3 -o "$tarball.part" \
        "https://codeload.github.com/sailfishos-open/maliit-framework/tar.gz/$commit"
    mv "$tarball.part" "$tarball"
    echo "$sha256  $tarball" | sha256sum -c --quiet - ||
        { echo "prebuild: $tarball does not match its pin" >&2; exit 1; }
fi
