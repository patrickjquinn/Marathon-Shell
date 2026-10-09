// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// Palette (Silica public documentation, "Palette QML Type"): the colour set
// of a Silica item. Sailfish.Silica's public name for Keel's native palette
// (Sailfish.Silica.private Palette, plugin/cpp/private/palette.h), so that
// an app can declare one (`property Palette p: Palette { highlightColor:
// "red" }`) or name the type of an item's `palette`. Colours not set follow
// the Silica ancestor's palette, else the ambience; setting colorScheme or
// highlightColor derives the dependent colours again.
import QtQuick
import Sailfish.Silica.private 1.0 as SilicaPrivate

SilicaPrivate.Palette {
}
