// SPDX-FileCopyrightText: 2016-2022 Jolla Ltd.
// SPDX-FileCopyrightText: 2019 Open Mobile Platform LLC.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (c) 2016 - 2022 Jolla Ltd.
 * Copyright (c) 2019 Open Mobile Platform LLC.
 * Contact: Slava Monich <slava.monich@jolla.com>
 *
 * You may use this file under the terms of BSD license as follows:
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   1. Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *   2. Redistributions in binary form must reproduce the above copyright
 *      notice, this list of conditions and the following disclaimer in the
 *      documentation and/or other materials provided with the distribution.
 *   3. Neither the name of Jolla Ltd nor the names of its contributors may
 *      be used to endorse or promote products derived from this software
 *      without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation
 * are those of the authors and should not be interpreted as representing
 * any official policies, either expressed or implied.
 */

#include "qmcedisplay.h"
#include "qmcetklock.h"
#include "qmcebatterylevel.h"
#include "qmcebatterystatus.h"
#include "qmcebatterystate.h"
#include "qmcecablestate.h"
#include "qmcechargerstate.h"
#include "qmcechargingstate.h"
#include "qmcepowersavemode.h"
#include "qmcecallstate.h"
#include "qmcechargertype.h"
#include "qmcenameowner.h"

#include <QtQml>

class QMCE_EXPORT QMceDeclarativePlugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "Nemo.Mce")

public:
    void registerTypes(const char* aUri);
    static void registerTypes(const char* aUri, int aMajor, int aMinor);
};

void QMceDeclarativePlugin::registerTypes(const char* aUri, int aMajor, int aMinor)
{
    qmlRegisterType<QMceDisplay>(aUri, aMajor, aMinor, "MceDisplay");
    qmlRegisterType<QMceTkLock>(aUri, aMajor, aMinor, "MceTkLock");
    qmlRegisterType<QMceBatteryLevel>(aUri, aMajor, aMinor, "MceBatteryLevel");
    qmlRegisterType<QMceBatteryStatus>(aUri, aMajor, aMinor, "MceBatteryStatus");
    qmlRegisterType<QMceBatteryState>(aUri, aMajor, aMinor, "MceBatteryState");
    qmlRegisterType<QMceCableState>(aUri, aMajor, aMinor, "MceCableState");
    qmlRegisterType<QMceChargingState>(aUri, aMajor, aMinor, "MceChargingState");
    qmlRegisterType<QMceChargerState>(aUri, aMajor, aMinor, "MceChargerState");
    qmlRegisterType<QMcePowerSaveMode>(aUri, aMajor, aMinor, "McePowerSaveMode");
    qmlRegisterType<QMceCallState>(aUri, aMajor, aMinor, "MceCallState");
    qmlRegisterType<QMceChargerType>(aUri, aMajor, aMinor, "MceChargerType");
    qmlRegisterType<QMceNameOwner>(aUri, aMajor, aMinor, "MceNameOwner");
}

void QMceDeclarativePlugin::registerTypes(const char* aUri)
{
    registerTypes(aUri, 1, 0);
}

#include "qmcedeclarativeplugin.moc"
