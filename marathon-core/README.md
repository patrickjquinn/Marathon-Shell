# Marathon Core Library

**Version:** 1.0.0  
**Type:** Shared C++ Library  
**License:** Same as Marathon OS

## Overview

`MarathonCore` is a shared library that provides app management infrastructure for Marathon OS. It follows a monorepo architecture similar to `marathon-ui`, allowing multiple components to share the same codebase without duplication.

## Architecture

```
Marathon-Shell (monorepo)
├── marathon-core/              ← Shared app management library
│   ├── src/
│   │   ├── marathonapppackager.{h,cpp}    # .marathon package creation
│   │   ├── marathonappverifier.{h,cpp}    # GPG signature verification
│   │   ├── marathonappinstaller.{h,cpp}   # App installation logic
│   │   ├── marathonappregistry.{h,cpp}    # App registry/catalog
│   │   └── marathonappscanner.{h,cpp}     # App discovery/scanning
│   └── CMakeLists.txt
│
├── shell/                      ← Links to MarathonCore
│   └── marathon-shell-bin      (uses MarathonCore for app management)
│
└── tools/marathon-dev/         ← Links to MarathonCore
    └── marathon-dev            (uses MarathonCore for CLI operations)
```

## Components

### 1. `MarathonAppPackager`
- Creates `.marathon` package files (ZIP-based)
- Extracts and validates package structure
- Handles compression and file organization

### 2. `MarathonAppVerifier`
- GPG signature verification
- Package integrity checking
- Security validation

### 3. `MarathonAppInstaller`
- Installs apps from directories or packages
- Handles uninstallation
- Manages installation paths and permissions
- Coordinates with packager and verifier

### 4. `MarathonAppRegistry`
- In-memory app catalog
- App metadata storage
- Quick lookup by app ID

### 5. `MarathonAppScanner`
- Scans filesystem for Marathon apps
- Parses `manifest.json` files
- Populates the registry

## Usage

### In CMake Projects

```cmake
# Link to MarathonCore
target_link_libraries(your-target PRIVATE MarathonCore)

# Include headers (automatically available)
#include "marathonapppackager.h"
#include "marathonappverifier.h"
#include "marathonappinstaller.h"
```

### In C++ Code

```cpp
#include "marathonapppackager.h"
#include "marathonappverifier.h"

// Package an app
MarathonAppPackager packager;
if (packager.packageDirectory("/path/to/app", "output.marathon")) {
    qDebug() << "Package created successfully";
}

// Verify a package
MarathonAppVerifier verifier;
auto result = verifier.verifyDirectory("/path/to/app");
if (result == MarathonAppVerifier::Valid) {
    qDebug() << "Signature valid";
}
```

## Benefits of Shared Library Approach

1. **No Code Duplication**: Single source of truth for app management
2. **Consistent Behavior**: Shell and dev tool use identical logic
3. **Easier Testing**: Test the library once, benefits all consumers
4. **Better Maintainability**: Bug fixes automatically apply everywhere
5. **Reduced Build Time**: Library compiled once, linked multiple times
6. **Follows Marathon Pattern**: Same structure as `marathon-ui`

## Dependencies

- **Qt6::Core**: Core Qt functionality
- **System Tools**: `zip`, `unzip`, `gpg` (external processes)

## Installation

```bash
cmake -B build
cmake --build build
sudo cmake --install build

# Library installed to: /usr/lib64/libMarathonCore.so.1
# Headers installed to: /usr/include/marathon-core/
```

## Comparison: Before vs After

### Before (❌ Bad)
```cmake
# tools/marathon-dev/CMakeLists.txt
set(SOURCES
    main.cpp
    ../../shell/src/marathonapppackager.cpp  # DUPLICATE compilation
    ../../shell/src/marathonappverifier.cpp  # DUPLICATE compilation
    ../../shell/src/marathonappinstaller.cpp
    ../../shell/src/marathonappregistry.cpp
    ../../shell/src/marathonappscanner.cpp
)
```

**Problems:**
- Sources compiled twice (once for shell, once for dev tool)
- Tight coupling via relative paths
- Harder to test in isolation
- Changes require rebuilding both targets

### After (✅ Good)
```cmake
# tools/marathon-dev/CMakeLists.txt
set(SOURCES
    main.cpp
)
target_link_libraries(marathon-dev PRIVATE MarathonCore)
```

**Benefits:**
- Sources compiled once as shared library
- Clean dependency management
- Easy to test library independently
- Changes only rebuild library consumers if ABI changes

## Development

### Building
```bash
cd /path/to/Marathon-Shell
cmake -B build
cmake --build build --target MarathonCore
```

### Testing
```bash
# Unit tests (if available)
ctest --test-dir build -R MarathonCore

# Verify linking
ldd build/tools/marathon-dev/marathon-dev | grep MarathonCore
ldd build/shell/marathon-shell-bin | grep MarathonCore
```

## Future Enhancements

- Add unit tests directly in `marathon-core/tests/`
- Export CMake package config for easier external consumption
- Add C API for potential language bindings
- Implement async variants using Qt's threading primitives
- Add progress callbacks for long-running operations

