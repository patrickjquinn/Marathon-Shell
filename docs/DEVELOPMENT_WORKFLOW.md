# Development Workflow

## Source File Locations

Marathon Shell uses a build-and-install workflow where source files are separate from installed runtime files.

### Source Files (Edit These)

All editable source code is located in the project repository:

```
./apps/           - Application sources
./shell/          - Shell sources (C++ and QML)
./marathon-ui/    - UI library sources
./marathon-core/  - Core library sources
```

### Installed Files (Do Not Edit)

Build artifacts are installed to these locations:

```
~/.local/share/marathon-apps/    - Installed applications (auto-generated)
~/.local/share/marathon-ui/      - Installed UI library (auto-generated)
./build/                         - Build artifacts (auto-generated)
./build-apps/                    - App build artifacts (auto-generated)
```

**Important:** Files in `~/.local/share/marathon-apps/` are overwritten on every build. Changes made to these files will be lost.

---

## Standard Development Cycle

### 1. Edit Source Files

Make changes to source files in the repository:

```bash
# Edit app sources
vim ./apps/phone/pages/DialerPage.qml

# Edit shell sources
vim ./shell/qml/components/MarathonShell.qml

# Edit UI library
vim ./marathon-ui/Core/MButton.qml
```

### 2. Build and Run

Use the provided run script to build and launch:

```bash
./run.sh
```

This script performs the following steps:
1. Builds Marathon Shell (C++ and QML)
2. Builds Marathon UI library
3. Cleans and rebuilds all applications
4. Installs apps to `~/.local/share/marathon-apps/`
5. Launches the shell

### 3. Incremental Builds

For faster iteration when only specific components change:

```bash
# Rebuild apps only
./scripts/build-apps.sh

# Rebuild shell only
cd build && cmake --build .

# Rebuild UI library only
cd build-ui && cmake --build .

# Full clean rebuild
CLEAN=1 ./run.sh
```

---

## Build System Architecture

### Build Process Flow

```
Source Files (./apps/, ./shell/)
    |
    v
CMake Configuration
    |
    v
Compilation (C++/QML)
    |
    v
Installation (~/.local/share/)
    |
    v
Runtime Loading
```

### CMake Targets

The build system defines the following main targets:

- `marathon-shell` - Main shell executable
- `marathon-core` - Core library (app management)
- `marathon-ui-*` - UI library modules
- `marathon-dev` - Developer CLI tool
- Individual app targets in `build-apps/`

### Installation Directories

| Component | Install Location |
|-----------|------------------|
| Marathon Shell | `./build/shell/marathon-shell` |
| Marathon Apps | `~/.local/share/marathon-apps/<app>/` |
| Marathon UI | `~/.local/share/marathon-ui/` |
| Developer Tool | `./build/tools/marathon-dev/marathon-dev` |

---

## Debugging Workflow

### Enable Debug Logging

```bash
# Full debug output
MARATHON_DEBUG=1 ./run.sh

# Qt logging rules
export QT_LOGGING_RULES="marathon.*.debug=true"
./run.sh

# Specific category logging
export QT_LOGGING_RULES="marathon.wayland.debug=true;qt.qml.warning=false"
./run.sh
```

### GDB Debugging

```bash
# Build with debug symbols (default in Debug builds)
cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
cmake --build .

# Run under GDB
gdb --args ./shell/marathon-shell

# GDB commands
(gdb) run
(gdb) bt     # backtrace
(gdb) info threads
```

### Valgrind Memory Checking

```bash
valgrind --leak-check=full \
         --show-leak-kinds=all \
         --track-origins=yes \
         ./build/shell/marathon-shell
```

### QML Profiling

```bash
# Run with QML profiler
QSG_RENDER_TIMING=1 ./run.sh

# Profile specific QML file
qmlprofiler ./build/shell/marathon-shell
```

---

## Common Development Tasks

### Creating a New App

```bash
# Use marathon-dev to scaffold
./build/tools/marathon-dev/marathon-dev init myapp

# Or manually create structure
mkdir -p apps/myapp/{pages,components,assets}
touch apps/myapp/{manifest.json,MyApp.qml,qmldir,CMakeLists.txt}

# Add to apps/CMakeLists.txt
# Then build
./scripts/build-apps.sh
```

### Modifying Existing Apps

1. Edit source in `./apps/<app>/`
2. Run `./scripts/build-apps.sh` or `./run.sh`
3. Changes appear in running shell (or restart shell)

