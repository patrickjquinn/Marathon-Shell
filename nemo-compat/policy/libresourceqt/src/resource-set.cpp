// SPDX-FileCopyrightText: 2011 Nokia Corporation
// SPDX-License-Identifier: LGPL-2.1-only
/*************************************************************************
This file is part of libresourceqt

Copyright (C) 2011 Nokia Corporation.

This library is free software; you can redistribute
it and/or modify it under the terms of the GNU Lesser General Public
License as published by the Free Software Foundation
version 2.1 of the License.

This library is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public
License along with this library; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
USA.
*************************************************************************/

#include <policy/resource-set.h>
#include "resource-engine.h"

#if (QT_VERSION >= QT_VERSION_CHECK(5,14,0))
#include <QRecursiveMutex>
#endif

using namespace ResourcePolicy;

static quint32 resourceSetId = 1;

class ResourceSetPrivate
{
public:
    enum RequestType { Acquire, Update, Release };


    ResourceSetPrivate(const QString &applicationClass,
                       bool initialAlwaysReply, bool initialAutoRelease);

    bool proceedIfImFirst(RequestType theRequest);

    quint32 identifier;
    const QString resourceClass;
    Resource* resourceSet[NumberOfTypes];
    ResourceEngine* resourceEngine;
    AudioResource* audioResource;
    VideoResource* videoResource;
    bool autoRelease;
    bool alwaysReply;
    bool initialized;
    bool pendingAcquire;
    bool pendingUpdate;
    bool pendingAudioProperties;
    bool pendingVideoProperties;
    bool haveAudioProperties;
    bool inAcquireMode;
    QList<RequestType> requestQ;
    bool ignoreQ;

#if (QT_VERSION >= QT_VERSION_CHECK(5,14,0))
    QRecursiveMutex reqMutex;
#else
    QMutex reqMutex;
#endif
};

ResourceSetPrivate::ResourceSetPrivate(const QString &applicationClass,
                                       bool initialAlwaysReply = false, bool initialAutoRelease = false)
    : resourceClass(applicationClass)
    , resourceEngine(nullptr)
    , audioResource(nullptr)
    , autoRelease(initialAutoRelease)
    , alwaysReply(initialAlwaysReply)
    , initialized(false)
    , pendingAcquire(false)
    , pendingUpdate(false)
    , pendingAudioProperties(false)
    , pendingVideoProperties(false)
    , inAcquireMode(false)
    , ignoreQ(false)
#if (QT_VERSION < QT_VERSION_CHECK(5,14,0))
    , reqMutex(QMutex::Recursive)
#endif
{
    identifier = resourceSetId++;
    memset(resourceSet, 0, sizeof(Resource *)*NumberOfTypes);
}

bool ResourceSetPrivate::proceedIfImFirst(RequestType theRequest)
{
    if (!ignoreQ) {
        requestQ.push_back(theRequest);
    } else {
        qCDebug(lcResourceQt, "ResourceSet::%s()...executing first request of %d.", __FUNCTION__, int(requestQ.size())); // Modified by Shipwright for Qt 6: qsizetype.
        return true;
    }

    // Execute if this is the first request or the next is run from slot.
    if (requestQ.size() == 1) {
        if (!ignoreQ) {
            qCDebug(lcResourceQt, "ResourceSet::%s()...allowing only request directly.", __FUNCTION__);
        }
        return true;
    }

    if (requestQ.size() > 1) {
        qCDebug(lcResourceQt, "ResourceSet::%s()...queuing request %d.", __FUNCTION__, int(requestQ.size())); // Modified by Shipwright for Qt 6: qsizetype.

        switch (theRequest)
        {
        case Acquire:  qCDebug(lcResourceQt, "ResourceSet::%s()...queuing request:Acquire.", __FUNCTION__); break;
        case Update:   qCDebug(lcResourceQt, "ResourceSet::%s()...queuing request:Update.", __FUNCTION__);  break;
        case Release:  qCDebug(lcResourceQt, "ResourceSet::%s()...queuing request:Release.", __FUNCTION__); break;
        }
        return false;
    }

    Q_ASSERT_X(0, "proceedIfImFirst", "request queue can not be empty.");

    return false;
}

