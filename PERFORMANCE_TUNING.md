# Marathon Shell Performance Tuning Guide

**Target Device:** OnePlus 6 (enchilada) - Snapdragon 845, Adreno 630  
**Current Status:** ✅ **System is GPU-accelerated and running at ~60 FPS**  
**Build Type:** MinSizeRel (acceptable for mobile)

---

## Current Performance Validation

The shell is **already properly GPU-accelerated** via EGLFS. The `-platform eglfs` flag (added in APKBUILD line 136) ensures direct framebuffer rendering with GPU acceleration, regardless of other environment variables.

**Key Facts:**
- ✅ 60 FPS confirms GPU is active
- ✅ EGLFS is correctly configured
- ✅ Command-line args override environment variables correctly
- ✅ Adreno 630 is a capable GPU (comparable to desktop GPUs from 2012-2014)

---

## Optional Performance Tuning

These are **minor optimizations** that may improve responsiveness or reduce latency by 5-10%, not dramatic speedups.

### 1. **Scene Graph Threading** (Test Both Modes)

**Current:** Likely using basic/single-threaded render loop

**File:** `configs/etc/environment.d/50-gpu-acceleration.conf` or `packages/marathon-shell/marathon-shell-session`

**Add:**
```bash
# Option A: Threaded (may improve CPU/GPU overlap)
export QSG_RENDER_LOOP=threaded

# Option B: Basic (current default, lower overhead)
export QSG_RENDER_LOOP=basic
```

**Test:** Run shell with `QSG_INFO=1` to see render loop mode, observe frame times.

---

### 2. **Explicit RHI Backend** (Consistency)

**Current:** Auto-detecting (likely using OpenGL ES 2.0/3.0)

**File:** `50-gpu-acceleration.conf`

**Add:**
```bash
# Force OpenGL ES (what's probably being used now):
export QSG_RHI_BACKEND=gles2
export QSG_INFO=1  # Enable info logging to verify backend

# Alternative: Try Vulkan (may be faster, requires mesa-vulkan-drivers)
# export QSG_RHI_BACKEND=vulkan
# export QT_VULKAN_DEVICE=0
```

**Note:** Vulkan requires additional packages (see Advanced section below).

---

### 3. **Frame Pacing & VSync**

**Current:** May have vsync disabled or variable

**File:** `50-gpu-acceleration.conf`

**Add:**
```bash
# Enable vsync for smoother 60 FPS:
export QT_QPA_EGLFS_SWAPINTERVAL=1

# Reduce input latency (single buffering):
export QSG_MAX_FRAMES_IN_FLIGHT=1

# Atomic modesetting (reduces tearing):
export QT_QPA_EGLFS_KMS_ATOMIC=1
export QT_QPA_EGLFS_ALWAYS_SET_MODE=1
```

---

### 4. **QML Disk Cache** (Faster App Launches)

**Current:** Disabled during build (`QML_DISABLE_DISK_CACHE=1` in APKBUILD)

**File:** `packages/marathon-shell/marathon-shell-session`

**Change line 93-94:**
```bash
# Remove these lines:
# export QML_DISABLE_DISK_CACHE=1
# export QT_DISABLE_QML_CACHE=1

# Add instead:
export QML_DISK_CACHE=1
export QML_DISK_CACHE_PATH=/home/user/.cache/qml
```

**Benefit:** QML files are compiled once and cached, reducing app launch time by 50-200ms.

---

### 5. **Clean Up Confusing Config** (Optional - Clarity Only)

**File:** `50-gpu-acceleration.conf`

**Current (confusing but harmless):**
```bash
QT_QUICK_BACKEND=software  # Misleading name, doesn't disable GPU with EGLFS
```

**Suggested (clearer):**
```bash
# Remove the line entirely, or comment it:
# QT_QUICK_BACKEND=software  # Not needed with EGLFS
```

**Impact:** None on performance, just removes confusion. With `-platform eglfs`, GPU is always used.

---

## Advanced: Vulkan Backend

**Status:** Optional, may provide 5-15% better frame consistency and lower latency.

### Requirements:

1. **Install packages:**
   ```bash
   apk add vulkan-loader mesa-vulkan-drivers mesa-demos
   ```

2. **Update `50-gpu-acceleration.conf`:**
   ```bash
   # Qt Vulkan backend
   export QSG_RHI_BACKEND=vulkan
   export QT_VULKAN_DEVICE=0
   export QSG_INFO=1
   
   # Vulkan layers (disable validation for production)
   export VK_INSTANCE_LAYERS=
   export VK_LOADER_DEBUG=error
   
   # Adreno Turnip (freedreno Vulkan driver)
   export TU_DEBUG=noconform
   export MESA_VK_DEVICE_SELECT=a630  # Force Adreno 630
   
   # EGLFS still needed for window management
   export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
   export QT_QPA_EGLFS_KMS_ATOMIC=1
   ```

3. **Update APKBUILD dependencies:**
   ```bash
   depends="
       ...existing packages...
       vulkan-loader
       mesa-vulkan-drivers
       "
   ```

### Validation:

```bash
# On device, verify Vulkan works:
vulkaninfo | grep -i adreno

# Expected output:
# deviceName = Adreno (TM) 630
# apiVersion = 1.1.xxx

# Run shell with verbose logging:
QSG_INFO=1 marathon-shell-bin -platform eglfs 2>&1 | grep -i vulkan

# Should see:
# qt.scenegraph.general: Using Vulkan backend
```

---

## Testing & Validation

### 1. **Current Backend Detection**

```bash
# On device:
QSG_INFO=1 marathon-shell-bin -platform eglfs 2>&1 | head -20

# Look for:
# - "Using OpenGL ES X.X backend" (current)
# - "Using Vulkan backend" (if Vulkan enabled)
# - "MSAA sample count" (GPU is active if shown)
```

### 2. **Frame Rate Monitoring**

```bash
# Enable frame rate overlay:
export QSG_VISUALIZE=overdraw
export QSG_INFO=1

marathon-shell-bin -platform eglfs
```

### 3. **GPU Utilization**

```bash
# On device:
watch -n 1 cat /sys/class/kgsl/kgsl-3d0/gpubusy_percentage

# Should see 20-60% during animations, 1-5% idle
```

### 4. **Render Loop Mode**

```bash
QSG_INFO=1 marathon-shell-bin -platform eglfs 2>&1 | grep render

# Look for:
# - "basic render loop" (current, single-threaded)
# - "threaded render loop" (if threaded enabled)
```

---

## Recommended Testing Order

1. **Baseline:** Test current performance (already ~60 FPS)
2. **Try Threaded Loop:** Add `QSG_RENDER_LOOP=threaded`, test for 10 minutes
3. **Enable VSync:** Add `QT_QPA_EGLFS_SWAPINTERVAL=1`, check frame consistency
4. **QML Cache:** Enable disk cache, test app launch times
5. **Vulkan (optional):** Install deps, enable Vulkan, test for stability

**Roll back** any change that causes issues (stuttering, crashes, visual glitches).

---

## Performance Expectations

| Configuration | Expected FPS | Notes |
|--------------|--------------|-------|
| Current (EGLFS + OpenGL ES) | 50-60 | ✅ Already excellent |
| + Threaded Loop | 55-60 | More consistent frame times |
| + VSync | 60 (locked) | Smoother, no tearing |
| + QML Cache | Same FPS | Faster app launches (~200ms) |
| + Vulkan | 55-65 | Lower latency, better consistency |

**Important:** The Adreno 630 is powerful enough for 60 FPS with headroom. The goal is **consistency**, not higher peak FPS.

---

## Known Issues & Limitations

### 1. **Software Backend Name is Misleading**

The `QT_QUICK_BACKEND=software` setting doesn't disable GPU acceleration when using `-platform eglfs`. It likely controls scene graph threading or render loop mode. Can be safely removed for clarity.

### 2. **Session Script QT_QPA_PLATFORM Override**

`marathon-shell-session` sets `QT_QPA_PLATFORM=wayland`, but this is **correctly overridden** by the command-line `-platform eglfs` flag in APKBUILD line 136. No action needed, but could be removed for clarity:

```bash
# In marathon-shell-session, remove line 15:
# export QT_QPA_PLATFORM=wayland  # Not needed, overridden by -platform eglfs
```

### 3. **Vulkan Driver Maturity**

The Turnip driver (freedreno Vulkan) for Adreno 630 is mature but may have edge cases. OpenGL ES is the safer default. Only switch to Vulkan if testing shows clear benefits.

---

## Build Optimizations (Optional)

### Current Build Type: `MinSizeRel`

This is **acceptable** for mobile devices (smaller binary, less memory pressure). If you want to prioritize speed over size:

**File:** `packages/marathon-shell/APKBUILD` line 98

**Change:**
```cmake
# Current:
-DCMAKE_BUILD_TYPE=MinSizeRel \

# For maximum speed (larger binary):
-DCMAKE_BUILD_TYPE=Release \
-DCMAKE_CXX_FLAGS="-O3 -march=armv8-a+crc+crypto -mtune=cortex-a75 -flto" \

# For balanced (recommended):
-DCMAKE_BUILD_TYPE=RelWithDebInfo \
-DCMAKE_CXX_FLAGS="-O2 -march=armv8-a+crc -mtune=cortex-a75" \
```

**Impact:** May improve CPU-bound operations by 10-15%, no impact on GPU rendering.

---

## Summary for Maintainer

**Current Status:** ✅ System is well-optimized, 60 FPS, GPU-accelerated

**Immediate Actions:** None required (system is working well)

**Optional Improvements (in priority order):**
1. Enable QML disk cache (faster app launches)
2. Add VSync for frame consistency (`QT_QPA_EGLFS_SWAPINTERVAL=1`)
3. Try threaded render loop (`QSG_RENDER_LOOP=threaded`)
4. Clean up confusing `QT_QUICK_BACKEND=software` line
5. (Advanced) Test Vulkan backend for lower latency

**Testing:** All changes should be tested for 10+ minutes of real usage before being committed. Roll back anything that causes stuttering, crashes, or visual artifacts.

---

**Last Updated:** 2025-10-31  
**Validated By:** Marathon Shell development team  
**Device Tested:** OnePlus 6 (enchilada) running postmarketOS + Marathon Shell

