# Marathon Keyboard

A high-performance, BlackBerry 10-inspired virtual keyboard for Qt/QML applications.

## Features

- **Zero-Latency Input**: Optimized for instant visual feedback before text commit
- **BB10-Style Predictions**: Word predictions and auto-correction
- **Long-Press Alternates**: Access special characters via long-press
- **Modular Architecture**: Easily integrate into any Qt/QML project
- **Hardware-Accelerated Rendering**: Smooth animations and effects
- **Dark Theme**: Beautiful black and dark grey color scheme

## Architecture

```
marathon-keyboard/
├── qml/
│   ├── Core/           # Main keyboard container and performance monitoring
│   ├── UI/             # Key components, popups, prediction bar
│   ├── Layouts/        # QWERTY and symbol layouts
│   ├── Data/           # Dictionary and auto-correction
│   └── Input/          # Input context management
└── src/                # C++ backend for Qt Input Method integration
```

## Usage

### Basic Integration

```qml
import QtQuick
import MarathonKeyboard.Core 1.0

Item {
    MarathonKeyboard {
        id: keyboard
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        
        // Set scale factor for responsive sizing
        scaleFactor: 1.0
        
        // Handle key presses
        onKeyPressed: function(text) {
            // Commit text via Qt Input Method Engine
            Qt.inputMethod.commit(text)
        }
        
        // Handle logging (optional)
        onLogMessage: function(component, message, level) {
            console.log("[" + component + "] " + message)
        }
        
        // Handle haptic feedback (optional)
        onHapticRequested: function(intensity) {
            // Trigger haptic feedback: "light", "medium", "heavy"
        }
    }
}
```

### Integration with Marathon OS Shell

See `shell/qml/components/VirtualKeyboard.qml` for a complete example of:
- Shell service integration (Logger, HapticService)
- Qt Input Method Engine wiring
- Keyboard show/hide logic

## API

### Properties

- `scaleFactor: real` - Scale factor for responsive sizing (default: 1.0)
- `active: bool` - Whether keyboard is active/visible
- `currentLayout: string` - Current layout ("qwerty" or "symbols")
- `shifted: bool` - Shift key state
- `capsLock: bool` - Caps lock state

### Signals

- `keyPressed(string text)` - Emitted when a key is pressed
- `backspace()` - Emitted when backspace is pressed
- `enter()` - Emitted when enter is pressed
- `logMessage(string component, string message, string level)` - Logging callback
- `hapticRequested(string intensity)` - Haptic feedback callback
- `dismissRequested()` - Emitted when dismiss button is clicked

### Functions

- `show()` - Show the keyboard
- `hide()` - Hide the keyboard

## C++ Backend

The keyboard includes a C++ Input Method Engine for proper Qt integration:

```cpp
#include <marathoninputmethodengine.h>

// In your main.cpp:
MarathonInputMethodEngine *ime = new MarathonInputMethodEngine(&app);
engine.rootContext()->setContextProperty("InputMethodEngine", ime);
```

## Building

marathon-keyboard is part of the Marathon OS monorepo but can be used independently.

### As Part of Marathon OS

```bash
cmake -B build
cmake --build build
```

### Standalone

```bash
cd marathon-keyboard
cmake -B build
cmake --build build
cmake --install build --prefix /path/to/install
```

## Dependencies

- Qt 6.5 or later
- Qt Qml
- Qt Quick
- Qt Gui

## Performance

- **Key Press Latency**: < 1ms from touch to visual feedback
- **Prediction Generation**: Background thread, non-blocking
- **Frame Rate**: 60 FPS maintained during typing

## Customization

The keyboard supports extensive customization:

- **Layouts**: Modify `qml/Layouts/` for custom key arrangements
- **Themes**: Adjust colors in `qml/UI/Key.qml`
- **Predictions**: Customize dictionary in `qml/Data/Dictionary.qml`
- **Auto-Correction**: Modify rules in `qml/Data/AutoCorrect.qml`

## License

See LICENSE in the repository root.

## Contributing

This keyboard is part of Marathon OS. Contributions welcome!

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Acknowledgments

Inspired by BlackBerry 10's excellent virtual keyboard design.

