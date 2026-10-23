#include "popupplacement.h"

#include <QtTest>

class PopupPlacementTest : public QObject {
    Q_OBJECT

  private slots:
    void flipsAnEdgeMenuIntoTheViewport() {
        const QRect result = PopupPlacement::constrain(
            QRect(470, 40, 180, 220), QRect(450, 20, 20, 20), Qt::RightEdge,
            Qt::RightEdge | Qt::BottomEdge, QPoint(), QRect(0, 0, 480, 419),
            Qt::Horizontal, Qt::Orientations(), Qt::Orientations());
        QCOMPARE(result, QRect(270, 40, 180, 220));
    }

    void leavesAnUnconstrainedPopupOnItsRequestedSide() {
        const QRect result = PopupPlacement::constrain(
            QRect(200, 40, 120, 160), QRect(180, 20, 20, 20), Qt::RightEdge,
            Qt::RightEdge | Qt::BottomEdge, QPoint(), QRect(0, 0, 480, 419),
            Qt::Horizontal | Qt::Vertical, Qt::Orientations(), Qt::Orientations());
        QCOMPARE(result, QRect(200, 40, 120, 160));
    }

    void slidesWhenFlippingWouldStillOverflow() {
        const QRect result = PopupPlacement::constrain(
            QRect(410, 300, 160, 180), QRect(400, 280, 10, 20), Qt::RightEdge,
            Qt::RightEdge | Qt::BottomEdge, QPoint(), QRect(0, 0, 480, 419),
            Qt::Orientations(), Qt::Horizontal | Qt::Vertical, Qt::Orientations());
        QCOMPARE(result, QRect(320, 239, 160, 180));
    }

    void resizesAnOversizedPopupAsTheLastResort() {
        const QRect result = PopupPlacement::constrain(
            QRect(-20, -10, 540, 460), QRect(), {}, {}, QPoint(), QRect(0, 0, 480, 419),
            Qt::Orientations(), Qt::Orientations(), Qt::Horizontal | Qt::Vertical);
        QCOMPARE(result, QRect(0, 0, 480, 419));
    }

    void nestedBoundsMayStartBeforeTheDirectParent() {
        const QRect result = PopupPlacement::constrain(
            QRect(250, 20, 180, 200), QRect(), {}, {}, QPoint(), QRect(-200, -40, 480, 419),
            Qt::Orientations(), Qt::Horizontal, Qt::Orientations());
        QCOMPARE(result, QRect(100, 20, 180, 200));
    }
};

QTEST_MAIN(PopupPlacementTest)
#include "test_popupplacement.moc"
