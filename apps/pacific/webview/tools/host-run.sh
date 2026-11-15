#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: LGPL-2.1-or-later
#
# Runs a program built against the engine prefix (sdk-prefix.sh) on an aarch64
# Linux host, for development: Fedora's Mesa EGL and Wayland instead of the
# phone's libhybris.
#
#   shoal/pacific/webview/tools/host-run.sh <prefix> <build dir> <command> [args]
#
# Atlantic's engine runs its helper processes from /opt/wpe-sfos (compiled
# in, no override in a release build), so bubblewrap mounts the prefix's
# helpers there in a private mount namespace; nothing is installed on the
# host. ICU 73 (the engine's) must be in <prefix>/icu73, copied from a
# Sailfish OS 5.2 root (README.md "Running on the host").
set -eu
prefix=$(cd "${1:?usage: host-run.sh <prefix> <build dir> <command> [args]}" && pwd)
build=$(cd "${2:?build dir}" && pwd)
shift 2
root=$prefix/root
[ -d "$prefix/icu73" ] || { echo "host-run.sh: $prefix/icu73 is missing (ICU 73 from the Sailfish root)" >&2; exit 2; }
command -v bwrap >/dev/null || { echo "host-run.sh: needs bubblewrap" >&2; exit 2; }
mkdir -p "$prefix/compat"
# Only the compat libraries the host lacks: libgbm and libsoup from the
# phone's compat set would shadow the host's working ones.
ln -sf "$root/usr/lib64/wpe-compat/libjpeg.so.8" "$prefix/compat/libjpeg.so.8"
export LD_LIBRARY_PATH="$prefix/icu73:$prefix/compat:$root/usr/lib64"
# Spell checking: an enchant built for the host with --prefix=<prefix>/enchant
# and dictionaries in <prefix>/hunspell (README.md "Running on the host").
if [ -d "$prefix/enchant/lib" ]; then
    LD_LIBRARY_PATH="$prefix/enchant/lib:$LD_LIBRARY_PATH"
fi
if [ -d "$prefix/hunspell" ]; then
    export PACIFIC_DICTIONARY_DIR="$prefix/hunspell"
fi
if [ -d "$prefix/voikko" ]; then
    export VOIKKO_DICTIONARY_PATH="$prefix/voikko"
fi
export ENCHANT_CONFIG_DIR="${ENCHANT_CONFIG_DIR:-$prefix/enchant-config}"
export PACIFIC_WEB_EXTENSIONS_DIR="$build/web-process-extensions"
export QML_IMPORT_PATH="$build/qml${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QSG_RHI_BACKEND=opengl
# Fedora's Qt logs to the journal when stderr is not a terminal.
export QT_FORCE_STDERR_LOGGING=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
exec bwrap --dev-bind / / --tmpfs /opt \
    --ro-bind "$root/usr/libexec/wpe-webkit-2.0" /opt/wpe-sfos/libexec/wpe-webkit-2.0 \
    --ro-bind "$root/opt/wpe-sfos/lib" /opt/wpe-sfos/lib \
    -- "$@"
