#!/bin/bash
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Builds Pacific's WebKit (README.md, "Our own build"):
#
#   shoal/pacific/engine/build/build.sh <workdir> source
#   shoal/pacific/engine/build/build.sh <workdir> generate|use|lto [jobs]
#   shoal/pacific/engine/build/build.sh <workdir> bolt-instrument|bolt
#   shoal/pacific/engine/build/build.sh <workdir> tarball|install
#
# source:   WPE WebKit 2.54.2 with Atlantic's patch stack (atlantic-engine
#           a91f8ec, the series in its scripts/patches.sh) and ours
#           (patches/*.patch, in name order). patches/atlantic/<name>
#           replaces Atlantic's patch of that name, rebased onto this
#           WebKit; an empty one skips it (upstream has it now). No fuzz
#           (-F0): a patch whose context changed fails rather than land in
#           the wrong place.
#           PACIFIC_SRC_DIR names the source directory under <workdir>/src
#           (default wpewebkit-<version>): clang names a file's static
#           functions in a PGO profile by its path, so building with a
#           profile trained on an older WebKit wants that one's directory
#           name (README.md, "Building it").
# generate: the PGO-instrumented engine (pgo-train.sh runs it on a phone).
# use:      the release engine: -fprofile-use with <workdir>/pgo/pacific.profdata,
#           ThinLTO, relocations kept for BOLT.
# lto:      as use without a profile (the A/B baseline for PGO).
# bolt-instrument: the release libWPEWebKit with BOLT's counters, for a
#           training run on the phone (pgo-train.sh); its .fdata files merged
#           with merge-fdata into <workdir>/pgo/bolt.fdata.
# bolt:     llvm-bolt over libWPEWebKit with <workdir>/pgo/bolt.fdata.
# tarball:  <workdir>/pacific-webkit-2.54.2-aarch64.tar.xz for the engine spec.
# install:  copies it into the native build containers (tools/build/native)
#           and the engine mirror they are given.
#
# Needs make-sysroot.sh first. One heavy job at a time: the build container
# is capped at PACIFIC_BUILD_MEMORY (default 13g) plus swap up to
# PACIFIC_BUILD_SWAP (default 16g) and five compile jobs. On the 15 GB
# workstation with other work running, 13g let the host itself thrash and
# lock up (2026-10-18, a PGO use build): there use PACIFIC_BUILD_MEMORY=9g
# PACIFIC_BUILD_SWAP=9g and 3 jobs, so the container is killed instead.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=$(realpath -m "${1:?usage: build.sh <workdir> source|generate|use|lto|bolt|tarball|install [jobs]}")
step=${2:?step}
atlantic_commit=a91f8ecdea2e4fe8fa017d6a28503a4d01edf381
webkit_version=2.54.2
# As published in wpewebkit.org/releases/wpewebkit-2.54.2.tar.xz.sums and on
# the release page; the .asc is signed by Adrián Pérez de Castro's key
# 5AA3 BC33 4FD7 E336 9E7C 77B2 91C5 59DB E4C9 123B.
webkit_sha256=f3284e19e47fcb5ac8c63c2e1c113dbd65b2423eb8a545f5b345707829004f56
src_dir=${PACIFIC_SRC_DIR:-wpewebkit-$webkit_version}
image=localhost/shipwright-webkit-builder:f44
# PACIFIC_CPU=armv8.0 builds for the Xperia 10 II (pacific-toolchain.cmake),
# into a workdir of its own; its tarball is named -armv8.0.
cpu=${PACIFIC_CPU:-armv8.2}
suffix=; [ "$cpu" = armv8.2 ] || suffix=-$cpu
run() { podman run --rm --memory "${PACIFIC_BUILD_MEMORY:-13g}" --memory-swap "${PACIFIC_BUILD_SWAP:-16g}" -e PACIFIC_CPU="$cpu" -e PACIFIC_SRC_DIR="$src_dir" -v "$W":/w:Z -v "$here":/cfg:ro,Z "$image" "$@"; }