ResourceSet::ResourceSet(const QString &applicationClass, QObject *parent,
                         bool initialAlwaysReply, bool initialAutoRelease)
    : QObject(parent)
    , d(new ResourceSetPrivate(applicationClass, initialAlwaysReply, initialAutoRelease))
{
}

ResourceSet::ResourceSet(const QString &applicationClass, QObject * parent)
    : QObject(parent)
    , d(new ResourceSetPrivate(applicationClass))
{
}

ResourceSet::~ResourceSet()
{
    qCDebug(lcResourceQt, "ResourceSet::%s(%d)", __FUNCTION__, d->identifier);
    for (int i = 0; i < NumberOfTypes;i++) {
        delete d->resourceSet[i];
    }
    if (d->resourceEngine) {
        qCDebug(lcResourceQt, "ResourceSet::%s(%d) - resourceEngine->disconnectFromManager()", __FUNCTION__, d->identifier);
        d->resourceEngine->disconnect(this);
        d->resourceEngine->disconnectFromManager();
    }
    qCDebug(lcResourceQt, "ResourceSet::%s(%d) - deleted!", __FUNCTION__, d->identifier);

    delete d;
}

bool ResourceSet::initialize()
{
    d->resourceEngine = new ResourceEngine(this);

    QObject::connect(d->resourceEngine, &ResourceEngine::connectedToManager,
                     this, &ResourceSet::connectedHandler);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesGranted,
                     this, &ResourceSet::handleGranted);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesDenied,
                     this, &ResourceSet::handleDeny);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesReleased,
                     this, &ResourceSet::handleReleased);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesLost,
                     this, &ResourceSet::handleResourcesLost);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesBecameAvailable,
                     this, &ResourceSet::handleResourcesBecameAvailable);
    QObject::connect(d->resourceEngine, &ResourceEngine::errorCallback,
                     this, &ResourceSet::errorCallback);
    QObject::connect(d->resourceEngine, &ResourceEngine::resourcesReleasedByManager,
                     this, &ResourceSet::handleReleasedByManager);
    QObject::connect(d->resourceEngine, &ResourceEngine::updateOK,
                     this, &ResourceSet::handleUpdateOK);

    qCDebug(lcResourceQt) << QString("initializing resource engine...");
    if (!d->resourceEngine->initialize()) {
        return false;
    }
    qCDebug(lcResourceQt) << QString("resourceEngine->initialize() returned true");
    if (!d->resourceEngine->connectToManager()) {
        return false;
    }
    qCDebug(lcResourceQt, "ResourceSet is initialized engine:%d", d->resourceEngine->id());
    d->initialized = true;
    qCDebug(lcResourceQt, "**************** ResourceSet::%s().... %d", __FUNCTION__, __LINE__);

    return true;
}

void ResourceSet::addResourceObject(Resource *resource)
{
    qCDebug(lcResourceQt, "**************** ResourceSet::%s(%d).... %d", __FUNCTION__, this->id(), __LINE__);
    if (resource == nullptr)
        return;

    qCDebug(lcResourceQt, "**************** ResourceSet::%s(%d).... %d", __FUNCTION__, this->id(), __LINE__);
    delete d->resourceSet[resource->type()];
    d->resourceSet[resource->type()] = resource;

    if (resource->type() == AudioPlaybackType) {
        qCDebug(lcResourceQt, "**************** ResourceSet::%s(%d).... %d", __FUNCTION__, this->id(), __LINE__);
        d->audioResource = static_cast<AudioResource *>(resource);
        QObject::connect(d->audioResource, &AudioResource::audioPropertiesChanged,
                         this, &ResourceSet::handleAudioPropertiesChanged);

        if (!d->audioResource->audioGroupIsSet())
            d->audioResource->setAudioGroup(d->resourceClass);

        if (d->audioResource->streamTagIsSet() && (d->audioResource->processID() > 0)) {
            qCDebug(lcResourceQt) << QString("registering audio properties");
            registerAudioProperties();
        } else if (d->audioResource->audioGroupIsSet()) {
            qCDebug(lcResourceQt, "ResourceSet::%s().... %d registering audio proprerties later", __FUNCTION__, __LINE__);
            d->pendingAudioProperties = true;
        }

    } else if (resource->type() == VideoPlaybackType) {
        qCDebug(lcResourceQt, "**************** ResourceSet::%s(%d).... %d", __FUNCTION__, this->id(), __LINE__);
        d->videoResource = static_cast<VideoResource *>(resource);

        QObject::connect(d->videoResource, &VideoResource::videoPropertiesChanged,
                         this, &ResourceSet::handleVideoPropertiesChanged);
        if (d->videoResource->processID() > 0) {
            qCDebug(lcResourceQt) << QString("registering video properties");
            registerVideoProperties();
        }
    }

    if (d->resourceEngine
        && (d->resourceEngine->isConnectedToManager() || d->resourceEngine->isConnectingToManager())) {
        d->pendingUpdate = true;
    }
}

