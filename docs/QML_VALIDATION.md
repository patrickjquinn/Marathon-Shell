# QML Build-Time Validation Integration

## Overview
We've integrated **qmllint** into the CMake build system to catch QML errors **before runtime**, preventing issues like:
- `QtObject` components containing child components (which QtObject doesn't support)
- Missing imports
- Type mismatches
- Structural errors

## What Was Added

### 1. CMake Module (`cmake/QMLLint.cmake`)
- Finds `qmllint` executable automatically
- Creates validation targets that run **before** building
- Sets up proper QML import paths for validation
- Makes builds **fail** if qmllint finds errors (not just warnings)

### 2. Integration Points

#### Shell (`shell/CMakeLists.txt`)
- Validates all shell QML files before building
- Target: `marathon-shell_qmllint`

#### MarathonUI Modules (all 8 modules)
- Each module validates its QML files before building
- Targets: `marathon-ui-theme_qmllint`, `marathon-ui-core_qmllint`, etc.

## How It Works

1. **Before Build**: CMake runs `qmllint` on all QML files
2. **If Errors Found**: Build **fails immediately** with clear error messages
3. **If Successful**: Build proceeds normally

## Example Error Detection

qmllint will catch errors like:
```qml
//  ERROR: QtObject cannot have child components
QtObject {
    Connections { ... }  // This will fail at build time!
}
```

```qml
//  ERROR: Missing import
Item {
    MButton { ... }  // MarathonUI.Core not imported - caught at build time!
}
```

## Usage

The validation runs automatically during normal builds:
```bash
cmake --build build  # qmllint runs automatically before compiling
```

To run validation manually:
```bash
cmake --build build --target marathon-shell_qmllint
```

## Configuration

QML linting rules are configured in:
- `.qmllint.ini` (root)
- `shell/.qmllint.ini` (shell-specific)

## Benefits

1. **Early Error Detection**: Catch structural errors before runtime
2. **Faster Debugging**: Know immediately if QML is invalid
3. **CI/CD Integration**: Automated validation in build pipelines
4. **Better IDE Support**: Works with QML Language Server (qmlls)

## Notes

- `qmllint` may show warnings about `anchors` and `MarathonUI` imports during development - these are expected and don't fail the build
- Only actual **errors** fail the build (warnings are shown but don't block)
- If `qmllint` is not found, builds continue with a warning (graceful degradation)