case $step in
source)
    podman image exists "$image" || podman build -t "$image" "$here"
    [ -d "$W/atlantic" ] || git clone -q --filter=blob:none https://github.com/specsierra/atlantic-engine.git "$W/atlantic"
    git -C "$W/atlantic" -c advice.detachedHead=false checkout -q "$atlantic_commit"
    tarball=$W/wpewebkit-$webkit_version.tar.xz
    [ -f "$tarball" ] || curl -fsSL -o "$tarball" https://wpewebkit.org/releases/wpewebkit-$webkit_version.tar.xz
    echo "$webkit_sha256  $tarball" | sha256sum -c --quiet -
    rm -rf "$W/src"; mkdir -p "$W/src"; tar -xf "$tarball" -C "$W/src"
    [ "$src_dir" = "wpewebkit-$webkit_version" ] || mv "$W/src/wpewebkit-$webkit_version" "$W/src/$src_dir"
    cd "$W/src/$src_dir"
    for p in $(sed -n '/WEBKIT_SOURCE_PATCHES=(/,/^)/p' "$W/atlantic/scripts/patches.sh" | grep -oE 'patches/webkit/[^"]+'); do
        o=$here/patches/atlantic/${p##*/}
        if [ ! -e "$o" ]; then
            patch -p1 -s -F0 --no-backup-if-mismatch < "$W/atlantic/$p"
        elif [ -s "$o" ]; then
            echo "== Atlantic's ${p##*/}: ours, rebased (patches/atlantic)"
            patch -p1 -s -F0 --no-backup-if-mismatch < "$o"
        else
            echo "== Atlantic's ${p##*/}: skipped (patches/atlantic)"
        fi
    done
    for p in "$here"/patches/*.patch; do
        [ -f "$p" ] && patch -p1 -s -F0 --no-backup-if-mismatch < "$p"
    done
    echo "== source ready: $W/src/$src_dir (WebKit $webkit_version)" ;;
generate|use|lto)
    mkdir -p "$W/ccache" "$W/pgo"
    [ "$step" != use ] || [ -f "$W/pgo/pacific.profdata" ] || { echo "no $W/pgo/pacific.profdata" >&2; exit 1; }
    run bash /cfg/build-webkit.sh "$step" "${3:-5}" ;;
bolt-instrument)
    # The release library with BOLT's counters, for a training run on the
    # phone (pgo-train.sh with PACIFIC_BOLT_DUMP and the library in place of
    # the release one), and bolt-write.c (libpacific-boltwrite.so), which
    # writes each process's counts every 5 s: BOLT's own timed dump cannot
    # keep a file per process, and WebKit SIGKILLs its helpers before any exit
    # handler runs. Prints PACIFIC_BOLT_DUMP. Merge the .fdata files into
    # <workdir>/pgo/bolt.fdata (merge-fdata), then run `bolt`.
    run bash -c '
        set -e; lib=$(ls /w/stage-use/opt/pacific/lib/libWPEWebKit-2.0.so.1.*.* | grep -v -e prebolt -e instrumented)
        llvm-bolt "$lib" -o "$lib.instrumented" -instrument \
            -instrumentation-file=/tmp/pacific-bolt-unused.fdata 2>&1 | tail -3
        g=$(ls -d /w/sysroot/usr/lib64/gcc/aarch64-meego-linux-gnu/* | head -1)
        clang --target=aarch64-linux-gnu --sysroot=/w/sysroot --gcc-install-dir=$g -fuse-ld=lld \
            -shared -fPIC -O2 -o /w/libpacific-boltwrite.so /cfg/bolt-write.c -lpthread
        # LLVM 22 keeps none of the runtime'"'"'s own symbols in the output: the
        # runtime is placed whole, so the dump is at DT_FINI (__bolt_instr_fini)
        # moved by the two functions'"'"' offsets in libbolt_rt_instr.a.
        rt=$(ls /usr/lib64/libbolt_rt_instr.a /usr/lib*/llvm*/lib*/libbolt_rt_instr.a 2>/dev/null | head -1)
        off() { llvm-nm "$rt" | awk -v s="$1" "\$3 == s {print \$1}"; }
        fini=$(llvm-readelf -d "$lib.instrumented" | awk "/\(FINI\)/ {print \$3}")
        printf "PACIFIC_BOLT_DUMP=0x%x\n" $(( fini - 0x$(off __bolt_instr_fini) + 0x$(off __bolt_instr_data_dump) ))' ;;
bolt)
    run bash -c '
        set -e; lib=$(ls /w/stage-use/opt/pacific/lib/libWPEWebKit-2.0.so.1.*.* | grep -v -e prebolt -e instrumented)
        cp "$lib" "$lib.prebolt"
        llvm-bolt "$lib.prebolt" -o "$lib" -data=/w/pgo/bolt.fdata -reorder-blocks=ext-tsp \
            -reorder-functions=cdsort -split-functions -split-all-cold -icf=1 -use-gnu-stack \
            -dyno-stats 2>&1 | tail -20' ;;
tarball)
    out=$W/pacific-webkit-$webkit_version-aarch64$suffix.tar.xz
    meta=$W/stage-use/opt/pacific/share/build-config
    mkdir -p "$meta"
    cp "$W/build-use/CMakeCache.txt" "$W/build-use/cmakeconfig.h" "$meta/"
    cp "$here/pacific-toolchain.cmake" "$meta/"
    # Symbols and the relocations kept for BOLT are not shipped.
    run sh -c 'for f in /w/stage-use/opt/pacific/lib/libWPEWebKit-2.0.so.1.*.* /w/stage-use/opt/pacific/libexec/wpe-webkit-2.0/* \
        /w/stage-use/opt/pacific/lib/wpe-webkit-2.0/injected-bundle/*.so; do llvm-strip --strip-all "$f"; done'
    tar -C "$W/stage-use" --owner=0 --group=0 --numeric-owner --sort=name --mtime=@0 -cJf "$out" \
        opt/pacific/lib opt/pacific/libexec opt/pacific/include opt/pacific/share
    sha256sum "$out" ;;
install)
    # Into each native build container's kept target/, where fetch-rpms.sh
    # looks first (SHA256SUMS must list it), and into the engine mirror
    # native.sh copies into every container, so a container made later (a
    # new Sailfish release, tools/build/releases) has it too.
    out=$W/pacific-webkit-$webkit_version-aarch64$suffix.tar.xz
    mirror=${PACIFIC_ENGINE_RPMS:-$HOME/.cache/shipwright/atlantic-mirror/aarch64}
    mkdir -p "$mirror"
    cp "$out" "$mirror/"
    for c in $(podman ps --format '{{.Names}} {{.Image}}' | awk '/shipwright-sailfish:/{print $1}'); do
        podman exec "$c" mkdir -p /root/build/target/pacific-engine/rpms
        podman cp "$out" "$c:/root/build/target/pacific-engine/rpms/"
        echo "== $c"
    done
    sha256sum "$out" ;;
*) echo "build.sh: unknown step $step" >&2; exit 1 ;;
esac
