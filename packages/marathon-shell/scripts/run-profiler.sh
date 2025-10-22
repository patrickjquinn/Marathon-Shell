#!/bin/bash
# Marathon Shell - Run with QML Profiler enabled

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "============================================"
echo "Marathon Shell - QML Profiler Mode"
echo "============================================"
echo ""
echo "🔍 Starting with QML profiler enabled..."
echo "📊 Connect Qt Creator → Analyze → QML Profiler → Attach to Running Application"
echo ""

# Enable QML profiler on port 3768 (Qt Creator default)
export QML_PROFILER_PORT=3768
export QSG_VISUALIZE=overdraw  # Optional: visualize overdraw
export QSG_RENDER_LOOP=basic    # Optional: better profiling accuracy

# Build first if needed
if [ ! -f "build/shell/marathon-shell.app/Contents/MacOS/marathon-shell" ]; then
    echo "🏗️  Building Marathon Shell first..."
    ./scripts/build-all.sh
    echo ""
fi

echo "🚀 Launching Marathon Shell with profiler..."
echo "   Profiler listening on port: $QML_PROFILER_PORT"
echo ""

# Run with profiler
./build/shell/marathon-shell.app/Contents/MacOS/marathon-shell -qmljsdebugger=port:$QML_PROFILER_PORT,block