bool ResourceSet::addResource(ResourceType type)
{
    Resource *resource = nullptr;

    switch (type) {
    case AudioPlaybackType:
        resource = new AudioResource;
        break;
    case AudioRecorderType:
        resource = new AudioRecorderResource;
        break;
    case VideoPlaybackType:
        resource = new VideoResource;
        break;
    case VideoRecorderType:
        resource = new VideoRecorderResource;
        break;
    case VibraType:
        resource = new VibraResource;
        break;
    case LedsType:
        resource = new LedsResource;
        break;
    case BacklightType:
        resource = new BacklightResource;
        break;
    case SystemButtonType:
        resource = new SystemButtonResource;
        break;
    case LockButtonType:
        resource = new LockButtonResource;
        break;
    case ScaleButtonType:
        resource = new ScaleButtonResource;
        break;
    case SnapButtonType:
        resource = new SnapButtonResource;
        break;
    case LensCoverType:
        resource = new LensCoverResource;
        break;
    case HeadsetButtonsType:
        resource = new HeadsetButtonsResource;
        break;
    case RearFlashlightType:
        resource = new RearFlashlightResource;
        break;
    default:
        break;
    }

    if (resource == nullptr) {
        return false;
    }
    addResourceObject(resource);
    return true;
}

void ResourceSet::deleteResource(ResourceType type)
{
    if (type == AudioPlaybackType) {
        d->audioResource->disconnect();
        d->audioResource = nullptr;
        d->pendingAudioProperties = false;
    }
    delete d->resourceSet[type];
    d->resourceSet[type] = nullptr;

    if (d->resourceEngine
        && (d->resourceEngine->isConnectedToManager() || d->resourceEngine->isConnectingToManager())) {
        d->pendingUpdate = true;
    }
}

bool ResourceSet::contains(ResourceType type) const
{
    return ((type < NumberOfTypes) && (d->resourceSet[type] != nullptr));
}

bool ResourceSet::isConnectedToManager() const
{
    return d->resourceEngine && d->resourceEngine->isConnectedToManager();
}

bool ResourceSet::contains(const QList<ResourceType> &types) const
{
    bool containsAll = true;
    int i = 0;

    do {
        containsAll = contains(types.at(i));
        i++;
    } while ((i < types.size()) && containsAll);

    return containsAll;
}

quint32 ResourceSet::id() const
{
    return d->identifier;
}

QList<Resource *> ResourceSet::resources() const
{
    QList<Resource *> listOfResources;
    for (int i = 0; i < NumberOfTypes; i++) {
        if (d->resourceSet[i] != nullptr) {
            listOfResources.append(d->resourceSet[i]);
        }
    }
    return listOfResources;
}

Resource * ResourceSet::resource(ResourceType type) const
{
    return d->resourceSet[type];
}

bool ResourceSet::initAndConnect()
{
    if (!d->initialized) {
        qCDebug(lcResourceQt, "ResourceSet::%s().... initializing...", __FUNCTION__);
        return initialize();
    }

    if (!d->resourceEngine->isConnectedToManager()) {
        qCDebug(lcResourceQt, "ResourceSet::%s().... connecting...", __FUNCTION__);
        return d->resourceEngine->connectToManager();
    }

    qCDebug(lcResourceQt, "ResourceSet::%s(): already connected", __FUNCTION__);

    return true;
}