### Updating UI Library

1. Edit source in `./marathon-ui/`
2. Rebuild UI library: `cd build-ui && cmake --build .`
3. Rebuild apps that use updated components
4. Restart shell to load new library

### Adding C++ Backend Code

1. Add `.h` and `.cpp` files to `shell/src/` or app's `src/`
2. Update `CMakeLists.txt` to include new sources
3. Rebuild: `cd build && cmake --build .`
4. Register types in `main.cpp` if exposing to QML

---

## Code Style and Conventions

### C++ Style

- Follow Qt coding conventions
- Use `camelCase` for methods and properties
- Use `PascalCase` for classes
- Use `m_` prefix for private member variables
- Use `Q_PROPERTY` for QML-exposed properties

### QML Style

- Use `camelCase` for property names
- Use `PascalCase` for component names
- Indent with 4 spaces
- Group properties logically (required, optional, signals, internal)
- Place signal handlers after property declarations

### File Naming

- QML files: `PascalCase.qml` (e.g., `MarathonShell.qml`)
- C++ headers: `lowercase.h` (e.g., `waylandcompositor.h`)
- C++ sources: `lowercase.cpp` (e.g., `waylandcompositor.cpp`)

---

## Testing Changes

### Manual Testing

1. Build and launch shell
2. Test affected functionality
3. Check console for errors/warnings
4. Verify no regressions in related features

### Automated Testing

```bash
# Run unit tests
cd build
ctest

# Run specific test
./tests/test_apppackager
```

### QML Validation

```bash
# Validate all QML files
./scripts/validate-qml.sh

# Validate specific file
qmllint apps/phone/pages/DialerPage.qml
```

---

## Troubleshooting

### "App not found" after changes

**Cause:** App not properly installed
**Solution:**
```bash
./scripts/build-apps.sh
# Check install
ls -la ~/.local/share/marathon-apps/
```

### Changes not appearing

**Cause:** Edited installed files instead of source files
**Solution:**
1. Discard changes in `~/.local/share/marathon-apps/`
2. Make edits in `./apps/`
3. Run `./scripts/build-apps.sh`

### Build errors after pulling changes

**Cause:** Stale build artifacts or CMake cache
**Solution:**
```bash
# Clean rebuild
CLEAN=1 ./run.sh

# Or manually clean
rm -rf build build-apps build-ui
./scripts/build-all.sh
```

### Wayland compositor crashes

**Cause:** Various (compositor bugs, driver issues)
**Debug:**
```bash
MARATHON_DEBUG=1 ./run.sh 2>&1 | tee crash.log
# Check crash.log for stack trace
```

---

## Contributing Workflow

### Before Submitting Changes

1. Test thoroughly on target platform
2. Run QML validation: `./scripts/validate-qml.sh`
3. Check for console warnings
4. Verify no regressions
5. Follow code style conventions
6. Update documentation if needed

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/my-feature

# Make changes
vim apps/myapp/MyApp.qml

# Test
./run.sh

# Commit
git add apps/myapp/
git commit -m "Add feature X to myapp"

# Push and create PR
git push origin feature/my-feature
```

---

## Quick Reference

### Essential Commands

```bash
# Development
./run.sh                           # Build and run everything
./scripts/build-apps.sh            # Rebuild apps only
./scripts/validate-qml.sh          # Validate QML syntax

# Debugging
MARATHON_DEBUG=1 ./run.sh          # Enable debug logging
gdb --args ./build/shell/marathon-shell  # Debug with GDB

# Verification
ls -la ~/.local/share/marathon-apps/     # Check installed apps
diff -r ./apps/phone ~/.local/share/marathon-apps/phone  # Compare source vs installed
```

### File Location Summary

| What You Want | Where It Is |
|---------------|-------------|
| App source to edit | `./apps/<app>/` |
| Shell source to edit | `./shell/` |
| UI library to edit | `./marathon-ui/` |
| Build artifacts | `./build/` |
| Installed apps (don't edit) | `~/.local/share/marathon-apps/` |
| Build scripts | `./scripts/` |
| Documentation | `./docs/` |

---

## Additional Resources

- [App Development Guide](APP_DEVELOPMENT.md) - Creating Marathon apps

- [Developer CLI Guide](DEVELOPER_GUIDE.md) - Using marathon-dev tool
- [Code Signing Guide](CODE_SIGNING_GUIDE.md) - GPG signing for apps
