// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Qt 5's RegExpValidator (QRegExp based) on Qt 6's RegularExpressionValidator.
// `regExp` takes a JavaScript RegExp (the usual `regExp: /^[0-9]+$/`) or a
// pattern string. Both validators require the whole input to match, as QRegExp
// exact matching did. QRegExp-only syntax (wildcard mode, minimal matching)
// is not translated.
import QtQuick 2.15

RegularExpressionValidator {
    // Qt 5 default: an empty QRegExp, documented as matching any string.
    property var regExp

    regularExpression: regExp instanceof RegExp ? regExp
                       : (regExp === undefined || regExp === null) ? /.*/
                       : new RegExp(String(regExp))
}