void ResourceSet::executeNextRequest()
{
    qCDebug(lcResourceQt) << Q_FUNC_INFO;

    if (d->requestQ.isEmpty()) {
        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...the completed request is not present.");
        return;
    }

    d->requestQ.removeFirst(); // Remove completed request.

    if (d->requestQ.isEmpty()) {
        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...last request acknowledged and removed.");
        return;
    }

    ResourceSetPrivate::RequestType nxtReq = d->requestQ.at(0);

    // Ensure that proceedIfimFirst() lets through.
    d->ignoreQ = true;
    // Having recursive mutexes, because it is taken again in proceedIfImFirst.
    qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...executing first request of %d.") << d->requestQ.size();

    switch (nxtReq) {
    case ResourceSetPrivate::Acquire:
        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...Acquire.");
        this->acquire();
        break;
    case ResourceSetPrivate::Update:
        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...Update.");
        this->update();
        break;
    case ResourceSetPrivate::Release:
        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("...Release.");
        this->release();
        break;
    }

    d->ignoreQ = false;

    //Q_ASSERT_X(0, "executeNextRequest", "should not happen since requestQ.isEmpty() was false.");
}

bool ResourceSet::acquire()
{
    if (!d->initialized || !d->resourceEngine->isConnectedToManager()) {
        d->pendingAcquire = true;
        return initAndConnect();
    } else {
      /*  if (pendingUpdate)
        { //Connected and there are res.added.

            if ( !proceedIfImFirst( Update, Acquire ) ) return true;

            qCDebug(lcResourceQt) << Q_FUNC_INFO << QString(".... forcing update.");

            if (!resourceEngine->updateResources()) return false;

            if ( inAcquireMode ) return true;
        }*/

        if (!d->proceedIfImFirst(ResourceSetPrivate::Acquire))
          return true;

        qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("... acquiring");
        return d->resourceEngine->acquireResources();
    }
}

bool ResourceSet::release()
{
    if (!d->initialized || !d->resourceEngine->isConnectedToManager()) {
        return true;
    }

    if (!d->proceedIfImFirst(ResourceSetPrivate::Release))
        return true;

    //inAcquireMode = false;
    qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("... releasing...");
    return d->resourceEngine->releaseResources();
}

bool ResourceSet::update()
{
    if (!d->initialized) {
        return true;
    }

    if (!d->resourceEngine->isConnectedToManager()) {
        d->pendingUpdate = true;
        d->resourceEngine->connectToManager();

        return true;
    }

    if (!d->proceedIfImFirst(ResourceSetPrivate::Update))
        return true;

    qCDebug(lcResourceQt) << Q_FUNC_INFO << QString("... updating...");
    return d->resourceEngine->updateResources();
}

QString ResourceSet::applicationClass()
{
    return d->resourceClass;
}

bool ResourceSet::setAutoRelease()
{
    if (d->initialized)
        return false;

    d->autoRelease = true;
    return true;
}

bool ResourceSet::willAutoRelease()
{
    return d->autoRelease;
}

bool ResourceSet::setAlwaysReply()
{
    if (d->initialized)
        return false;

    d->alwaysReply = true;
    return true;
}

bool ResourceSet::alwaysGetReply()
{
    return d->alwaysReply;
}

bool ResourceSet::hasResourcesGranted()
{
    return d->inAcquireMode;
}

void ResourceSet::connectedHandler()
{
    qCDebug(lcResourceQt, "**************** ResourceSet::%s().... %d", __FUNCTION__, __LINE__);

    if (d->resourceEngine->isConnectedToManager()) {
        qCDebug(lcResourceQt, "ResourceSet::%s() Connected to manager!", __FUNCTION__);
        emit managerIsUp();

        if (d->pendingAudioProperties) {
            registerAudioProperties();
        }
        if (d->pendingVideoProperties) {
            registerVideoProperties();
        }
        if (d->pendingUpdate) {
            d->resourceEngine->updateResources();
            d->pendingUpdate = false;
        }
        if (d->pendingAcquire) {
            acquire();
            d->pendingAcquire = false;
        }
    } else { // assuming reconnecting
        qCDebug(lcResourceQt, "ResourceSet::%s() Reconnecting to manager...", __FUNCTION__);

        // first check if we have any acquired resources
        for (int i = 0; i < NumberOfTypes; i++) {
            if (d->resourceSet[i]) {
                if (d->resourceSet[i]->isGranted()) {
                    if (i == AudioPlaybackType) {
                        d->pendingAudioProperties = true;
                        qCDebug(lcResourceQt, "ResourceSet::%s() We have audio", __FUNCTION__);
                    }

                    if (i == VideoPlaybackType) {
                        d->pendingVideoProperties = true;
                        qCDebug(lcResourceQt, "ResourceSet::%s() We have video", __FUNCTION__);
                    }

                    qCDebug(lcResourceQt, "ResourceSet::%s() We have acquired resources. Re-acquire", __FUNCTION__);
                    d->pendingAcquire = true;
                    d->resourceSet[i]->unsetGranted();
                }
            }
        }
        // now reconnect
        d->resourceEngine->connectToManager();
    }
}

