#!/bin/sh
# SPDX-FileCopyrightText: 2026 Atlantic Browser contributors (atlantic-engine deploy/runtime-common.sh)
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MPL-2.0
#
# The runtime environment Pacific's engine needs, for shell scripts outside
# Sailjail, installed as /usr/libexec/pacific/pacific-env.sh by
# shipwright-pacific-engine:
#
#   . /usr/libexec/pacific/pacific-env.sh          # from a launcher script
#   /usr/libexec/pacific/pacific-env.sh <program> [args]   # or exec under it
#
# The variables themselves are set by the pacific-env program next to this
# script (launcher/pacific-env.c; README.md lists each one and why), which
# the browser also runs inside Sailjail, where there is no shell. Anything
# already set in the environment wins.

pacific_env_bin=${PACIFIC_ENV_BIN:-/usr/libexec/pacific/pacific-env}
eval "$("$pacific_env_bin" --print)"
unset pacific_env_bin

# Run as a wrapper: pacific-env.sh <program> [args]
case ${0##*/} in
    pacific-env.sh)
        if [ $# -gt 0 ]; then
            exec "$@"
        fi
        ;;
esac
