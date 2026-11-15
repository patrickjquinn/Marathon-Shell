#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Spell checking on the development host: builds enchant 2.3.3 (the engine's
# version) into <prefix>/enchant and copies the dictionaries to
# <prefix>/hunspell, plus libvoikko and the Finnish Voikko data in
# <prefix>/voikko, all from shoal/pacific/engine/SOURCES; host-run.sh then
# uses them. Needs gcc, g++, make, python3, unzip, glib2-devel and
# hunspell-devel.
#
#   shoal/pacific/webview/tools/host-enchant.sh <prefix>
set -eu
here=$(cd "$(dirname "$0")" && pwd)
prefix=$(cd "${1:?usage: host-enchant.sh <prefix>}" && pwd)
engine=$here/../../engine
"$engine/fetch-rpms.sh" "$prefix/engine-rpms" >/dev/null
sources=$prefix/sources
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xzf "$sources/libvoikko-4.3.2.tar.gz" -C "$work"
(cd "$work/libvoikko-4.3.2" &&
    ./configure --prefix="$prefix/enchant" --disable-static --disable-hfst --disable-buildtools \
        --with-dictionary-path="$prefix/voikko" >/dev/null &&
    make -j4 >/dev/null 2>&1 && make install >/dev/null 2>&1)
mkdir -p "$prefix/voikko"
(cd "$prefix/voikko" && unzip -o -q "$sources/voikko-fi-dict-5.zip")
tar -xzf "$sources/enchant-2.3.3.tar.gz" -C "$work"
(cd "$work/enchant-2.3.3" &&
    PKG_CONFIG_PATH="$prefix/enchant/lib/pkgconfig" ./configure --prefix="$prefix/enchant" --disable-static \
        --with-hunspell --with-voikko --without-aspell --without-nuspell --without-hspell \
        --with-hunspell-dir="$prefix/hunspell" CPPFLAGS="-I$prefix/enchant/include" >/dev/null &&
    make -j4 >/dev/null 2>&1 && make install >/dev/null 2>&1)
mkdir -p "$prefix/hunspell"
cp "$sources"/*.aff "$sources"/*.dic "$prefix/hunspell/"
echo "$prefix/enchant"
