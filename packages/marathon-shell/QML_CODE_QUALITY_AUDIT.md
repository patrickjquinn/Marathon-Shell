# Marathon Shell - QML Code Quality Audit

**Date:** October 19, 2025  
**Tool:** qmllint (Qt 6.x)  
**Files Analyzed:** 145 QML files  
**Reference:** [Qt qmllint Documentation](https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html)

---

## Executive Summary

A comprehensive audit of all shell QML files revealed **4,596 warnings** across multiple categories. The codebase has significant technical debt that impacts maintainability, performance, and code quality.

### Critical Statistics

| Warning Category | Count | Severity |
|-----------------|-------|----------|
| **Unqualified Access** | 3,723 | 🔴 HIGH |
| **Missing Properties** | 555 | 🔴 HIGH |
| **Import Issues** | 166 | 🟡 MEDIUM |
| **PropertyChanges Parsing** | 62 | 🟡 MEDIUM |
| **Unresolved Types** | 49 | 🟡 MEDIUM |
| **Unused Imports** | 36 | 🟢 LOW |
| **Duplicated Names** | 3 | 🟡 MEDIUM |
| **Incompatible Types** | 1 | 🔴 HIGH |
| **Duplicate Bindings** | 1 | 🟡 MEDIUM |

---

## Top Priority Issues

### 1. **Unqualified Access (3,723 warnings)** 🔴

**Problem:** Properties accessed without explicit qualification, making code harder to understand and debug.

**Example:**
```qml
// ❌ Bad - Unqualified
property int volume: AudioManager.volume

// ✅ Good - Qualified
property int volume: root.audioManager.volume
```

**Impact:**
- Makes code harder to reason about
- Can lead to subtle bugs when scope changes
- Prevents qmlcachegen optimization
- Hurts IDE autocomplete

**Recommendation:** Add `pragma ComponentBehavior: Bound` to all files and explicitly qualify all property accesses.

---

### 2. **Missing Properties (555 warnings)** 🔴

**Problem:** Attempting to assign to or access properties that don't exist on the target object.

**Common Issues:**
- Assigning to non-existent default properties
- Using `target:` in PropertyChanges (deprecated pattern)
- Accessing properties that were removed or renamed

**Example:**
```qml
// ❌ Bad - Cannot assign to non-existent default property
Timer {
    interval: 1000
    running: true
}

// ✅ Good - Explicit child
Item {
    Timer {
        interval: 1000
        running: true
    }
}
```

---

### 3. **PropertyChanges Anti-Pattern (62 warnings)** 🟡

**Problem:** Using old `target:` syntax in PropertyChanges which is custom-parsed and error-prone.

**Example:**
```qml
// ❌ Bad - Old syntax
State {
    PropertyChanges { target: navBar; visible: true; z: 10 }
}

// ✅ Good - Modern syntax
State {
    PropertyChanges {
        navBar.visible: true
        navBar.z: 10
    }
}
```

**Files Affected:**
- `MarathonShell.qml` (primary offender with 62 occurrences)

---

### 4. **Import Issues (166 warnings)** 🟡

**Problems:**
- Missing qmldir entries for components
- Unused imports cluttering files
- Incorrect module paths

**Specific Issues:**
```
- theme/Theme.qml is listed but does not exist
- theme/Layout.qml is listed but does not exist  
- MTabControl.qml is listed but does not exist
```

**Action Required:** Clean up qmldir files and remove references to non-existent components.

---

## File-Specific Issues

### High-Priority Files (>50 warnings each)

1. **`MarathonShell.qml`**
   - 62 PropertyChanges warnings
   - Multiple missing property assignments
   - Core shell file - needs immediate attention

2. **`SystemStatusStore.qml`** 
   - Extensive unqualified access
   - Incorrect property bindings
   - Ambiguous signal names

3. **`SystemControlStore.qml`**
   - Unqualified access to managers
   - Complex property chains
   - Needs refactoring

4. **`AlarmManager.qml`**
   - Missing default property assignments
   - Timer not properly contained
   - Signal handling issues

5. **`CellularManager.qml`**
   - Duplicated signal names
   - Platform-specific code not properly guarded
   - Timer containment issues

---

