/*
 * SPDX-FileCopyrightText: 2014 - 2023 Jolla Ltd.
 * SPDX-FileCopyrightText: 2025 Jolla Mobile Ltd
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#ifndef SAILFISH_ACCOUNTS__SERVICEMODEL_H
#define SAILFISH_ACCOUNTS__SERVICEMODEL_H

#include <QAbstractListModel>
#include <QQmlParserStatus>

class Q_DECL_EXPORT ServiceModel : public QAbstractListModel, public QQmlParserStatus
{
    Q_OBJECT
    class ServiceModelPrivate;
    Q_INTERFACES(QQmlParserStatus)
    Q_PROPERTY(QString serviceTypeFilter READ serviceTypeFilter WRITE setServiceTypeFilter NOTIFY serviceTypeFilterChanged)

public:
    enum Roles {
        ServiceNameRole = Qt::UserRole + 1,
        ServiceDisplayNameRole,
        ServiceIconRole,
        ServiceTypeRole,
        ServiceTagsRole,
        ServiceProviderNameRole
    };

    ServiceModel(QObject* parent = 0);
    ~ServiceModel();

    QString serviceTypeFilter() const;
    void setServiceTypeFilter(const QString &serviceFilter);

    int rowCount( const QModelIndex & index = QModelIndex() ) const;
    QVariant data( const QModelIndex &index, int role ) const;

    void classBegin();
    void componentComplete();

signals:
    void serviceTypeFilterChanged();

protected:
    QHash<int, QByteArray> roleNames() const;

private:
    ServiceModelPrivate* d_ptr;
    Q_DISABLE_COPY(ServiceModel)
    Q_DECLARE_PRIVATE(ServiceModel)
};

#endif
