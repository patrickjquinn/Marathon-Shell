#!/usr/bin/env python3
"""check-untranslated.py against small QML snippets."""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location(
    "untranslated", Path(__file__).with_name("check-untranslated.py"))
untranslated = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(untranslated)


def hits(source, name="A.qml"):
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / name
        f.write_text(source)
        return untranslated.hits(f)


class CheckUntranslated(unittest.TestCase):
    def test_bare_text_is_flagged(self):
        self.assertEqual(hits('Label { text: "Hello" }\n'), [(1, "Hello")])

    def test_every_property_is_flagged(self):
        for prop in ("title", "label", "description", "placeholderText", "valueText",
                     "subtitle", "message", "Accessible.name", "Accessible.description",
                     "header", "hint", "summary", "placeholder", "toolTip", "tooltip", "errorText",
                     "helperText", "buttonText", "okText", "cancelText"):
            self.assertEqual(len(hits(f'X {{ {prop}: "Hello" }}\n')), 1, prop)

    def test_next_line_literal_is_flagged(self):
        self.assertEqual(hits('Label {\n    text:\n        "Foo"\n}\n'), [(2, "Foo")])
        self.assertEqual(hits('Label {\n    text:\n        qsTr("Foo")\n}\n'), [])

    def test_qstr_passes(self):
        self.assertEqual(hits('Label { text: qsTr("Hello") }\n'), [])
        self.assertEqual(hits('Label { text: qsTrId("hello") }\n'), [])

    def test_ternary_branch_is_flagged(self):
        self.assertEqual(len(hits('Label { text: on ? "On" : qsTr("Off") }\n')), 1)

    def test_other_properties_pass(self):
        self.assertEqual(hits('Item { objectName: "x"; id: y }\n'), [])

    def test_text_without_letters_passes(self):
        self.assertEqual(hits('Label { text: "" }\nLabel { text: "|" }\nLabel { text: "12" }\n'), [])

    def test_marker_passes(self):
        self.assertEqual(hits('Label { text: "Esc" } // i18n: not user-facing\n'), [])

    def test_comments_pass(self):
        self.assertEqual(hits('// text: "Hello"\n/*\ntext: "Hello"\n*/\n'), [])

    def test_agent_descriptions_pass(self):
        src = 'KeelAction { title: "T"; description: "For agents" }\n'
        self.assertEqual(hits(src, "NotesActions.qml"), [(1, "T")])

    def test_main_exit_status(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "A.qml").write_text('Label { text: "Hello" }\n')
            self.assertEqual(untranslated.main(["x", d]), 1)
            (Path(d) / "A.qml").write_text('Label { text: qsTr("Hello") }\n')
            self.assertEqual(untranslated.main(["x", d]), 0)


if __name__ == "__main__":
    unittest.main()