void ResourceSet::registerAudioProperties()
{
    if (!d->initialized) {
        qCDebug(lcResourceQt, "%s(): initializing...", __FUNCTION__);
        d->pendingAudioProperties = true;
        initialize();
    } else if (d->resourceEngine->isConnectedToManager()) {
        qCDebug(lcResourceQt, "Registering new audio settings");
        //qCDebug(lcResourceQt,  "\taudio group: %s", audioResource->audioGroup().toStdString().c_str() );
        //qCDebug(lcResourceQt,  "\tPID: %d ", audioResource->processID() );
        //qCDebug(lcResourceQt,  "\taudio stream: %s:%s",  audioResource->streamTagName().toStdString().c_str(),
        //         audioResource->streamTagValue().toStdString().c_str() );

        if ((d->audioResource->processID() > 0) && d->audioResource->streamTagName() != "media.name") {
            qWarning() << "streamTagName should be 'media.name' it is '" << d->audioResource->streamTagName() << "'";
        }
        bool r = d->resourceEngine->registerAudioProperties(d->audioResource->audioGroup(),
                                                            d->audioResource->processID(),
                                                            d->audioResource->streamTagName(),
                                                            d->audioResource->streamTagValue());
        qCDebug(lcResourceQt, "resourceEngine->registerAudioProperties returned %s", r ? "true" : "false");

        d->pendingAudioProperties = false;
    } else { //if (!resourceEngine->isConnectedToManager() && !resourceEngine->isConnectingToManager()) {
        qCDebug(lcResourceQt, "%s(): Connecting to Manager...", __FUNCTION__);

        d->pendingAudioProperties = true;
        d->resourceEngine->connectToManager();
    }
}

void ResourceSet::registerVideoProperties()
{
    if (!d->initialized) {
        qCDebug(lcResourceQt, "%s(): initializing...", __FUNCTION__);
        d->pendingVideoProperties = true;
        initialize();
    } else if (d->resourceEngine->isConnectedToManager()) {
        qCDebug(lcResourceQt, "Registering new video settings:");
        qCDebug(lcResourceQt, "\tPID:%d", d->videoResource->processID());

        if (d->videoResource->processID() < 2) {
            qWarning() << "processID should be > 1 '" << "'";
        }

        bool r = d->resourceEngine->registerVideoProperties(d->videoResource->processID());

        qCDebug(lcResourceQt, "resourceEngine->registerVideoProperties returned %s", r ? "true" : "false");

        d->pendingVideoProperties = false;
    } else { //if (!resourceEngine->isConnectedToManager() && !resourceEngine->isConnectingToManager()) {
        qCDebug(lcResourceQt, "%s(): Connecting to Manager...", __FUNCTION__);

        d->pendingVideoProperties = true;
        d->resourceEngine->connectToManager();
    }
}

