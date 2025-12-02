import re
import sys

log_file = "shell_perf.log"

frame_times = []
render_times = []
sync_times = []

# Regex for render thread timing
# [DEBUG] [window 0x...][render thread 0x...] syncAndRender: frame rendered in 0ms, sync=0, render=0, swap=0
render_pattern = re.compile(r"frame rendered in (\d+)ms, sync=(\d+), render=(\d+), swap=(\d+)")

# Regex for GUI thread timing (frame interval)
# [DEBUG] [window 0x...][gui thread] polishAndSync: start, elapsed since last call: 5 ms
interval_pattern = re.compile(r"polishAndSync: start, elapsed since last call: (\d+) ms")

intervals = []

with open(log_file, 'r') as f:
    for line in f:
        render_match = render_pattern.search(line)
        if render_match:
            total = int(render_match.group(1))
            sync = int(render_match.group(2))
            render = int(render_match.group(3))
            frame_times.append(total)
            render_times.append(render)
            sync_times.append(sync)
            continue

        interval_match = interval_pattern.search(line)
        if interval_match:
            intervals.append(int(interval_match.group(1)))

if not intervals:
    print("No frame data found in log.")
    sys.exit(1)

avg_interval = sum(intervals) / len(intervals)
avg_fps = 1000 / avg_interval if avg_interval > 0 else 0
min_fps = 1000 / max(intervals) if max(intervals) > 0 else 0
max_fps = 1000 / min(intervals) if min(intervals) > 0 else 0

print(f"--- Performance Summary ---")
print(f"Total Frames Analyzed: {len(intervals)}")
print(f"Average FPS: {avg_fps:.2f}")
print(f"Min FPS: {min_fps:.2f} (Max Interval: {max(intervals)}ms)")
print(f"Max FPS: {max_fps:.2f} (Min Interval: {min(intervals)}ms)")
print(f"---------------------------")
print(f"Average Render Time: {sum(render_times)/len(render_times):.2f}ms")
print(f"Max Render Time: {max(render_times)}ms")
print(f"Average Sync Time: {sum(sync_times)/len(sync_times):.2f}ms")
