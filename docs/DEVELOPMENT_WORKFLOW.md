# Marathon Shell Development Workflow

## ⚠️ CRITICAL: Where to Edit Files

### ✅ ALWAYS EDIT SOURCE FILES HERE:
```
/Users/patrick.quinn/Developer/personal/Marathon-Shell/apps/
```

### ❌ NEVER EDIT INSTALLED COPIES HERE:
```
~/.local/share/marathon-apps/
```

**Why?** The `~/.local/share/marathon-apps/` directory contains **temporary installed copies** that are **overwritten** every time you run `./run.sh`.

---

## Development Workflow

### 1. Make Changes to Apps
Edit source files in:
```
./apps/phone/pages/DialerPage.qml
./apps/music/MusicApp.qml
etc.
```

### 2. Build and Run
Simply run:
```bash
./run.sh
```

This will:
1. Build the Marathon Shell
2. Build all apps from `./apps/`
3. **Clean and reinstall** apps to `~/.local/share/marathon-apps/`
4. Launch the shell

### 3. Quick Rebuild (Apps Only)
If you only changed apps (not the shell):
```bash
./scripts/build-apps.sh && ./build/shell/marathon-shell.app/Contents/MacOS/marathon-shell
```

---

## File Locations

| Type | Location | Purpose |
|------|----------|---------|
| **App Sources** | `./apps/` | Edit these! |
| **Installed Apps** | `~/.local/share/marathon-apps/` | Don't touch! Auto-generated |
| **Shell Sources** | `./shell/` | Edit these! |
| **MarathonUI Library** | `./shell/qml/MarathonUI/` | Edit these! |
| **Build Output** | `./build/` | Auto-generated |

---

## What `./run.sh` Does

```bash
./run.sh
├── Builds shell (cmake --build build)
├── Runs build-apps.sh
│   ├── Cleans ~/.local/share/marathon-apps/*
│   ├── Builds apps from ./apps/
│   └── Installs to ~/.local/share/marathon-apps/
└── Launches marathon-shell
```

---

## Common Mistakes to Avoid

❌ **DON'T:**
- Open files in `~/.local/share/marathon-apps/` in your editor
- Make changes to files in `~/.local/share/marathon-apps/`
- Expect changes in `~/.local/share/marathon-apps/` to persist

✅ **DO:**
- Edit files in `./apps/`
- Run `./run.sh` after making changes
- Check `./apps/` first when debugging

---

## Quick Reference

```bash
# Full rebuild and run
./run.sh

# Just rebuild apps
./scripts/build-apps.sh

# Just rebuild shell
cd build && make -j$(sysctl -n hw.ncpu)

# Check what's installed
ls -la ~/.local/share/marathon-apps/

# Verify source vs installed
diff -r ./apps/phone ~/.local/share/marathon-apps/phone
```