void ResourceSet::handleGranted(quint32 bitmaskOfGrantedResources)
{
    qCDebug(lcResourceQt, " ResourceSet::%s",__FUNCTION__);
    QList<ResourceType> optionalResources;
    qCDebug(lcResourceQt, "Acquired resources: 0x%04x", bitmaskOfGrantedResources);

    bool setChanged = false;

    for (int i = 0; i < NumberOfTypes; i++) {
        if (d->resourceSet[i] == nullptr)
            continue;

        ResourceType type = (ResourceType) i;
        quint32 bitmask = resourceTypeToLibresourceType(type);
        qCDebug(lcResourceQt, "Checking if resource 0x%04x is in the set", bitmask);

        if ((bitmask & bitmaskOfGrantedResources) == bitmask) {
            if (d->resourceSet[i]->isOptional()) {
                optionalResources << type;
            }
            if (!d->resourceSet[i]->isGranted())
                setChanged = true;

            d->resourceSet[i]->setGranted();
            qCDebug(lcResourceQt, "Resource 0x%04x is now granted", i);
        } else {
            if (d->resourceSet[i]->isGranted())
                setChanged = true;

            d->resourceSet[i]->unsetGranted();
            setChanged = true;
        }
    }

    // When we come to this slot bitmaskOfGrantedResources contains resources.
    if (d->alwaysReply || (!d->alwaysReply && setChanged)) {
        qCDebug(lcResourceQt, " ResourceSet::%s - emitting resourcesGranted(optionalResources) ", __FUNCTION__);
        emit resourcesGranted(optionalResources);
    }

    d->inAcquireMode = true;
    executeNextRequest();
}

void ResourceSet::handleReleased()
{
    for (int i = 0; i < NumberOfTypes; i++) {
        if (d->resourceSet[i]) {
            d->resourceSet[i]->unsetGranted();
        }
    }

    if (d->alwaysReply || (!d->alwaysReply && d->inAcquireMode))
        emit resourcesReleased();

    qCDebug(lcResourceQt, "ResourceSet(%d) - resourcesReleased!", d->identifier);
    d->inAcquireMode = false;

    executeNextRequest();
    //emit resourcesReleased();
}

void ResourceSet::handleDeny()
{
    for (int i = 0; i < NumberOfTypes; i++) {
        if (d->resourceSet[i]) {
            d->resourceSet[i]->unsetGranted();
        }
    }
    executeNextRequest();
    emit resourcesDenied();
}

void ResourceSet::handleResourcesLost(quint32 lostResourcesBitmask)
{
    for (int i = 0; i < NumberOfTypes; i++) {
        quint32 bitmask = resourceTypeToLibresourceType((ResourceType)i);
        if ((bitmask & lostResourcesBitmask) == bitmask) {
            d->resourceSet[i]->unsetGranted();
            qCDebug(lcResourceQt, "Resource %04x is now lost", bitmask);
        }
    }

    // All requests are invalid when we are pre-empted.
    d->requestQ.clear();
    if (d->inAcquireMode)
        emit lostResources();
}

void ResourceSet::handleResourcesBecameAvailable(quint32 availableResources)
{
    QList<ResourceType> listOfResources;
    for (int i = 0; i < NumberOfTypes; i++) {
        ResourceType type = (ResourceType) i;
        quint32 bitmask = resourceTypeToLibresourceType(type);
        if ((bitmask & availableResources) == bitmask) {
            listOfResources.append(type);
        }
    }
    emit resourcesBecameAvailable(listOfResources);
}

void ResourceSet::handleAudioPropertiesChanged(const QString &, quint32,
                                               const QString &, const QString &)
{
    registerAudioProperties();
}

void ResourceSet::handleVideoPropertiesChanged( quint32)
{
    registerVideoProperties();
}

void ResourceSet::handleReleasedByManager()
{
    // All requests are invalid when we are pre-empted.
   d->requestQ.clear();

   d->resourceEngine->releaseResources();
   d->inAcquireMode = false;
   emit resourcesReleasedByManager();
}

void ResourceSet::handleUpdateOK(bool resend)
{
    d->pendingUpdate = false;
    qCDebug(lcResourceQt, "ResourceSet::%s().... %d", __FUNCTION__, __LINE__);

    if (resend) {
        /*QList<ResourceType> optionalResources;

        for (int i=0; i < NumberOfTypes; i++) {
            if(resourceSet[i] == NULL)
                continue;

            ResourceType type = (ResourceType)i;
            if ( resourceSet[i]->isOptional() &&  resourceSet[i]->isGranted() )
                optionalResources << type;
        }*/

        //Only way to reply if alwaysReply is off and the set doesn't change.
        emit updateOK();
    }

    qCDebug(lcResourceQt, "ResourceSet::%s()...about to exe next request....", __FUNCTION__);
    executeNextRequest();
}
