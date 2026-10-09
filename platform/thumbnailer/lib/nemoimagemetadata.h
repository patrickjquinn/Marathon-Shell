// SPDX-FileCopyrightText: 2012 Hannu Mallat <hmallat@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2012 Hannu Mallat <hmallat@gmail.com>
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

#ifndef NEMOIMAGEMETADATA_H
#define NEMOIMAGEMETADATA_H

class QString;
class QByteArray;

#include <nemothumbnailexports.h>

#include <QMetaType>

class NEMO_QML_PLUGIN_THUMBNAILER_EXPORT NemoImageMetadata
{
public:
    enum Orientation {
        TopLeft = 1,
        TopRight,
        BottomRight,
        BottomLeft,
        LeftTop,
        RightTop,
        RightBottom,
        LeftBottom
    };

    NemoImageMetadata();
    NemoImageMetadata(const QString &filename, const QByteArray &format);
    NemoImageMetadata(const NemoImageMetadata &other);
    ~NemoImageMetadata();

    NemoImageMetadata &operator=(const NemoImageMetadata &other);

    Orientation orientation(void) const {
        return m_orientation;
    }

private:
    Orientation m_orientation;
};

Q_DECLARE_METATYPE(NemoImageMetadata)

Q_DECLARE_METATYPE(NemoImageMetadata::Orientation)

#endif // NEMOIMAGEMETADATA_H
