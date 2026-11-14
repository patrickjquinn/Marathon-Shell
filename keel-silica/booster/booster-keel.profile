# -*- mode: sh -*-
# SPDX-FileCopyrightText: 2026 Patrick Quinn
# SPDX-License-Identifier: MIT
#
# Sailjail profile of booster-keel@<app>.service, the per-application Keel
# booster that runs inside the app's sandbox (as booster-silica-media.profile
# for stock Sailfish apps): the booster's own data, plus what every booster
# needs (booster.inc, from sailjail-permissions). Without it the sandboxed
# booster cannot start, and `invoker -A` has nothing to launch the app in.
whitelist /usr/share/booster-keel
include /etc/sailjail/permissions/booster.inc
