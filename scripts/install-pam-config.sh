#!/usr/bin/env bash
#
# Install Marathon Shell PAM Configuration
#
# This script installs the PAM configuration file for Marathon authentication.
# Must be run with sudo/root privileges.
#

set -e  # Exit on error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PAM_SOURCE="$PROJECT_ROOT/pam.d/marathon-shell"
PAM_DEST="/etc/pam.d/marathon-shell"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run with sudo:"
    echo "   sudo $0"
    exit 1
fi

# Check if source file exists
if [ ! -f "$PAM_SOURCE" ]; then
    echo "❌ PAM configuration file not found: $PAM_SOURCE"
    exit 1
fi

# Backup existing config if present
if [ -f "$PAM_DEST" ]; then
    BACKUP="$PAM_DEST.backup.$(date +%Y%m%d-%H%M%S)"
    echo "📦 Backing up existing PAM config to: $BACKUP"
    cp "$PAM_DEST" "$BACKUP"
fi

# Install the configuration
echo "📝 Installing Marathon Shell PAM configuration..."
cp "$PAM_SOURCE" "$PAM_DEST"
chmod 644 "$PAM_DEST"
chown root:root "$PAM_DEST"

echo "✅ PAM configuration installed successfully!"
echo ""
echo "Configuration details:"
echo "  - Location: $PAM_DEST"
echo "  - Authentication stack: fprintd -> pam_unix (with rate limiting)"
echo "  - Rate limiting: pam_faillock (5 attempts, then lockout)"
echo "  - Session: systemd-logind integration"
echo ""
echo "To verify the configuration:"
echo "  cat $PAM_DEST"
echo ""
echo "To test authentication (will prompt for password):"
echo "  pamtester marathon-shell $USER authenticate"
echo ""

