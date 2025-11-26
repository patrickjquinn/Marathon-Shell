#!/bin/bash

# Marathon Shell - Build and Run Script
# Incremental builds only (much faster). Run with CLEAN=1 for clean rebuild.

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

# Detect number of CPU cores
if [[ "$OSTYPE" == "darwin"* ]]; then
    CORES=$(sysctl -n hw.ncpu)
else
    CORES=$(nproc)
fi

echo "💻 Detected $CORES CPU cores"

# Clean build if requested
if [ "$CLEAN" = "1" ]; then
    echo " Clean build requested, removing build directories..."
    rm -rf build build-apps build-ui
fi

# Kill any existing instances first
echo "🛑 Killing any running Marathon Shell instances..."
pkill -9 marathon-shell 2>/dev/null || true

echo ""
echo "============================================"
echo "Marathon OS Incremental Build"
echo "============================================"
echo ""

# Build everything using build-all.sh script
echo "🏗  Building Marathon Shell and Apps..."
# CRITICAL: Always reinstall apps to ensure source changes are deployed
./scripts/build-all.sh install

if [ $? -eq 0 ]; then
    echo ""
    echo " Complete build successful!"
    echo ""
    
    # Setup power management permissions (Linux only)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "🔋 Checking power management permissions..."
        
        NEED_WAKELOCK_SETUP=false
        NEED_RTC_SETUP=false
        
        # Check wakelock support
        if [ -e "/sys/power/wake_lock" ]; then
            if [ ! -w "/sys/power/wake_lock" ]; then
                NEED_WAKELOCK_SETUP=true
                echo "   ⚠️  Wakelock interface found but not writable"
            else
                echo "   ✓ Wakelock interface: accessible"
            fi
        else
            echo "   ℹ️  Kernel wakelock interface not available (CONFIG_PM_WAKELOCKS not enabled)"
            echo "      Will use systemd-logind inhibitors as fallback"
        fi
        
        # Check RTC alarm support
        if [ -e "/sys/class/rtc/rtc0/wakealarm" ]; then
            if [ ! -w "/sys/class/rtc/rtc0/wakealarm" ]; then
                NEED_RTC_SETUP=true
                echo "   ⚠️  RTC wake alarm found but not writable"
            else
                echo "   ✓ RTC wake alarm: accessible"
            fi
        else
            echo "   ℹ️  RTC wake alarm interface not available"
        fi
        
        # Offer to set up permissions if needed
        if [ "$NEED_WAKELOCK_SETUP" = true ] || [ "$NEED_RTC_SETUP" = true ]; then
            echo ""
            echo "   Power management features need permissions setup."
            echo "   This will enable:"
            if [ "$NEED_WAKELOCK_SETUP" = true ]; then
                echo "     - Kernel wakelocks (prevent opportunistic suspend)"
            fi
            if [ "$NEED_RTC_SETUP" = true ]; then
                echo "     - RTC wake alarms (wake from suspend)"
            fi
            echo ""
            
            # Auto-setup in CI/non-interactive mode, otherwise ask
            if [ -n "$CI" ] || [ "$AUTO_SETUP_PERMISSIONS" = "1" ]; then
                SETUP_PERMS="y"
            else
                read -p "   Set up permissions now? (y/N) " -n 1 -r SETUP_PERMS
                echo ""
            fi
            
            if [[ $SETUP_PERMS =~ ^[Yy]$ ]]; then
                echo "   Setting up permissions (requires sudo)..."
                
                if [ "$NEED_WAKELOCK_SETUP" = true ] && [ -e "/sys/power/wake_lock" ]; then
                    sudo chmod 666 /sys/power/wake_lock /sys/power/wake_unlock 2>/dev/null || true
                    echo "   ✓ Wakelock permissions set"
                fi
                
                if [ "$NEED_RTC_SETUP" = true ] && [ -e "/sys/class/rtc/rtc0/wakealarm" ]; then
                    sudo chmod 664 /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
                    sudo chgrp $USER /sys/class/rtc/rtc0/wakealarm 2>/dev/null || true
                    echo "   ✓ RTC alarm permissions set"
                fi
                
                echo ""
                echo "   ✅ Power management permissions configured!"
                echo "      (Note: These are temporary and will reset on reboot)"
                echo "      For persistent setup, see README.md Power Management section"
            else
                echo "   ⏭️  Skipping permission setup"
                echo "      Shell will use fallback methods (systemd-logind inhibitors)"
            fi
        else
            echo "   ✅ Power management: ready"
        fi
        echo ""
    fi
    
    echo " Starting Marathon Shell..."
    echo ""
    
    # Check for debug mode
    if [ "$MARATHON_DEBUG" = "1" ] || [ "$MARATHON_DEBUG" = "true" ]; then
        echo "🐛 Debug mode enabled (MARATHON_DEBUG=$MARATHON_DEBUG)"
        echo ""
    fi
    
    # CRITICAL: Disable Qt's automatic HiDPI scaling for the compositor itself
    # The compositor must render at native 1:1 scale, regardless of host DPI
    # Otherwise QWaylandOutput will advertise wrong geometry (e.g. 1080x2280 instead of 540x1140)
    export QT_AUTO_SCREEN_SCALE_FACTOR=0
    export QT_ENABLE_HIGHDPI_SCALING=0
    
    # Check for device DPI simulation (OnePlus 6: ~1.25x scale for 50% window)
    if [ "$DEVICE_DPI" = "1" ] || [ "$DEVICE_DPI" = "oneplus6" ]; then
        export QT_SCALE_FACTOR=1.25
        echo "📱 Device DPI simulation enabled (OnePlus 6: 1.25x scale)"
        echo "   Window: 540x1140 (50% of 1080x2280), DPI: ~402 ppi"
        echo ""
    else
        # Force 1:1 scaling (no DPI scaling from host)
        export QT_SCALE_FACTOR=1
        echo "🖥  Compositor scaling: 1:1 (native resolution, no HiDPI from host)"
    fi
    
    # Enable QML validation in debug mode
    if [ "$MARATHON_DEBUG" = "1" ] || [ "$MARATHON_DEBUG" = "true" ]; then
        # DON'T disable disk cache - we need it for ARM performance!
        # export QML_DISABLE_DISK_CACHE=1
        export QT_QML_DISK_CACHE_PATH="${XDG_CACHE_HOME:-$HOME/.cache}/marathon-qml"
        mkdir -p "$QT_QML_DISK_CACHE_PATH"
        # Allow all logging in debug mode (same as running binary directly)
        unset QT_LOGGING_RULES
        echo " Debug mode: Full logging enabled (no filtering)"
        echo ""
    else
        # Disable all debug logging in production
        export QT_LOGGING_RULES="*.debug=false;*.info=false;*.warning=false"
    fi
    
    # Additional Qt environment variables to reduce verbosity
    export QT_QUICK_CONTROLS_STYLE=""
    export QT_QUICK_CONTROLS_IMAGEPROVIDER=""
    export QT_QUICK_CONTROLS_MATERIAL_THEME=""
    export QT_QUICK_CONTROLS_MATERIAL_VARIANT=""
    export QT_QUICK_CONTROLS_UNIVERSAL_THEME=""
    export QT_QUICK_CONTROLS_UNIVERSAL_VARIANT=""
    
    # Set QML import path for MarathonUI modules
    export QML_IMPORT_PATH="$PROJECT_DIR/build/shell/qml:$QML_IMPORT_PATH"
    
    # Force Qt Multimedia to use GStreamer backend (better PulseAudio/PipeWire support)
    export QT_MEDIA_BACKEND=gstreamer
    echo "🔊 Audio backend: $QT_MEDIA_BACKEND (GStreamer has native PulseAudio support)"
    echo ""
    
    # Run the app (detect OS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS .app# Set Chromium Flags for embedded stability
# --disable-gpu: Prevent GPU instability
# --renderer-process-limit=1: Limit renderer processes to save memory (Aggressive)
# --disable-dev-shm-usage: Fix crash in containers/low-memory
export QTWEBENGINE_CHROMIUM_FLAGS="--disable-gpu --renderer-process-limit=1 --disable-dev-shm-usage"
export QT_WEBENGINE_DISABLE_SANDBOX=1

# Run the shell
./build/shell/marathon-shell-bin.app/Contents/MacOS/marathon-shell-bin
    else
        # Linux executable
        ./build/shell/marathon-shell-bin
    fi
else
    echo " Build failed!"
    exit 1
fi
