// SPDX-FileCopyrightText: 2012 Robin Burchell <robin+nemo@viroteck.net>
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Robin Burchell <robin+nemo@viroteck.net>
 *
 * You may use this file under the terms of the BSD license as follows:
 *
 * "Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *   * Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in
 *     the documentation and/or other materials provided with the
 *     distribution.
 *   * Neither the name of Nemo Mobile nor the names of its contributors
 *     may be used to endorse or promote products derived from this
 *     software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE."
 */

#include "nemothumbnailprovider.h"

#include "nemothumbnailcache.h"

#include <QFile>
#include <QImage>
#include <QDebug>

QImage NemoThumbnailProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    // sourceSize should indicate what size thumbnail you want. i.e. if you want a 120x120px thumbnail,
    // set sourceSize: Qt.size(120, 120).
    if (!requestedSize.isValid()) {
        qWarning("You must request a sourceSize whenever you use nemoThumbnail");
        return QImage();
    }

    if (size)
        *size = requestedSize;

    NemoThumbnailCache::ThumbnailData thumbnail = NemoThumbnailCache::instance()->requestThumbnail(id, requestedSize, true);
    if (thumbnail.validImage()) {
        return thumbnail.image();
    }
    if (thumbnail.validPath()) {
        return QImage(thumbnail.path());
    }

    return QImage();
}

