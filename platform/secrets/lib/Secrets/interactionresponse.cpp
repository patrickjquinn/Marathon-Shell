// SPDX-FileCopyrightText: 2018 Jolla Ltd.
// SPDX-License-Identifier: BSD-3-Clause
/*
 * Copyright (C) 2018 Jolla Ltd.
 * Contact: Chris Adams <chris.adams@jollamobile.com>
 * All rights reserved.
 * BSD 3-Clause License, see LICENSE.
 */

#include "Secrets/interactionresponse.h"
#include "Secrets/interactionresponse_p.h"

using namespace Sailfish::Secrets;

InteractionResponsePrivate::InteractionResponsePrivate()
{
}

InteractionResponsePrivate::InteractionResponsePrivate(const InteractionResponsePrivate &other)
    : QSharedData(other)
    , m_result(other.m_result)
    , m_responseData(other.m_responseData)
{
}

InteractionResponsePrivate::~InteractionResponsePrivate()
{
}

/*!
  \qmltype InteractionResponse
  \inqmlmodule Sailfish.Secrets
  \brief Encapsulates a user-input response from an authentication plugin
*/

/*!
  \class InteractionResponse
  \brief Encapsulates a user-input response from an authentication plugin
  \inmodule SailfishSecrets
  \inheaderfile Secrets/interactionresponse.h

  Whenever an authentication (verifying the identity of the user)
  or input (requesting data or confirmation from the user) request
  is processed by an authentication plugin, the response will be
  encapsulated in an instance of this type.

  Note that client applications should never have to use this type,
  as only authentication plugin implementations return instances
  of this type, and such responses are consumed by the secrets
  service.
 */

/*!
  \brief Constructs a new InteractionResponse instance
 */
InteractionResponse::InteractionResponse()
    : d_ptr(new InteractionResponsePrivate)
{
}

/*!
  \brief Destroys the InteractionResponse instance
 */
InteractionResponse::~InteractionResponse()
{
}

/*!
  \brief Constructs a copy of the \a other InteractionResponse instance
 */
InteractionResponse::InteractionResponse(const InteractionResponse &other)
    : d_ptr(other.d_ptr)
{
}

/*!
  \brief Assigns this InteractionResponse to be equal to the \a other
 */
InteractionResponse& InteractionResponse::operator=(const InteractionResponse &other)
{
    d_ptr = other.d_ptr;
    return *this;
}

/*!
  \qmlproperty Result InteractionResponse::result
  \brief The result of the request
*/

/*!
  \brief Returns the result of the request
 */
Result InteractionResponse::result() const
{
    return d_ptr->m_result;
}

/*!
  \brief Sets the result of the request to \a result
 */
void InteractionResponse::setResult(const Result &result)
{
    if (d_ptr->m_result != result) {
        d_ptr->m_result = result;
    }
}

/*!
  \qmlproperty ArrayBuffer InteractionResponse::responseData
  \brief The data which was retrieved from the user
*/

/*!
  \brief Returns the data which was retrieved from the user
 */
QByteArray InteractionResponse::responseData() const
{
    return d_ptr->m_responseData;
}

/*!
  \brief Sets the data which was retrieved from the user to \a data
 */
void InteractionResponse::setResponseData(const QByteArray &data)
{
    if (d_ptr->m_responseData != data) {
        d_ptr->m_responseData = data;
    }
}

/*!
  \brief Returns true if the \a lhs response is identical to the \a rhs response
 */
bool Sailfish::Secrets::operator==(const InteractionResponse &lhs, const InteractionResponse &rhs)
{
    return lhs.result() == rhs.result()
            && lhs.responseData() == rhs.responseData();
}

/*!
  \brief Returns false if the \a lhs response is identical to the \a rhs response
 */
bool Sailfish::Secrets::operator!=(const InteractionResponse &lhs, const InteractionResponse &rhs)
{
    return !operator==(lhs, rhs);
}

/*!
  \brief Returns true if the \a lhs response should sort as less than the \a rhs response
 */
bool Sailfish::Secrets::operator<(const InteractionResponse &lhs, const InteractionResponse &rhs)
{
    if (lhs.result() != rhs.result())
        return lhs.result() < rhs.result();
    return lhs.responseData() < rhs.responseData();
}

