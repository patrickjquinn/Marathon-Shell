// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
import QtQuick 2.6

QtObject {
    enum LoadStatus { LoadStartedStatus, LoadStoppedStatus, LoadSucceededStatus, LoadFailedStatus }
    enum ErrorDomain { NoErrorDomain, InternalErrorDomain, ConnectionErrorDomain, CertificateErrorDomain,
                       HttpErrorDomain, FtpErrorDomain, DnsErrorDomain, HttpStatusCodeDomain }
    property url url
    property int status
    property string errorString
    property int errorCode
    property int errorDomain
}
