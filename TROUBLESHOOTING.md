# Marathon Shell Troubleshooting Guide

## Common Build and Runtime Issues

### ❌ Error: `module "MarathonUI.Theme" is not installed`

**Symptom:**
```
[WARNING] QQmlApplicationEngine failed to load component
[WARNING] qrc:/MarathonOS/Shell/qml/MarathonShell.qml:5:1: module "MarathonUI.Theme" is not installed
[CRITICAL] No root QML objects
```

**Root Cause:**
MarathonUI QML modules must be **built AND installed** before Marathon Shell can run. Simply building the project is not enough.

**Quick Fix:**
```bash
cd Marathon-Shell
./scripts/build-all.sh  # Builds AND installs everything
```

**Manual Fix (if build-all.sh fails):**
```bash
# Build project
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# CRITICAL: Install MarathonUI modules
cmake --install build

# Now run shell
./build/shell/marathon-shell-bin
```

**Why This Happens:**
- Marathon Shell is a Qt/QML application that imports `MarathonUI.*` modules
- Qt searches for QML modules in specific directories (import paths)
- MarathonUI must be installed to one of these locations:
  1. `~/.local/share/marathon-ui/` (user-local, **recommended for development**)
  2. `/usr/lib/qt6/qml/MarathonUI/` (system-wide, requires sudo)
  3. `build/MarathonUI/` (build directory, **now supported as of this fix**)

**Verification:**
After running `cmake --install build`, check:
```bash
ls ~/.local/share/marathon-ui/MarathonUI/Theme/qmldir
```
If this file exists, MarathonUI is installed correctly.

---

### ❌ Error: `module "QtWebEngine" is not installed`

**Symptom:**
The **Browser** app fails to launch, and logs show:
```
[WARNING] [MarathonAppLoader] Component error: ".../BrowserApp.qml:2 module "QtWebEngine" is not installed"
```

**Root Cause:**
The `QtWebEngine` QML module is missing from your system. This is required for the Browser app.

**Fix:**
Install the missing dependency:

**Fedora:**
```bash
sudo dnf install qt6-qtwebengine-devel
```

**Ubuntu/Debian:**
```bash
sudo apt install qml-module-qtwebengine
```

**Arch Linux:**
```bash
sudo pacman -S qt6-webengine
```

---

### 🐛 Debugging QML Module Loading

If you're still getting module not found errors, enable debug mode:

```bash
MARATHON_DEBUG=1 ./build/shell/marathon-shell-bin
```

You'll see output like:
```
[QML Import] User-local MarathonUI: /home/user/.local/share/marathon-ui
[QML Import] System-wide Qt modules: /usr/lib/qt6/qml
[QML Import] Build directory: /home/user/Marathon-Shell/build
[MarathonShell] ✓ MarathonUI modules found
  - Using user-local installation
```

If you see:
```
FATAL: MarathonUI QML modules not found!
CHECKED PATHS:
  1. /home/user/.local/share/marathon-ui/MarathonUI/Theme [NOT FOUND]
  2. /usr/lib/qt6/qml/MarathonUI/Theme [NOT FOUND]
  3. /home/user/Marathon-Shell/build/MarathonUI/Theme [NOT FOUND]
```

Then MarathonUI is not installed. Run `cmake --install build`.

---

### 📦 System-Wide Installation (For Packaging)

For distribution packages (Debian, Fedora, Arch, etc.):

```bash
# Build for system paths
cmake -B build -S . \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build -j$(nproc)

# Install to system directories (requires root)
sudo cmake --install build

# MarathonUI will be installed to:
#   /usr/lib/qt6/qml/MarathonUI/

# Shell binary will be installed to:
#   /usr/bin/marathon-shell
```

---

### 🔧 Development Workflow

**First-time setup:**
```bash
git clone --recursive https://github.com/patrickjquinn/Marathon-Shell.git
cd Marathon-Shell
./scripts/build-all.sh  # Builds AND installs everything
```

**Iterative development:**
```bash
./run.sh  # Rebuilds and runs shell (fast incremental builds)
```

**After modifying MarathonUI QML files:**
```bash
cd build-ui && cmake --build . && cmake --install .
```

**After modifying shell C++ or QML:**
```bash
cd build && cmake --build .
./shell/marathon-shell-bin
```

**Clean rebuild:**
```bash
CLEAN=1 ./run.sh
```

---

### 🖥️ Platform-Specific Notes

#### Droidian / Mobian / PostmarketOS

On mobile Linux distributions, you may need to build without WebEngine:

```bash
# Install dependencies (example for Debian-based)
sudo apt install cmake ninja-build g++ \
    qt6-base-dev qt6-declarative-dev \
    qt6-wayland-dev qt6-multimedia-dev \
    libhunspell-dev hunspell-en-us

# Build (WebEngine detection is automatic)
./scripts/build-all.sh
```

#### Arch Linux

```bash
# Install dependencies
sudo pacman -S cmake ninja gcc qt6-base qt6-declarative \
    qt6-wayland qt6-multimedia qt6-webengine \
    hunspell hunspell-en_us

# Build
./scripts/build-all.sh
```

#### Fedora / RHEL

```bash
# Install dependencies
sudo dnf install cmake ninja-build gcc-c++ \
    qt6-qtbase-devel qt6-qtdeclarative-devel \
    qt6-qtwayland-devel qt6-qtmultimedia-devel \
    qt6-qtwebengine-devel \
    hunspell-devel hunspell-en-US

# Build
./scripts/build-all.sh
```

---

### 🔍 Qt Version Compatibility

**Supported:** Qt 6.5.0 - 6.9.3

**Known Issues:**
- **Qt 6.10+**: May have breaking QML changes (untested)
- **Qt 6.4 and older**: Not supported (missing QML features)

Check your Qt version:
```bash
qmake6 --version  # or qmake -version on some distros
```

---

### 💬 Getting Help

If you're still stuck:

1. **Enable debug logging:**
   ```bash
   MARATHON_DEBUG=1 ./build/shell/marathon-shell-bin > debug.log 2>&1
   ```

2. **Collect build information:**
   ```bash
   cmake --version
   qmake6 --version
   ls -la ~/.local/share/marathon-ui/MarathonUI/Theme/
   ```

3. **File an issue:** https://github.com/patrickjquinn/Marathon-Shell/issues

Include:
- Your Linux distribution and version
- Qt version
- Full build log (`./scripts/build-all.sh > build.log 2>&1`)
- Debug log (from step 1)
- Output of `ls -la ~/.local/share/marathon-ui/`

---

## Summary: The Three-Step Build

```bash
# 1. Build everything
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)

# 2. INSTALL MarathonUI (CRITICAL!)
cmake --install build

# 3. Run shell
./build/shell/marathon-shell-bin
```

**Or just use:**
```bash
./scripts/build-all.sh
./run.sh
```

✅ **That's it!**

