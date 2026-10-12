#!/bin/bash
# Install the marathon-store:// URL scheme handler for the current
# user. On Duranium the marathon-shell package ships it; this script
# does the same job on a dev workstation so the Store app's
# Get / Update / Open buttons actually drive flatpak when running
# under the visual-validate harness or `marathon-shell-bin` directly.
#
# Effects (user-scope only — no root):
#   ~/.local/bin/marathon-store-handler   (built from crates/marathon-store-handler)
#   ~/.local/share/applications/marathon-store-handler.desktop
#   xdg-mime default for x-scheme-handler/marathon-store
#
# Re-run after changing the handler — the install is idempotent.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRATES_DIR="$(cd "$SRC_DIR/../../crates" && pwd)"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"
DESKTOP_NAME="marathon-store-handler.desktop"

mkdir -p "$BIN_DIR" "$APP_DIR"

cargo build --release --locked --manifest-path "$CRATES_DIR/Cargo.toml" -p marathon-store-handler
install -m 0755 "${CARGO_TARGET_DIR:-$CRATES_DIR/target}/release/marathon-store-handler" \
    "$BIN_DIR/marathon-store-handler"
install -m 0644 "$SRC_DIR/$DESKTOP_NAME" "$APP_DIR/$DESKTOP_NAME"

# Patch the Exec= line to point at the user-local copy. On Duranium
# the handler lives at /usr/bin; here it's wherever ~/.local/bin
# resolves.
sed -i "s|^Exec=.*|Exec=${BIN_DIR}/marathon-store-handler %u|" \
    "$APP_DIR/$DESKTOP_NAME"

# Refresh the desktop database so xdg-mime can see the new entry.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

# Register as default for the marathon-store:// scheme.
xdg-mime default "$DESKTOP_NAME" x-scheme-handler/marathon-store

echo "Installed marathon-store-handler:"
echo "  handler        : $BIN_DIR/marathon-store-handler"
echo "  desktop entry  : $APP_DIR/$DESKTOP_NAME"
echo
echo "Registered marathon-store:// scheme. Test with:"
echo "  xdg-open marathon-store://refresh-state/all"
