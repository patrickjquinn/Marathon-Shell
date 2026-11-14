// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
// Test double of Qt WebEngine's ContextMenuRequest.
import QtQml 2.0

QtObject {
    enum MediaType { MediaTypeNone, MediaTypeImage, MediaTypeVideo, MediaTypeAudio, MediaTypeCanvas,
                     MediaTypeFile, MediaTypePlugin }

    property url linkUrl
    property string linkText
    property url mediaUrl
    property int mediaType
    property point position
    property bool accepted
}
