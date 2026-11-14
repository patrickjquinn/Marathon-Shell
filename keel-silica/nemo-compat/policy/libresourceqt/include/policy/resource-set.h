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
/**
* \file resource-set.h
* \brief Declaration of ResourcePolicy::ResourceSet
*
* \copyright Copyright (C) 2011 Nokia Corporation.
* \author Wolf Bergenheim and Robert Löfman
* \par License
* @license LGPL
* This file is part of libresourceqt
* \par
* Copyright (C) 2011 Nokia Corporation.
* \par
* This library is free software; you can redistribute
* it and/or modify it under the terms of the GNU Lesser General Public
* License as published by the Free Software Foundation
* version 2.1 of the License.
* \par
* This library is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
* Lesser General Public License for more details.
* \par
* You should have received a copy of the GNU Lesser General Public
* License along with this library; if not, write to the Free Software
* Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301
* USA.
*/

#ifndef RESOURCE_SET_H
#define RESOURCE_SET_H

#include <QString>
#include <QObject>
#include <QVector>
#include <QList>

#include <policy/resources.h>
#include <policy/audio-resource.h>
#include <stdlib.h>
#include <stdarg.h>
#include <stdio.h>

class ResourceSetPrivate;

/**
* \mainpage The Meego Resource Policy Qt API: Libresourceqt
*
* \section intro_section Introduction
*
* This library is used to request resources from the Meego Policy Resource Manager,
* by means of two classes: \ref ResourcePolicy::Resource and
* \ref ResourcePolicy::ResourceSet.
*
* The Libresourceqt API provides:
*
* <table>
* <caption>
*   <big><b>
*     Classes in Libresourceqt API
*   </b></big>
* </caption>
* <tr>
*   <th>Name</th>
*   <th>Content</th>
* </tr>
* <tr>
*   <td>ResourcePolicy::ResourceSet</td>
*   <td>The \ref ResourceSet is the main class whose instances should be filled with resources needed by the application.
*       Then use the ResourceSet's methods to acquire those resources. </td>
* <tr>
*   <td>ResourcePolicy::Resource</td>
*   <td>The ResourceSet is filled with instances of subclasses of the class \ref Resource, for example AudioResource.</td>
* </tr>
* </table>
*
* \section library_started_section Getting started
*
* Say that your application is a player (if not a player than use another suitable application class,
* please see "Further Information" section), then in order to use the Resource Policy Library, you first need to create the
* \ref ResourcePolicy::ResourceSet like this:
* \code
* ResourcePolicy::ResourceSet* mySet = new ResourcePolicy::ResourceSet("player");
* \endcode
* Then to add resources to the set, use the ResourceSet::addResource() method like this:
* \code
* mySet->addResource(AudioPlaybackType);
* mySet->addResource(VideoPlaybackType);
* \endcode
* If you want to pre-populate the AudioResource with the audio group (it is a good idea)
* and other audio parameters, you can create an audio object yourself and then
* give that to the ResourcePolicy::ResourceSet. Note that you should NOT free this object.
* The ResourcePolicy::ResourceSet takes ownership of this pointer.
* \code
* ResourcePolicy::AudioResource*audioResource = new ResourcePolicy::AudioResource("player");
* mySet->addResourceObject(audioResource);
* \endcode
* Calling the ResourcePolicy::ResourceSet::deleteResource() method will remove
* and delete the object. Then when you want to acquire the modified ResourcePolicy::ResourceSet
* you simply use the ResourcePolicy::ResourceSet::acquire() method, like this:
* \code
* QObject::connect(mySet, SIGNAL(resourcesGranted(QList<ResourcePolicy::ResourceType>)),
*                  this, SLOT(acquireOkHandler(QList<ResourcePolicy::Resource>)));
* QObject::connect(mySet, SIGNAL(resourcesDenied()), this, SLOT(acquireDeniedHandler()));
* mySet->acquire();
* \endcode
* You should also connect to the ResourcePolicy::ResourceSet::lostResources() signal like this:
* \code
* QObject::connect(mySet, SIGNAL(lostResources()), this, SLOT(lostResourcesHandler()));
* \endcode
* This signal tells you when you should stop using the resources you have asked for.
* So it is important that you connect to it.
*
* To modify the properties of the resources you can use the ResourcePolicy::ResourceSet::resource() method.
*
* \section see_further_info Further information
* For a more detailed guide see the
* <a href="http://wiki.meego.com/images/Meego-policy-framework-developer-guide.pdf">MeeGo Policy Framework Developer Guide (PDF)</a>.
*/

