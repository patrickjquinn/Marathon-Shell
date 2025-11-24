#!/bin/bash
# Send a test notification to Marathon Shell via D-Bus

APP_NAME="Test Script"
TITLE="Hello Marathon"
BODY="This is a test notification from the command line."
ICON="info"

echo "Sending test notification..."
echo "Title: $TITLE"
echo "Body: $BODY"

# Try using gdbus (standard on most desktops)
if command -v gdbus >/dev/null 2>&1; then
    # Try standard destination first
    gdbus call --session \
        --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "$APP_NAME" \
        0 \
        "$ICON" \
        "$TITLE" \
        "$BODY" \
        "[]" \
        "{'category': <'test'>, 'urgency': <byte 1>}" \
        5000
    
    # If that didn't reach Marathon (likely hit GNOME), try the fallback
    echo "Also trying Marathon fallback destination..."
    gdbus call --session \
        --dest org.marathon.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify \
        "$APP_NAME" \
        0 \
        "$ICON" \
        "$TITLE" \
        "$BODY" \
        "[]" \
        "{'category': <'test'>, 'urgency': <byte 1>}" \
        5000
        
    if [ $? -eq 0 ]; then
        echo "✅ Notification sent via gdbus (fallback)"
        exit 0
    fi
fi

# Fallback to notify-send (libnotify)
if command -v notify-send >/dev/null 2>&1; then
    notify-send "$TITLE" "$BODY" -i "$ICON" -a "$APP_NAME"
    if [ $? -eq 0 ]; then
        echo "✅ Notification sent via notify-send"
        exit 0
    fi
fi

echo "❌ Failed to send notification. Neither gdbus nor notify-send were successful."
exit 1
