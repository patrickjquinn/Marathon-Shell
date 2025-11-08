# Marathon Shell Tests

This directory contains unit and integration tests for security-critical Marathon Shell components.

## Running Tests

### Build Tests

```bash
cd /path/to/Marathon-Shell
cmake -B build -DBUILD_TESTING=ON
cmake --build build
```

### Run All Tests

```bash
cd build
ctest --output-on-failure
```

### Run Individual Tests

```bash
# Test app packager
./tests/test_apppackager

# Test app verifier (requires GPG)
./tests/test_appverifier

# Test permission manager
./tests/test_permissionmanager
```

## Test Coverage

### AppPackager Tests
- Create package from app directory
- Extract package to directory
- Handle invalid app directories
- Validate manifest presence
- Validate manifest structure

### AppVerifier Tests
- Verify valid GPG signatures
- Detect invalid signatures
- Detect tampered manifests
- Handle missing signatures (dev mode)
- Handle missing manifests
- Sign manifests with GPG
- Trusted key management

### PermissionManager Tests
- Grant/deny permissions
- Check permission status
- Request permissions (shows dialog)
- Revoke permissions
- Get app permissions
- Permission persistence
- Available permissions list
- Permission descriptions

## Requirements

### For All Tests
- Qt 6.5+
- CMake 3.16+

### For GPG Signing Tests
- GPG (GnuPG) installed
- GPG key configured
- Or tests will be skipped gracefully

## Test Results

Tests use Qt Test framework and output results in standard format:

```
********* Start testing of TestAppPackager *********
PASS   : TestAppPackager::initTestCase()
PASS   : TestAppPackager::testCreatePackage()
PASS   : TestAppPackager::testExtractPackage()
PASS   : TestAppPackager::testInvalidAppDirectory()
PASS   : TestAppPackager::cleanupTestCase()
Totals: 5 passed, 0 failed, 0 skipped, 0 blacklisted
********* Finished testing of TestAppPackager *********
```

## Continuous Integration

Tests are automatically run in CI/CD pipeline:
- On every commit
- Before merges
- Before releases

## Adding New Tests

1. Create `test_component.cpp` in this directory
2. Include component header
3. Write test cases using Qt Test framework
4. Add to `CMakeLists.txt`
5. Run and verify tests pass

Example:

```cpp
#include <QTest>
#include "../shell/src/mycomponent.h"

class TestMyComponent : public QObject {
    Q_OBJECT
    
private slots:
    void testSomething() {
        MyComponent component;
        QVERIFY(component.doSomething());
    }
};

QTEST_MAIN(TestMyComponent)
#include "test_mycomponent.moc"
```

## Debugging Tests

Run tests with verbose output:

```bash
./test_apppackager -v2
```

Run specific test function:

```bash
./test_apppackager testCreatePackage
```

## Known Issues

- GPG tests may fail if GPG is not configured
- Some tests require temporary file system access
- Tests clean up temporary files automatically

## Contributing

When adding new features to Marathon Shell:
1. Write tests for security-critical code
2. Ensure tests pass before submitting PR
3. Update this README if adding new test suites

