# Contributing to Marathon Shell

Thank you for your interest in contributing to Marathon Shell. This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful and professional in all interactions. Focus on constructive technical discussions.

## Getting Started

### Development Environment Setup

1. Clone the repository with submodules:
   ```bash
   git clone --recursive https://github.com/patrickjquinn/Marathon-Shell.git
   cd Marathon-Shell
   ```

2. Install dependencies (see README.md for platform-specific instructions)

3. Build the project:
   ```bash
   ./scripts/build-all.sh
   ```

4. Run the shell:
   ```bash
   ./run.sh
   ```

## Development Workflow

### File Locations

- **Source files** - Edit files in `./apps/`, `./shell/`, `./marathon-ui/`
- **Build artifacts** - Never edit files in `./build/`, `~/.local/share/marathon-apps/`

See [docs/DEVELOPMENT_WORKFLOW.md](docs/DEVELOPMENT_WORKFLOW.md) for detailed workflow information.

### Making Changes

1. Create a feature branch:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes in source files

3. Test your changes:
   ```bash
   ./run.sh
   ```

4. Validate QML if you modified QML files:
   ```bash
   ./scripts/validate-qml.sh
   ```

5. Commit your changes:
   ```bash
   git add <files>
   git commit -m "Description of changes"
   ```

6. Push to your fork and create a pull request

## Code Style

### C++ Style

Follow Qt coding conventions:

- Use `camelCase` for methods and properties
- Use `PascalCase` for class names
- Use `m_` prefix for private member variables
- Use meaningful variable names
- Comment complex logic
- Use `Q_PROPERTY` for QML-exposed properties
- Include header guards in all header files

Example:
```cpp
class NetworkManager : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)
    
public:
    explicit NetworkManager(QObject *parent = nullptr);
    bool isConnected() const { return m_connected; }
    
signals:
    void connectedChanged();
    
private:
    bool m_connected;
};
```

### QML Style

- Use `camelCase` for property names
- Use `PascalCase` for component names
- Indent with 4 spaces
- Group properties logically
- Place signal handlers after property declarations
- Use MarathonUI components instead of basic QtQuick controls

Example:
```qml
MPage {
    id: myPage
    title: "My Page"
    
    property string customProperty: "value"
    
    signal customSignal()
    
    content: MLabel {
        text: "Hello"
        color: MColors.textPrimary
    }
    
    onCustomSignal: {
        // Handle signal
    }
}
```

### File Naming

- QML files: `PascalCase.qml` (e.g., `MarathonShell.qml`)
- C++ headers: `lowercase.h` (e.g., `networkmanager.h`)
- C++ sources: `lowercase.cpp` (e.g., `networkmanager.cpp`)
- Scripts: `kebab-case.sh` (e.g., `build-apps.sh`)

## Commit Messages

Write clear, descriptive commit messages:

**Good:**
```
Add WiFi password dialog to settings

- Implement MPasswordDialog component
- Add password validation
- Connect to NetworkManager D-Bus API
- Add error handling for connection failures
```

**Bad:**
```
Fixed stuff
WIP
Updates
```

Format:
- First line: Brief summary (50 characters or less)
- Blank line
- Detailed description with bullet points if needed
- Reference issue numbers if applicable: `Fixes #123`

## Pull Request Guidelines

### Before Submitting

- Test your changes thoroughly
- Run QML validation: `./scripts/validate-qml.sh`
- Verify no new console warnings or errors
- Check that existing functionality still works
- Update documentation if needed
- Add comments for complex code

### Pull Request Description

Include:
- What changes were made
- Why the changes were necessary
- How to test the changes
- Screenshots for UI changes
- Any breaking changes or migration notes

### Review Process

- Address reviewer feedback promptly
- Make requested changes in new commits (don't force-push during review)
- Respond to review comments
- Be open to suggestions and alternative approaches

## Testing

### Manual Testing

1. Build and run the shell
2. Test the specific feature you modified
3. Test related features to check for regressions
4. Test on target platform (Linux with Wayland)
5. Check console for errors or warnings

### QML Validation

```bash
./scripts/validate-qml.sh
```

Fix any warnings or errors reported by qmllint.

### Unit Tests

If applicable, add unit tests for new C++ code:

```cpp
// tests/test_myfeature.cpp
#include <QtTest>

class TestMyFeature : public QObject {
    Q_OBJECT
    
private slots:
    void testBasicFunctionality();
};

void TestMyFeature::testBasicFunctionality() {
    // Test code
    QVERIFY(condition);
}

QTEST_MAIN(TestMyFeature)
#include "test_myfeature.moc"
```

## Documentation

### When to Update Documentation

Update documentation when you:
- Add a new feature
- Change existing behavior
- Add new configuration options
- Modify the build process
- Change the architecture

### Documentation Locations

- `README.md` - Overview and quick start
- `docs/ARCHITECTURE.md` - System architecture
- `docs/APP_DEVELOPMENT.md` - App development guide
- `docs/DEVELOPER_GUIDE.md` - Developer tools

- Other docs in `docs/` for specific topics

### Documentation Style

- Use clear, technical language
- Include code examples where helpful
- Avoid marketing language or hyperbole
- Use consistent terminology
- Keep documentation up-to-date with code changes

## Bug Reports

### Before Filing a Bug

1. Check if the issue already exists
2. Verify the issue on latest code
3. Test with debug logging: `MARATHON_DEBUG=1 ./run.sh`

### Bug Report Format

Include:
- Marathon Shell version or commit hash
- Operating system and version
- Qt version
- Steps to reproduce
- Expected behavior
- Actual behavior
- Console output (with `MARATHON_DEBUG=1`)
- Screenshots if applicable

## Feature Requests

### Proposing New Features

1. Check if the feature has been discussed
2. Explain the use case and benefits
3. Describe the proposed implementation
4. Consider alternative approaches
5. Be open to feedback and discussion

### Feature Request Format

Include:
- Description of the feature
- Use case / problem it solves
- Proposed implementation (if you have ideas)
- Mockups or examples (if applicable)
- Willingness to implement it yourself

## Community

### Getting Help

- Check documentation in `docs/`
- Search existing issues
- Create a new issue with clear description
- Be patient and respectful

### Communication Guidelines

- Be respectful and professional
- Focus on technical merit
- Provide constructive feedback
- Assume good intentions
- Help newcomers

## License

By contributing to Marathon Shell, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

If you have questions about contributing, please create an issue or reach out through the project's communication channels.

Thank you for contributing to Marathon Shell!

