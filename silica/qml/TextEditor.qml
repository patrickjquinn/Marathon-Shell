// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// TextEditor: enum holder for TextField/TextArea `backgroundStyle`
// (BackgroundStyle: NoBackground, UnderlineBackground, FilledBackground;
// names from Silica's BSD private/TextBase.qml). Numeric values are Keel's.
import QtQml

QtObject {
    enum BackgroundStyle { NoBackground, UnderlineBackground, FilledBackground }
}
