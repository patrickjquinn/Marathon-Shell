# Device migration benchmarks

These tools measure a running Marathon device. Build `dbus-rtt.c` against the
device's libc and libdbus using the command in its header. Copy that executable
to `/run/marathon-dbus-rtt`, `under-cpu-load.py` to
`/run/marathon-under-cpu-load.py`, and the other scripts to `/run/`.

Run `device-latency.sh idle` and `device-latency.sh load` as root. Each emits
three trials of 1,000 replies per endpoint, after 20 warm-up replies. The client
uses one persistent connection. Timings include sending the request, bus
routing, server processing and receiving the reply; they exclude client process
startup and request construction. An unsuccessful request makes the run fail.

The latency wrapper temporarily selects the performance governor on policy0,
reports its frequency, and restores the previous governor on exit. The load run
starts one busy worker per available core and reports measured CPU utilization.
Keep the client binary, device configuration and scripts identical before and
after deploying. Compare the median of each trial's percentiles; do not describe
that statistic as a percentile of pooled samples.

Run `python3 device-snapshot.py LABEL 30` as root with the shell on its home
screen to collect a 30-second idle CPU sample, RSS, PSS, thread counts and hashes
of running executables. CPU percentages use one core as 100%. PSS is in KiB.
Restarts and application caches affect memory: snapshots of a long-running old
process and a freshly restarted new process are observations, not an isolated
measurement of the dependency update's memory cost.
