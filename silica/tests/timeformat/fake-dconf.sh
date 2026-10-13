#!/bin/sh
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# A `dconf` for tst_timeformat (KEEL_DCONF): `read
# /sailfish/i18n/lc_timeformat24h` prints $KEEL_TEST_TIMEFORMAT24H (nothing
# when it is unset, as dconf does for an unset key).
if [ "$1" = read ] && [ "$2" = /sailfish/i18n/lc_timeformat24h ]; then
    [ -n "${KEEL_TEST_TIMEFORMAT24H:-}" ] && printf '%s\n' "$KEEL_TEST_TIMEFORMAT24H"
fi
exit 0