/**
* \brief The Namespace for Meego Resource Policy APIs.
* All Resource Policy Qt APIs reside under the ResourcePolicy namespace.
*/
namespace ResourcePolicy
{

class ResourceEngine;
/**
* Needed resources must be added to the ResourceSet. Each set can only contain
* a single Resource of a given type. That is one AudioPlaybackResource, etc.
*
* Internally the set is stored as a QVector of \ref Resource objects.
*/

class ResourceSet: public QObject
{
    Q_OBJECT
    Q_DISABLE_COPY(ResourceSet)

public:
    /**
    * Alternative constructor with additional parameters for setting
    * alwaysReply and autoRelease.
    * \param applicationClass This parameter defines the application class.
    * The application class is used to determine the priority order of the
    * application.
    * \param parent The parent of this class.
    * \param alwaysReply see setAlwaysReply()
    * \param autoRelease see setAutoRelease()
    */
    ResourceSet(const QString &applicationClass, QObject *parent, bool alwaysReply, bool autoRelease);

    /**
    * Alternative backwards-compatible constructor.
    * \param applicationClass This parameter defines the application class.
    * The application class is used to determine the priority order of the
    * application.
    * \param parent The optional parent of of this class.
    */
    ResourceSet(const QString &applicationClass, QObject *parent = NULL);

    ~ResourceSet();

    /**
    * This method adds a resource to the set. A set contains only a single
    * instance of a given resource. If the ResourceSet already contains a
    * resource of the given type it will be replaced.
    * \param resourceType The resource to add to the set. A copy of this object
    * is stored in the ResourceSet.
    */
    bool addResource(ResourceType resourceType);

    /**
    * This method adds a resource to the set. A set contains only a single
    * instance of a given resource. If the ResourceSet already contains a
    * resource of the given type it will be replaced.
    * \param resource The resource to be added to the set.
    * The ResourcePolicy::ResourseSet takes ownership of the pointer. Do NOT free!
    */
    void addResourceObject(Resource*resource);

    /**
    * This method removes the resource of the given type
    * \param type The type of resource to be removed from the set.
    */
    void deleteResource(ResourceType type);

    /**
    * This method returns a list of all resource in the set.
    * \return a QList of all resources in the set.
    */
    QList<Resource*> resources() const;

    /**
    * This method returns a const pointer to a resource of a specific type.
    * \param type The type of resource we are interested in.
    * \return a pointer to the Resource if it is defined NULL otherwise.
    */
    Resource* resource(ResourceType type) const;

    /**
    * Checks if the \ref ResourceSet contains the given \ref Resource
    * \param type The Resource to look for
    * \return true if the \ref Resource is defined in this \ref ResourceSet
    */
    bool contains(ResourceType type) const;

    /**
    * Checks if this \ref ResourceSet is connected to the policy manager.
    * @return true if this \ref ResourceSet is connected to the manager.
    */
    bool isConnectedToManager() const;

    /**
    * Checks if the \ref ResourceSet contains all given resources.
    * \param types A list of resources to check for
    * \return true if \b all given resources are defined in the ResourceSet.
    */
    bool contains(const QList<ResourceType> &types) const;

    /**
    * Returns the unique identifier of this ResourceSet.
    * @return the unique identifier of this ResourceSet.
    */
    quint32 id() const;

    /**
    * Returns the registered application class (given in the constructor).
    */
    QString applicationClass();

    /**
    * Initializes and connects the ResourceSet. This method can be used before \ref acquire()
    * if one wants to decrease the delay for the initial acquire() (i.e. if not connected, acquire()
    * will call initAndConnect()). In order to avoid an \ref update() after adding resources,
    * add the resources before calling initAndConnect(), and then call \ref acquire().
    * \return true if the method succeeds without encountering errors.
    */
    bool initAndConnect();

    /**
    * Try to acquire the resources in this \ref ResourceSet. The resourcesGranted() (or
    * resourcesDenied() if \ref setAlwaysReply() has been called) signal will be emitted depending on whether the
    * requested resources could be acquired or not. Note that regardless of whether setAlwaysReply() has been called,
    * you will receive the resourcesGranted() signal when the resources could be acquired for you (this could be a long time),
    * and thus you do not have to re-acquire in this case.
    */
    bool acquire();

    /**
    * Releases the acquired resources.
    */
    bool release();

    /**
    * Commits changes to the \ref ResourcePolicy::ResourceSet. Remember to call update()
    * after adding and/or removing resources. Note that, if you do not have resources acquired when
    * calling update() then this method only informs the policy manager of which resources you are
    * interested in, and this request is acknowledged with a \ref updateOK() signal (if alwaysReply is on by calling
    * \ref setAlwaysReply()).
    * If you do have resources granted then the application will be acknowledged with a \ref resourcesGranted()
    * or \ref lostResources() signal if you lose the resources (in this case you will receive the resources back when possible).
    */
    bool update();

    /**
    * Sets the auto-release. When loosing the resources due to another
    * application with a higher priority preempting us, the default is that we automatically
    * re-gain our resources without having to re-acquire them. However if the AutoRelease is set,
    * the resources are released and we need to re-acquire them when the preempting application
    * has released its resources (i.e. when the resourcesBecameAvailable() signal is received).
    *
    * This feature is by default disabled.
    *
    * This flag should be set once only before calling anything else
    * (excluding setAlwaysReply()), and cannot be unset.
    */
    bool setAutoRelease();

