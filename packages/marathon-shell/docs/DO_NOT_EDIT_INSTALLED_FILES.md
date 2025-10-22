# CRITICAL: How to Prevent Editing Wrong Files

## The Problem That Was Fixed

**What happened:** I edited files in `~/.local/share/marathon-apps/` (installed copies) instead of `./apps/` (source files). This caused hours of wasted time because installed files are overwritten on every build.

---

## Safeguards Now in Place

### 1. **Warning File in Install Directory**
Location: `~/.local/share/marathon-apps/DO_NOT_EDIT_WARNING.txt`

Explains that files in this directory are temporary copies.

### 2. **Marker Files in Each App**
Location: `~/.local/share/marathon-apps/<app>/.do-not-edit`

Each installed app now contains a `.do-not-edit` file with a warning.

### 3. **Build Script Warnings**
`./scripts/build-apps.sh` now prints:
```
⚠️  WARNING: Apps in ~/.local/share/marathon-apps are installed copies!
   Edit source files in ./apps/ instead
```

### 4. **Documentation**
Created `docs/DEVELOPMENT_WORKFLOW.md` explaining the correct workflow.

---

## Correct Workflow (ALWAYS FOLLOW THIS)

### ✅ To Make Changes:
1. Edit source files in: `./apps/<app>/`
2. Run: `./run.sh`
3. Changes are automatically built and installed

### ❌ NEVER Do This:
- Open files in `~/.local/share/marathon-apps/` in your editor
- Make changes to files in `~/.local/share/marathon-apps/`
- Run the shell without rebuilding apps after making changes

---

## File Locations Reference

| What | Where | Editable? |
|------|-------|-----------|
| **App Sources** | `./apps/` | ✅ YES - EDIT THESE |
| **Installed Apps** | `~/.local/share/marathon-apps/` | ❌ NO - AUTO-GENERATED |
| **Shell Source** | `./shell/` | ✅ YES - EDIT THESE |
| **MarathonUI Library** | `./shell/qml/MarathonUI/` | ✅ YES - EDIT THESE |
| **Build Artifacts** | `./build/`, `./build-apps/` | ❌ NO - AUTO-GENERATED |

---

## How `./run.sh` Works

```
./run.sh
├── 1. Builds Marathon Shell (C++ + QML)
│   └── Output: ./build/shell/marathon-shell
├── 2. Runs ./scripts/build-apps.sh
│   ├── Cleans ~/.local/share/marathon-apps/*
│   ├── Builds apps from ./apps/
│   ├── Installs to ~/.local/share/marathon-apps/
│   └── Adds warning files
└── 3. Launches the shell
```

**Key Point:** Every time you run `./run.sh`, installed apps are **deleted and rebuilt from source**.

---

## Quick Commands

```bash
# Full rebuild and run (use this 99% of the time)
./run.sh

# Rebuild only apps (if shell didn't change)
./scripts/build-apps.sh

# Rebuild only shell (if apps didn't change)
cd build && make -j$(sysctl -n hw.ncpu)

# Verify what's installed
ls -la ~/.local/share/marathon-apps/

# Check for warning markers
cat ~/.local/share/marathon-apps/DO_NOT_EDIT_WARNING.txt

# Verify source vs installed (should be identical after build)
diff -r ./apps/phone ~/.local/share/marathon-apps/phone
```

---

## If You Accidentally Edit Installed Files

**Don't panic!** Just:

1. Discard changes in `~/.local/share/marathon-apps/`
2. Make the same edits in `./apps/`
3. Run `./run.sh`

The installed files will be overwritten with your source changes.

---

## For AI Assistants / Future Contributors

**ALWAYS:**
- Check if you're editing `./apps/` (source) or `~/.local/share/marathon-apps/` (installed)
- Use `./run.sh` to test changes
- Read `DO_NOT_EDIT_WARNING.txt` before editing any marathon-apps files

**NEVER:**
- Edit files in `~/.local/share/marathon-apps/`
- Assume installed files are the source of truth
- Skip running `./run.sh` after making changes

---

## Technical Details

### Build System Flow

1. **Source Location:** `./apps/<app>/`
   - Contains `.qml` files, `manifest.json`, `qmldir`, etc.
   - Managed by CMake in `./apps/CMakeLists.txt`

2. **Build Process:** `./scripts/build-apps.sh`
   - Runs CMake with `MARATHON_APPS_DIR=~/.local/share/marathon-apps`
   - Compiles any C++ plugins
   - Copies QML files and resources

3. **Install Location:** `~/.local/share/marathon-apps/<app>/`
   - Shell loads apps from here at runtime
   - Cleaned and rebuilt on every build
   - **Not tracked by git** (in `.gitignore`)

### Why This Design?

- **Separation of concerns:** Source files stay clean, build artifacts separate
- **Standard Unix convention:** Source in `/path/to/project`, installed files in `~/.local/share/`
- **Allows future package management:** Apps can be distributed separately from shell
- **Clean rebuilds:** No stale files from previous builds

---

## Summary

**Golden Rule:** If you see `~/.local/share/marathon-apps/` in the file path, **DON'T EDIT IT**.

Always edit files in `./apps/` and run `./run.sh`.