## Recommended Actions

### Phase 1: Quick Wins (1-2 days)

1. **Remove Unused Imports** (36 files)
   - Search for `Unused import` warnings
   - Delete unused import statements
   - Improves load time

2. **Fix qmldir Files**
   - Remove non-existent component references
   - Update module paths
   - Validate all qmldir entries

3. **Add Missing Files or Remove References**
   - `theme/Theme.qml`
   - `theme/Layout.qml`
   - `MTabControl.qml`

### Phase 2: Medium Priority (1 week)

4. **Fix PropertyChanges Syntax** (62 occurrences)
   - Update `MarathonShell.qml` State transitions
   - Use modern syntax: `target.property: value`
   - Remove all `target:` bindings

5. **Fix Missing Property Assignments** (555 occurrences)
   - Identify components with missing default properties
   - Properly contain Timers, Connections, etc.
   - Use explicit Item parents where needed

6. **Fix Duplicated Names** (3 files)
   - Rename duplicate signals in:
     - `AmbientLightSensor.qml`
     - `CellularManager.qml`

### Phase 3: Major Refactoring (2-3 weeks)

7. **Add Pragma and Qualify Access** (3,723 occurrences)
   ```qml
   pragma ComponentBehavior: Bound
   ```
   - Add to every QML file
   - Explicitly qualify all property accesses
   - Use IDs for parent component access

8. **Fix Unresolved Types** (49 occurrences)
   - Ensure all types are properly imported
   - Check C++ type registrations
   - Validate QML module structures

9. **Type Safety Improvements**
   - Fix incompatible type assignments
   - Add explicit type annotations
   - Use typed property declarations

---

## Configuration Recommendations

### Create Strict `.qmllint.ini`

Based on [Qt documentation](https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html), create stricter settings:

```ini
[Warnings]
UnqualifiedAccess=warning
MissingProperty=warning
Quick.PropertyChangesParsed=warning
UnresolvedType=warning
DuplicatedName=error
IncompatibleType=error
DuplicatePropertyBinding=error
UnusedImports=info
```

### Enable Compiler Warnings

```bash
qmllint --compiler warning shell/qml/**/*.qml
```

This will show additional warnings about code that can't be compiled by qmlsc.

---

## Benefits of Fixing These Issues

1. **Performance**
   - Enables qmlcachegen optimizations
   - Reduces runtime property lookups
   - Faster startup times

2. **Maintainability**
   - Explicit property access improves readability
   - IDE autocomplete works better
   - Easier to refactor

3. **Reliability**
   - Catches bugs at lint-time instead of runtime
   - Type safety prevents crashes
   - Better error messages

4. **Developer Experience**
   - Better IDE integration
   - Faster debugging
   - Clearer code ownership

---

## Terminal App Issues

**Note:** The terminal app currently doesn't function despite loading successfully. The C++ `TerminalEngine` is properly compiled and registered, but the QML interface may have issues. This should be investigated separately from the general code quality audit.

### Potential Issues:
1. Signal/slot connections may not be working
2. QProcess initialization might be failing silently
3. Terminal output TextArea binding could be broken
4. Input handling may not be routing to the engine

**Recommendation:** Add comprehensive logging to `TerminalEngine.cpp` to trace execution flow and identify where the disconnect occurs.

---

## Next Steps

1. ✅ **Audit Complete** - This document
2. ⏭️ **Prioritize Fixes** - Create GitHub issues for each category
3. ⏭️ **Set Up CI** - Add qmllint to CI/CD pipeline
4. ⏭️ **Incremental Fixes** - Fix file-by-file, starting with core components
5. ⏭️ **Enforce Standards** - Block PRs with new qmllint errors

---

## Tools and Resources

- **qmllint**: `qmllint <file>.qml`
- **Batch linting**: `qmllint shell/qml/**/*.qml`
- **JSON output**: `qmllint --json output.json shell/qml/**/*.qml`
- **Documentation**: https://doc.qt.io/qt-6/qtqml-tooling-qmllint.html
- **QML Lint Errors Guide**: https://doc.qt.io/qt-6/qmllint-warnings-and-errors.html

---

*Generated by AI assistant based on qmllint analysis of Marathon Shell codebase*

