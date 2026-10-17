#!/usr/bin/env python3
"""check-test-reachability.py against small source trees."""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "reachability", Path(__file__).with_name("check-test-reachability.py"))
reachability = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(reachability)

TREE = {
    "CMakeLists.txt": "project(t)\nif(BUILD_TESTING)\n  add_subdirectory(tests)\nendif()\nadd_subdirectory(crates)\n",
    "tests/CMakeLists.txt": """
add_subdirectory(core)
add_test(NAME Lint_A COMMAND sh ${CMAKE_SOURCE_DIR}/tests/lint/check-a.sh ${CMAKE_SOURCE_DIR})
add_test(NAME Py COMMAND python3 ${CMAKE_SOURCE_DIR}/tools/x/test_x.py)
# foreach(suite apps/gone/tests) is a comment
foreach(suite tests/ui apps/notes/tests)
    string(REPLACE "/" "_" name "Qml_${suite}")
    add_test(NAME ${name} COMMAND sh ${CMAKE_SOURCE_DIR}/${suite}/run.sh)
endforeach()
""",
    "tests/core/CMakeLists.txt": """
set(SHARED ../../src/a.cpp)
add_executable(test_core_a
    test_a.cpp
    ${SHARED}
)
add_test(NAME Core_A COMMAND test_core_a)
add_executable(test_core_b test_b.cpp)
add_test(NAME Core_B COMMAND dbus-run-session -- $<TARGET_FILE:test_core_b>)
""",
    "tests/core/test_a.cpp": "QTEST_MAIN(TestA)\n",
    "tests/core/test_b.cpp": "QTEST_GUILESS_MAIN(TestB)\n",
    "tests/lint/check-a.sh": "true\n",
    "tools/x/test_x.py": "\n",
    "tests/ui/run.sh": 'exec qmltestrunner -input "$here"\n',
    "tests/ui/tst_a.qml": "TestCase { function test_a() {} }\n",
    "tests/ui/stubs/tst_nested.qml": "TestCase {}\n",
    "apps/notes/tests/run.sh": 'exec qmltestrunner -input "$here"\n',
    "apps/notes/tests/tst_notes.qml": "TestCase {\n    function test_one() {}\n    function helper() {}\n}\n",
    "crates/CMakeLists.txt": "add_test(NAME Rust_Crates COMMAND ${CARGO} test --workspace WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})\n",
    "crates/Cargo.toml": '[workspace]\nmembers = ["a"]\n',
    "crates/a/Cargo.toml": '[package]\nname = "a"\n',
    "crates/a/src/main.rs": "mod b;\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn t() {}\n}\n",
    "crates/a/src/b.rs": "pub mod c;\n",
    "crates/a/src/b/c.rs": "#[test]\nfn t() {}\n",
    "crates/a/tests/it.rs": "#[test]\nfn t() {}\n",
    "third-party/lib/test_skip.cpp": "QTEST_MAIN(X)\n",
}


class Reachability(unittest.TestCase):
    def tree(self, changes=None):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        files = dict(TREE)
        files.update(changes or {})
        for name, text in files.items():
            if text is None:
                continue
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        return root

    def problems(self, changes=None):
        root = self.tree(changes)
        return reachability.check(root.resolve())

    def assertFlags(self, changes, *needles):
        found = self.problems(changes)
        for needle in needles:
            self.assertTrue(any(needle in p for p in found), f"{needle!r} not in {found}")

    def test_reached_tree_is_clean(self):
        self.assertEqual(self.problems(), [])

    def test_source_not_built(self):
        self.assertFlags({"tests/core/test_c.cpp": "QTEST_APPLESS_MAIN(C)\n"}, "tests/core/test_c.cpp")

    def test_built_but_never_registered(self):
        cmake = TREE["tests/core/CMakeLists.txt"].replace(
            "add_test(NAME Core_B COMMAND dbus-run-session -- $<TARGET_FILE:test_core_b>)", "")
        self.assertEqual(self.problems({"tests/core/CMakeLists.txt": cmake}),
                         ["tests/core/test_b.cpp: not a source of any executable add_test runs"])

    def test_subdirectory_not_added(self):
        self.assertFlags({"tests/CMakeLists.txt": TREE["tests/CMakeLists.txt"].replace("add_subdirectory(core)", "")},
                         "tests/core/test_a.cpp", "tests/core/test_b.cpp")

    def test_qml_suite_missing_from_list(self):
        self.assertFlags({"apps/clock/tests/run.sh": TREE["apps/notes/tests/run.sh"],
                          "apps/clock/tests/tst_clock.qml": "TestCase {}\n"},
                         "apps/clock/tests/tst_clock.qml")

    def test_qml_function_qtquicktest_skips(self):
        self.assertFlags({"tests/ui/tst_a.qml": "TestCase { function testA() {} }\n"}, "testA() never runs")

    def test_registered_runner_missing(self):
        self.assertFlags({"apps/notes/tests/run.sh": None}, "apps/notes/tests/run.sh, which does not exist",
                         "apps/notes/tests/tst_notes.qml")

    def test_unregistered_scripts(self):
        self.assertFlags({"tests/lint/check-b.sh": "true\n", "scripts/test_y.py": "\n"},
                         "tests/lint/check-b.sh", "scripts/test_y.py")

    def test_rust_orphan_module(self):
        self.assertFlags({"crates/a/src/orphan.rs": "#[test]\nfn t() {}\n"}, "crates/a/src/orphan.rs")

    def test_rust_crate_outside_workspace(self):
        self.assertFlags({"tools/oauth/Cargo.toml": '[package]\nname = "oauth"\n',
                          "tools/oauth/src/main.rs": "#[test]\nfn t() {}\n"}, "tools/oauth")

    def test_rust_without_cargo_test(self):
        self.assertFlags({"crates/CMakeLists.txt": ""}, "crates/a")


if __name__ == "__main__":
    unittest.main()
