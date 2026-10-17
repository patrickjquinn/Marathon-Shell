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

3. Test your changes: run the test suite (see [Testing](#testing)) and try
   the change in the shell:
   ```bash
   ./run.sh
   ```

4. Validate QML if you modified QML files:
   ```bash
   ./scripts/validate-qml.sh
   ```

5. Commit your changes, one logical change per commit (see
   [Commit Messages](#commit-messages)):
   ```bash
   git add <files>
   git commit -m "fix(hub): a tap opens the app the notification came from"
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

Commits follow [Conventional Commits](https://www.conventionalcommits.org/),
and the release notes are generated from their subjects, so there is no
changelog file to edit: the subject is the changelog entry.

```
type(scope): what changes, as the user would notice it

Why the change was needed and anything a reviewer should know.
Fixes #123
```

| Type | Release notes |
|---|---|
| `feat` | Features |
| `fix` | Fixes |
| `perf` | Performance |
| `revert` (or git revert's default subject) | Reverted |
| `build`, `chore`, `ci`, `docs`, `refactor`, `style`, `test` | left out |
| any type with `!`, e.g. `feat(store)!:`, or a `BREAKING CHANGE:` footer | Breaking changes |

- The scope is the area touched: `hub`, `settings`, `compositor`,
  `packaging`, an app name. `git log --oneline` shows the ones in use.
- Write the subject as a sentence about behaviour, lower case, no full
  stop: `fix(hub): a tap opens the app the notification came from`.
- One logical change per commit, and the body says why
  ([docs/CODING_RULES.md](docs/CODING_RULES.md) section G). No
  generated-by or co-author trailers for tools.

CI fails a pull request with a commit whose subject is not of this form.
To check your branch and preview the notes it adds, install
[git-cliff](https://git-cliff.org) (the `git-cliff` package on Alpine and
Arch, `cargo install git-cliff`, or a release binary) and run:

```bash
git cliff origin/main..HEAD
```

The rules live in [cliff.toml](cliff.toml).

## Pull Request Guidelines

### Before Submitting

- Test your changes thoroughly
- Run QML validation: `./scripts/validate-qml.sh`
- Verify no new console warnings or errors
- Check that existing functionality still works
- Update documentation if needed
- Add comments for complex code

### Pull Request Description

GitHub fills the description from
[.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md).
Fill in every section:
- **What changed and why**: the change and the problem it solves; link issues
- **Commands run**: each build and test command and its result
- **Test evidence**: the tests added or changed and what they prove, or how
  you verified what no test covers
- **UI changes**: devices, DPI, touch input, light and dark mode, and
  before and after screenshots; delete the section if there is no UI change

CI builds and runs the test suite on every pull request
(`.github/workflows/ci.yml`; reproduce it with
`scripts/ci/build-and-test.sh`) and checks the commit subjects.

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

### Automated Tests

Every test runs through CTest:

```bash
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON -DKEEL_QML=/path/to/keel/build/qml
cmake --build build
QT_QPA_PLATFORM=offscreen ctest --test-dir build --output-on-failure
```

The Keel Silica QML suites are registered only when `KEEL_QML` (or an
installed keel-silica) provides `Sailfish/Silica`.

A test only counts once CTest runs it. Register it where its kind lives:

| Test | Where | Registration |
|---|---|---|
| C++ (QtTest) | `tests/core/`, `tests/shell/`, `tests/keyboard/cpp/` | `add_executable` and `add_test` in that directory's `CMakeLists.txt` |
| Shell QML | `tests/ui/tst_*.qml` | none: `Qml_tests_ui` runs the directory |
| App QML | `apps/<app>/tests/tst_*.qml` | none for a new file; a new app needs a `tests/run.sh` and its `apps/<app>/tests` added to the suite list in `tests/CMakeLists.txt` |
| Marathon.Silica QML | `marathon-silica/tests/tst_*.qml` | none: `Qml_marathon-silica_tests` runs the directory |
| Rust | `#[test]` in a crate of the `crates/` workspace | none: `Rust_Crates` runs `cargo test --workspace` |
| Lint scripts | `tests/lint/` | `add_test` in `tests/CMakeLists.txt` |

QtQuickTest runs only `TestCase` functions whose names start with `test_`.
`Lint_TestReachability` (`tests/lint/check-test-reachability.py`) fails
when a test exists that no registration reaches, or a registration names
a path that is gone; run it on its own with
`python3 tests/lint/check-test-reachability.py`.

A C++ test looks like this:

```cpp
// tests/core/test_myfeature.cpp
# include <QtTest>

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
# include "test_myfeature.moc"
```

and is registered in `tests/core/CMakeLists.txt`:

```cmake
add_executable(test_core_myfeature
    test_myfeature.cpp
    ../../shell/src/services/myfeature.cpp
)
target_link_libraries(test_core_myfeature Qt6::Test Qt6::Core)
add_test(NAME Core_MyFeature COMMAND test_core_myfeature)
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

