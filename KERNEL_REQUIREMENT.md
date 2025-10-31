# ⚠️ MARATHON SHELL KERNEL REQUIREMENT

## **PREEMPT_RT IS MANDATORY**

Marathon Shell is designed for **BlackBerry 10-level responsiveness** which REQUIRES a **PREEMPT_RT** kernel.

### **Current Issue:**

The deployed kernel is:
```
Linux marathon-ev1 6.14.0-rc5-sdm845 #3-postmarketos-qcom-sdm845 SMP PREEMPT
```

This is **NOT** a PREEMPT_RT kernel. It's just regular `PREEMPT`.

- **SMP PREEMPT** = Voluntary preemption (CONFIG_PREEMPT=y)
- **SMP PREEMPT_RT** = Full real-time preemption (CONFIG_PREEMPT_RT=y)

### **Why PREEMPT_RT?**

Without PREEMPT_RT:
- Touch input latency: **20-40ms** (miss the 16ms target)
- Render thread can be blocked by kernel operations
- Audio glitches during I/O operations
- No deterministic scheduling for compositor

With PREEMPT_RT:
- Touch input latency: **< 16ms** (one frame at 60 Hz)
- Render thread gets CPU immediately when needed
- Glitch-free audio even under load
- Marathon Shell can use `SCHED_FIFO` for critical threads

### **Required Kernel Config:**

```
CONFIG_PREEMPTION=y
CONFIG_PREEMPT_RT=y
CONFIG_CPU_FREQ_GOV_SCHEDUTIL=y
CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y
CONFIG_MQ_IOSCHED_KYBER=y
CONFIG_DEFAULT_KYBER=y
```

### **Image Maintainer Action:**

The `linux-marathon` package with PREEMPT_RT is currently being built and will be deployed in the next image.

**Check RT kernel:**
```bash
uname -a | grep PREEMPT_RT  # Should show "PREEMPT_RT"
```

**Check scheduler:**
```bash
cat /proc/sys/kernel/sched_rt_runtime_us  # Should show RT time budget
```

### **Shell Developer Action:**

1. **Assume PREEMPT_RT is available** - don't make it optional
2. **Fail loudly if RT scheduling fails** - log CRITICAL errors
3. **Document RT requirement** in README
4. **Test with:**
   ```bash
   chrt -f 75 /usr/bin/marathon-shell-bin
   # Should start without "Function not implemented" errors
   ```

---

**Marathon Shell is a high-performance compositor. PREEMPT_RT is not optional.**

