/****************************************************************************************
**
** Copyright (C) 2013 Jolla Ltd.
** All rights reserved.
** 
** This file is part of Sailfish Silica UI component package.
**
** You may use this file under the terms of BSD license as follows:
**
** Redistribution and use in source and binary forms, with or without
** modification, are permitted provided that the following conditions are met:
**     * Redistributions of source code must retain the above copyright
**       notice, this list of conditions and the following disclaimer.
**     * Redistributions in binary form must reproduce the above copyright
**       notice, this list of conditions and the following disclaimer in the
**       documentation and/or other materials provided with the distribution.
**     * Neither the name of the Jolla Ltd nor the
**       names of its contributors may be used to endorse or promote products
**       derived from this software without specific prior written permission.
** 
** THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
** ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
** WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
** DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE FOR
** ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
** (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
** LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
** ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
** (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
** SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**
****************************************************************************************/

var object = null
var dynamic = false
var component = null
var coverIncubator = null

function cleanup() {
    if (component) {
        component.destroy()
        component = null
    }

    if (coverIncubator) {
        // We can't cancel incubation, so we'll force completion and destroy the
        // object immediately
        coverIncubator.onStatusChanged = undefined
        if (coverIncubator.status == Component.Loading) {
            coverIncubator.forceCompletion()
        }
        if (coverIncubator.object) {
            coverIncubator.object.destroy()
        }
        coverIncubator = null
    }

    if (object) {
        if (dynamic) {
            object.destroy()
            dynamic = false
        } else {
            object.visible = false
            object.parent = null
        }
    }
}

function incubateCover(component, parent, callback) {
    coverIncubator = component.incubateObject(parent)
    coverIncubator.onStatusChanged = function(status) {
        if (status == Component.Ready) {
            object = coverIncubator.object
            dynamic = true
            coverIncubator = null
            callback.call(this, object)
        } else if (status == Component.Error) {
            console.log("CoverLoader.js: failed to create object from component with url ", component.url)
            coverIncubator = null
            callback.call(this, null)
        }
    }
}

function load(source, parent, callback) {
    cleanup()
    if (!source) {
        object = null
    } else if (typeof source === "string") { // test for url
        component = Qt.createComponent(source, Component.Asynchronous)
        if (component) {
            if (component.status === Component.Ready) {
                incubateCover(component, parent, callback)
                return
            } else if (component.status === Component.Loading) {
                component.statusChanged.connect(
                    function(status) {
                        if (component) {
                            if (status == Component.Ready) {
                                incubateCover(component, parent, callback)
                            } else if (status == Component.Error) {
                                console.log("CoverLoader.js: createComponent error: ", component.errorString())
                            }
                        }
                    })
                return
            } else {
                console.log("CoverLoader.js: error while creating object from", source)
                if (component.status === Component.Error) {
                    console.log("CoverLoader.js: createComponent error: ", component.errorString())
                } else if (component.status === Component.Null) {
                    console.log("CoverLoader.js: no data available for component")
                }
            }
        } else {
            console.log("CoverLoader.js: unable to create object from ", source)
        }
    } else if (source.incubateObject !== undefined && source.status && source.status === Component.Ready) {
        incubateCover(source, parent, callback)
        return
    } else if (typeof source.activeFocus === "boolean") {
        object = source
        object.parent = parent
    }

    callback.call(this, object)
}
