#!/bin/sh
# An app made by `marathon-dev init` passes `marathon-dev lint` as a
# third-party app.
set -eu
dev=$1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
"$dev" init "Demo App" >/dev/null
"$dev" lint demo-app