    /**
    * Checks whether we have setAutoRelease().
        * \return true if auto-release is enabled.
    */
    bool willAutoRelease();

    /**
    * Assures that the resourcesGranted() signal is emitted even if we already
    * have those requested resources granted (i.e. the set does not change). By default
    * this feature is off, and note that in that case you will not receive the
    * ref\ updateOK() nor the \ref resourcesDenied() signal. This flag should be set
    * once only before calling anything else (excluding setAutoRelease()) and cannot be unset.
    */
    bool setAlwaysReply();

    /**
    * Checks whether the always-get-reply flag has been set with \ref setAlwaysReply()
    * \return true if we will always get a reply (even if there is no change).
    */
    bool alwaysGetReply();

    /**
    * ref\ hasResourcesGranted() returns true if this set has any granted resources.
    */
    bool hasResourcesGranted();

signals:
    /**
    * This signal is emitted when the Resource Policy Manager notifies that the given
    * non-granted resources \param availableResources have become available. These are such resources
    * that the application has shown interest in before. \param availableResources A list of available resources.
    */
    void resourcesBecameAvailable(const QList<ResourcePolicy::ResourceType> &availableResources);

    /**
    * This signal is emitted as a response to the acquire() request (also for the update() request
    * when already granted and updating a modified resource set). Thus, this signal informs  of currently
    * granted resources. \param grantedOptionalResources The list of granted optional
    * resources. All the mandatory resources have also been acquired. Note that this signal
    * is also received after an application with higher priority stopped using the resources
    * that were preempted from you with the lostResources() signal (for this autoRelease must be off, see \ref setAutoRelease() ).
    */
    void resourcesGranted(const QList<ResourcePolicy::ResourceType> &grantedOptionalResources);

    /**
    * This signal is emitted as a response to the update() request if the application did not have
    * resources granted while updating. Note that a reply to an update() request may also be
    * resourcesLost() if the update request is denied (i.e. trying to add a mandatory resource that is granted to another application
    * with higher priority).
    */
    void updateOK();

    /**
    * This signal is emitted as a response to the acquire() request, in the case where \ref setAlwaysReply()
    * has been called and or more of the mandatory resources were not available.
    */
    void resourcesDenied();

    /**
    * This signal is emitted as a response to the release() request. Note that the manager can release as well
    * (i.e. \ref resourcesReleasedByManager()). In that case the application will not
    * receive resources automatically anymore, but has to re-acquire them.
    */
    void resourcesReleased();

    /**
    * This signal is emitted when the manager releases the acquired resources, so that you have to re-acquire
    * them again when you wish to use them.
    * Use this signal to implement permanent playback stopping logic in situations where you do not want
    * playback to continue automatically (in contrast to waiting
    * for resourcesGranted() in order to continue playback after a lostResources() signal emission) after
    * your application's resources are preempted because of some other event.
    * Note that when autoRelease is used, you will not receive the resourcesReleasedByManager() ever,
    * but rather you should interpret the
    * resourcesLost() also as an implicit resourcesReleasedByManager().
    */
    void resourcesReleasedByManager();

    /**
    * This signal is emitted when some other application with a higher priority
    * supersedes your application, and as a result you loose all our resources temporarily.
    * It is very important to connect to this signal as it is signaling when
    * the acquired resources shouldn't be used. When resourcesGranted() is
    * is emitted then the resources can be used again. Note that, when autoRelease mode is used,
    * this signal also signifies that the resources are lost permanently in the sense that they have to be
    * re-acquired when indicated available by the resourcesBecameAvailable() signal  (i.e. they are not granted back
    * automatically when freed by an other application in this case).
    */
    void lostResources();

    /**
    * Subscribe to this signal to receive error notifications,
    * particularly security errors.
    */
    void errorCallback(quint32, const char*);

    /**
    * This signals that the manager has started and is available. This signal was called connectedToManager() before,
    * but that name is now changed to managerIsUp() as that better describes that the manager has booted.
    */
    void managerIsUp();

private:
    ResourceSetPrivate* d;

    bool initialize();
    void registerAudioProperties();
    void registerVideoProperties();
    void executeNextRequest();

private slots:
    void connectedHandler();
    void handleGranted(quint32);
    void handleDeny();
    void handleReleased();
    void handleReleasedByManager();
    void handleResourcesLost(quint32);
    void handleResourcesBecameAvailable(quint32);
    void handleUpdateOK(bool resend);
    void handleAudioPropertiesChanged(const QString &group, quint32 pid, const QString &name, const QString &value);
    void handleVideoPropertiesChanged(quint32 pid);
};
}

#endif
