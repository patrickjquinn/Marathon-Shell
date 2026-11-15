#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Puts the engine RPMs this alpha repackages (Atlantic's build 746.1, listed
# with their SHA-256 in SHA256SUMS next to this script) into a directory:
#
#   shoal/pacific/engine/fetch-rpms.sh <directory>
#
# Sources, in order: the directory itself (kept between builds: the native
# build container keeps target/), PACIFIC_ENGINE_RPMS (a local mirror, e.g.
# ~/.cache/shipwright/atlantic-mirror/aarch64), then Atlantic's repository
# (PACIFIC_ENGINE_URL, default below). Every file is checked against
# SHA256SUMS; a mismatch fails the build rather than ship an unknown binary.
#
# Of our own WebKit builds (pacific-webkit-*), only the one for PACIFIC_CPU
# (armv8.2, the default, or armv8.0; build/build.sh names them) is needed;
# lines starting with # are notes.
#
# Then the source files listed in SOURCES (enchant and the spell-checking
# dictionaries: sha256, name, url) go to <directory>/../sources, checked the
# same way. PACIFIC_ENGINE_SOURCES names a local directory to take them from.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
dest=${1:?usage: fetch-rpms.sh <directory>}
url=${PACIFIC_ENGINE_URL:-https://specsierra.github.io/atlantic-engine/aarch64}
cpu=${PACIFIC_CPU:-armv8.2}
suffix=; [ "$cpu" = armv8.2 ] || suffix=-$cpu
webkit=pacific-webkit-2.54.2-aarch64$suffix.tar.xz
grep -q "  $webkit\$" "$here/SHA256SUMS" || {
    echo "fetch-rpms.sh: SHA256SUMS has no line for $webkit (PACIFIC_CPU=$cpu); build it (build/build.sh) and add the sum it prints" >&2
    exit 1
}
mkdir -p "$dest"
while read -r sum name; do
    [ -n "$name" ] || continue
    case "$sum" in '#'*) continue ;; esac
    case "$name" in pacific-webkit-*) [ "$name" = "$webkit" ] || continue ;; esac
    if [ -f "$dest/$name" ] && echo "$sum  $dest/$name" | sha256sum -c - >/dev/null 2>/dev/null; then
        continue
    fi
    if [ -n "${PACIFIC_ENGINE_RPMS:-}" ] && [ -f "$PACIFIC_ENGINE_RPMS/$name" ]; then
        cp "$PACIFIC_ENGINE_RPMS/$name" "$dest/$name.part"
    elif [ "${name#pacific-webkit-}" != "$name" ]; then
        # Our own WebKit build (build/build.sh tarball) is not downloadable:
        # build.sh install copies it into each native build container.
        echo "fetch-rpms.sh: $name is missing; run shoal/pacific/engine/build/build.sh <workdir> install" >&2
        exit 1
    else
        echo "fetch-rpms.sh: downloading $name" >&2
        curl -fsSL --retry 3 -o "$dest/$name.part" "$url/$name"
    fi
    if ! echo "$sum  $dest/$name.part" | sha256sum -c - >/dev/null; then
        echo "fetch-rpms.sh: $name does not match SHA256SUMS; refusing it" >&2
        rm -f "$dest/$name.part"
        exit 1
    fi
    mv "$dest/$name.part" "$dest/$name"
done < "$here/SHA256SUMS"

sources=$(dirname "$dest")/sources
mkdir -p "$sources"
grep -v '^#' "$here/SOURCES" | while read -r sum name src; do
    [ -n "$name" ] || continue
    if [ -f "$sources/$name" ] && echo "$sum  $sources/$name" | sha256sum -c - >/dev/null 2>/dev/null; then
        continue
    fi
    if [ -n "${PACIFIC_ENGINE_SOURCES:-}" ] && [ -f "$PACIFIC_ENGINE_SOURCES/$name" ]; then
        cp "$PACIFIC_ENGINE_SOURCES/$name" "$sources/$name.part"
    else
        curl -fsSL --retry 3 -o "$sources/$name.part" "$src"
    fi
    if ! echo "$sum  $sources/$name.part" | sha256sum -c - >/dev/null; then
        echo "fetch-rpms.sh: $name does not match SOURCES; refusing it" >&2
        rm -f "$sources/$name.part"
        exit 1
    fi
    mv "$sources/$name.part" "$sources/$name"
done
echo "$dest"
