#pragma once

#include <QRect>
#include <Qt>

// Pure xdg-positioner policy. Coordinates and bounds are in the direct
// parent's window-geometry coordinate space, as required by xdg-shell.
class PopupPlacement {
  public:
    static QRect constrain(const QRect &unconstrained, const QRect &anchorRect,
                           Qt::Edges anchorEdges, Qt::Edges gravityEdges, const QPoint &offset,
                           const QRect &bounds, Qt::Orientations flip, Qt::Orientations slide,
                           Qt::Orientations resize) {
        QRect placed = unconstrained;

        if (flip.testFlag(Qt::Horizontal) && !fitsX(placed, bounds)) {
            const QRect candidate(position(anchorRect, invertHorizontal(anchorEdges),
                                           invertHorizontal(gravityEdges), placed.size(), offset),
                                  placed.size());
            if (fitsX(candidate, bounds))
                placed.moveLeft(candidate.left());
        }
        if (flip.testFlag(Qt::Vertical) && !fitsY(placed, bounds)) {
            const QRect candidate(position(anchorRect, invertVertical(anchorEdges),
                                           invertVertical(gravityEdges), placed.size(), offset),
                                  placed.size());
            if (fitsY(candidate, bounds))
                placed.moveTop(candidate.top());
        }

        if (slide.testFlag(Qt::Horizontal) && placed.width() <= bounds.width())
            placed.moveLeft(qBound(bounds.left(), placed.left(),
                                   bounds.left() + bounds.width() - placed.width()));
        if (slide.testFlag(Qt::Vertical) && placed.height() <= bounds.height())
            placed.moveTop(qBound(bounds.top(), placed.top(),
                                  bounds.top() + bounds.height() - placed.height()));

        if (resize.testFlag(Qt::Horizontal) && !fitsX(placed, bounds)) {
            const int left  = qMax(placed.left(), bounds.left());
            const int right = qMin(placed.left() + placed.width(), bounds.left() + bounds.width());
            placed.setX(left);
            placed.setWidth(qMax(1, right - left));
        }
        if (resize.testFlag(Qt::Vertical) && !fitsY(placed, bounds)) {
            const int top    = qMax(placed.top(), bounds.top());
            const int bottom = qMin(placed.top() + placed.height(), bounds.top() + bounds.height());
            placed.setY(top);
            placed.setHeight(qMax(1, bottom - top));
        }
        return placed;
    }

  private:
    static QPoint position(const QRect &anchor, Qt::Edges anchorEdges, Qt::Edges gravity,
                           const QSize &size, const QPoint &offset) {
        int x = anchor.left() + anchor.width() / 2;
        int y = anchor.top() + anchor.height() / 2;
        if (anchorEdges.testFlag(Qt::LeftEdge))
            x = anchor.left();
        else if (anchorEdges.testFlag(Qt::RightEdge))
            x = anchor.left() + anchor.width();
        if (anchorEdges.testFlag(Qt::TopEdge))
            y = anchor.top();
        else if (anchorEdges.testFlag(Qt::BottomEdge))
            y = anchor.top() + anchor.height();

        if (gravity.testFlag(Qt::LeftEdge))
            x -= size.width();
        else if (!gravity.testFlag(Qt::RightEdge))
            x -= size.width() / 2;
        if (gravity.testFlag(Qt::TopEdge))
            y -= size.height();
        else if (!gravity.testFlag(Qt::BottomEdge))
            y -= size.height() / 2;
        return QPoint(x, y) + offset;
    }

    static Qt::Edges invertHorizontal(Qt::Edges edges) {
        const bool left  = edges.testFlag(Qt::LeftEdge);
        const bool right = edges.testFlag(Qt::RightEdge);
        edges.setFlag(Qt::LeftEdge, right);
        edges.setFlag(Qt::RightEdge, left);
        return edges;
    }

    static Qt::Edges invertVertical(Qt::Edges edges) {
        const bool top    = edges.testFlag(Qt::TopEdge);
        const bool bottom = edges.testFlag(Qt::BottomEdge);
        edges.setFlag(Qt::TopEdge, bottom);
        edges.setFlag(Qt::BottomEdge, top);
        return edges;
    }

    static bool fitsX(const QRect &rect, const QRect &bounds) {
        return rect.left() >= bounds.left() &&
            rect.left() + rect.width() <= bounds.left() + bounds.width();
    }

    static bool fitsY(const QRect &rect, const QRect &bounds) {
        return rect.top() >= bounds.top() &&
            rect.top() + rect.height() <= bounds.top() + bounds.height();
    }
};
