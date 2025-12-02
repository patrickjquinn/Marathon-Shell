#!/bin/bash
echo "Stopping any running instances..."
pkill marathon-shell

echo "Starting Marathon Shell with QML debugger enabled..."
echo "Please wait for the shell to appear, then perform your swipe gestures."
# Start shell in background, wait for debugger connection
# Enable render timing for fallback data
export QSG_RENDER_TIMING=1
./build/shell/marathon-shell-bin -qmljsdebugger=port:10000,host:127.0.0.1 &> shell_perf.log &
SHELL_PID=$!

# Wait for port to be ready
echo "Waiting for debugger port 10000..."
for i in {1..30}; do
    if netstat -tuln | grep -q ":10000 "; then
        echo "Port 10000 is open!"
        break
    fi
    sleep 0.5
done

echo "Checking if shell is running..."
ps -p $SHELL_PID || echo "Shell is NOT running!"

echo "Checking for listening port..."
netstat -tuln | grep 10000 || echo "Port 10000 not found!"

echo "Attaching QML Profiler..."
echo "RECORDING FOR 20 SECONDS - GO GO GO!"

# Run profiler for 20 seconds. 
# We use SIGINT (2) to allow it to gracefully close and save data if possible, 
# though qmlprofiler usually saves on exit.
timeout --signal=SIGINT 20s /usr/lib/qt6/bin/qmlprofiler --attach localhost:10000 --output profile_data.qtd

echo "Profiling finished."
echo "Saving data to $(pwd)/profile_data.qtd"

# Optional: Kill shell after profiling
# kill $SHELL_PID
