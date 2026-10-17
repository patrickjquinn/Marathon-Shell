# Marathon Shell Tests

## Running Tests

### Build with tests enabled

```bash
cd /path/to/Marathon-Shell
cmake -B build -G Ninja -DBUILD_TESTING=ON
cmake --build build
```

### Run all tests

```bash
cd build
ctest --output-on-failure
```

### Run individual test suites

```bash
# Core library tests
ctest -R Core_AppRegistry
ctest -R Core_AppPackager
ctest -R Core_PermissionManager

# Keyboard tests
ctest -R Keyboard_WordTrie
ctest -R Keyboard_WordEngine
ctest -R Keyboard_QML
```

## Test Suites

### Core: AppRegistry (15 tests)
- Empty registry state
- Register app and verify signals
- Duplicate registration rejection
- hasApp / getApp / getAppInfo lookups
- Non-existent app returns empty
- Protected app flag
- getAllAppIds enumeration
- Model data via QAbstractListModel roles
- Invalid model index handling
- Role names verification
- Multiple app type registration (Marathon, System, Native)

### Core: AppPackager (11 tests)
- Validates directory existence
- Requires manifest.json
- Validates JSON syntax
- Requires mandatory manifest fields (id, name, version, entryPoint, icon)
- Rejects empty required fields
- Requires manifest to be a JSON object
- Validates entry point file exists
- Requires package file for extraction
- Round-trip create + extract (requires zip/unzip on system)

### Core: PermissionManager (13 tests)
- Initial state verification
- Grant permission with signal
- Deny permission with signal
- Revoke previously granted permission
- Get all permissions for an app
- Permission status lifecycle (NotRequested -> Granted / Denied)
- Multiple app isolation
- Available permissions list
- Permission descriptions
- Batch set multiple permissions
- Non-existent app returns no permissions

### Keyboard: WordTrie (15 tests)
- Insert and size
- Completions (basic, max results, case insensitive, no match, empty prefix)
- Clear, empty word, very long word
- Special characters, unicode, duplicates
- Memory stress

### Keyboard: WordEngine (11 tests)
- Enabled/language properties
- Predictions, learn word, spell check
- Zero/negative max results
- Concurrent requests, empty language

### Keyboard: QML
The real `MarathonKeyboard.qml` and `InputContext` typing into a `TextInput`;
needs Keel's Silica (`KEEL_QML`).
- Typing, backspace, enter, a tapped key, shift and caps lock
- Autocorrect replacing the word, and never touching text it did not type
- Undoing a correction, double-space full stop
- Accepting a prediction with its trailing space
- Input mode from the field's hints

## Requirements

- Qt 6.4+ with Test and Core components
- Qt6QuickTest for QML tests
- Hunspell for WordEngine tests
- zip/unzip for AppPackager round-trip test (test is skipped if unavailable)

## Adding New Tests

1. Create test file in the appropriate subdirectory (`tests/core/`, `tests/keyboard/`)
2. Add the target to the corresponding `CMakeLists.txt`
3. Register with `add_test(NAME ... COMMAND ...)`
4. Run `ctest --output-on-failure` to verify
