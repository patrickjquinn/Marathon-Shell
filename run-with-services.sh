#!/bin/bash
# Marathon Shell - Run with full service environment

echo "🚀 Starting Marathon Shell with full service environment..."
echo ""

# Check service status
echo "Service Status:"
for svc in NetworkManager bluetooth ModemManager upower geoclue; do
    status=$(systemctl is-active "$svc" 2>&1)
    if [[ "$status" == "active" ]]; then
        echo "  ✓ $svc"
    else
        echo "  ⚠️  $svc ($status)"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Export environment variables
export MARATHON_DEBUG=1
export QT_LOGGING_RULES="*.debug=true"

# Run the shell
exec "$(dirname "$0")/run.sh" "$@"
