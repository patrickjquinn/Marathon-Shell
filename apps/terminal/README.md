# Marathon Terminal

A powerful terminal emulator for Marathon OS, built on QTermWidget.

### Beautiful Terminal Emulation

Full-featured terminal with:
- PTY support for interactive shells
- ANSI color support
- Scrollback history
- Copy/paste
- Multiple tabs
- Hardware keyboard support

## Dependencies

### Required
- **qtermwidget** (Qt6 version) - Terminal emulation library

### Installation

**Fedora:**
```bash
sudo dnf install qtermwidget-devel
```

**Debian/Ubuntu:**
```bash
sudo apt install libqtermwidget6-0-dev
```

**Arch Linux:**
```bash
sudo pacman -S qtermwidget
```

### Build

From the Marathon Shell root:
```bash
./scripts/build-apps.sh
```

The terminal will automatically detect qtermwidget6 at build time. If not found, it will compile with a stub implementation (non-functional).

## Architecture

The terminal uses:
- **QTermWidget** for terminal emulation
- **QWidget::createWindowContainer()** to embed in QML
- **QApplication** (not QGuiApplication) for QWidget support

## Notes

⚠️ **Process Isolation**: Currently apps run in-process with the shell. Crash protection is active but not a complete solution. Multi-process architecture is planned.
