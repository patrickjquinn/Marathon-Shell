// SPDX-FileCopyrightText: 2026 Patrick Quinn
// SPDX-License-Identifier: MIT
//
// ButtonLayout. API from the Silica public documentation: columnSpacing,
// rowSpacing, preferredWidth (unset: Theme.paddingMedium, Theme.paddingMedium,
// Theme.buttonWidthSmall, Keel's defaults), attached ButtonLayout.newLine. Layout rules as
// documented: buttons in a row share one width, the largest of the widest
// button's implicit width, its preferredWidth and the layout's
// preferredWidth; a row takes as many buttons as fit; adjacent rows with the
// same number of buttons get the same width. Rows are centred.
// C++ because the attached property needs QML_ATTACHED.
#ifndef KEEL_BUTTONLAYOUT_H
#define KEEL_BUTTONLAYOUT_H

#include <QQuickItem>
#include <QtQml/qqmlregistration.h>

class KeelButtonLayoutAttached : public QObject
{
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(bool newLine READ newLine WRITE setNewLine NOTIFY newLineChanged)
public:
    using QObject::QObject;
    bool newLine() const { return m_newLine; }
    void setNewLine(bool v);
signals:
    void newLineChanged();
private:
    bool m_newLine = false;
};

class KeelButtonLayout : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(ButtonLayout)
    QML_ATTACHED(KeelButtonLayoutAttached)
    Q_PROPERTY(qreal columnSpacing READ columnSpacing WRITE setColumnSpacing NOTIFY columnSpacingChanged)
    Q_PROPERTY(qreal rowSpacing READ rowSpacing WRITE setRowSpacing NOTIFY rowSpacingChanged)
    Q_PROPERTY(qreal preferredWidth READ preferredWidth WRITE setPreferredWidth NOTIFY preferredWidthChanged)

public:
    explicit KeelButtonLayout(QQuickItem *parent = nullptr);
    static KeelButtonLayoutAttached *qmlAttachedProperties(QObject *object);

    qreal columnSpacing() const { return m_columnSpacing; }
    void setColumnSpacing(qreal v);
    qreal rowSpacing() const { return m_rowSpacing; }
    void setRowSpacing(qreal v);
    qreal preferredWidth() const { return m_preferredWidth; }
    void setPreferredWidth(qreal v);

    Q_INVOKABLE void relayout();

signals:
    void columnSpacingChanged();
    void rowSpacingChanged();
    void preferredWidthChanged();

protected:
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void componentComplete() override;

private:
    void scheduleRelayout();
    bool m_pending = false;
    bool m_inLayout = false;
    qreal m_columnSpacing = -1;
    qreal m_rowSpacing = -1;
    qreal m_preferredWidth = -1;
};

#endif
