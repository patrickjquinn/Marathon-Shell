#!/bin/sh
# A WebEngineView's backgroundColor must be opaque or fully transparent:
# Chromium fails a CHECK on anything in between. Silica theme colours can be
# translucent, so a web view may not take one as is.
root=${1:-.}
bad=$(grep -rln --include=*.qml "WebEngineView" "$root/apps" "$root/shell/qml" 2>/dev/null |
	xargs grep -Hn "backgroundColor: *Theme\.[A-Za-z]*Color *$" 2>/dev/null)
if [ -n "$bad" ]; then
	echo "WebEngineView backgroundColor from a raw theme colour (may be translucent):"
	echo "$bad"
	exit 1
fi
