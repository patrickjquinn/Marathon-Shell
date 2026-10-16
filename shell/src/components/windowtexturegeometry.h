#pragma once

#include <QRectF>

#include <algorithm>

// Geometry of a rounded, cropped texture quad without MSAA (after lipstick's
// WindowPixmapItem): an octagon body (triangle strip, opaque when the texture
// is) and four corner triangles whose fragments fade over one pixel at the
// arc. Corner coordinates are in units of the radius, 0 on the inner edges
// and 1 at the outer corner, so the shader's arc test is dot(c, c) <= 1.
namespace WindowTextureGeometry {

    struct Vertex {
        float x, y, tx, ty;
    };

    struct CornerVertex {
        float x, y, tx, ty, cx, cy;
    };

    constexpr int BodyVertices   = 8;
    constexpr int CornerVertices = 12;

    // The part of the texture a normalized sourceRect samples. base is the
    // texture's normalized sub-rect (atlas), flipY a bottom-left origin.
    inline QRectF textureRect(const QRectF &base, const QRectF &sourceRect, bool flipY) {
        const QRectF s = flipY ?
            QRectF(sourceRect.x(), 1.0 - sourceRect.y(), sourceRect.width(), -sourceRect.height()) :
            sourceRect;
        return QRectF(base.x() + s.x() * base.width(), base.y() + s.y() * base.height(),
                      s.width() * base.width(), s.height() * base.height());
    }

    inline qreal clampRadius(const QRectF &rect, qreal radius) {
        return std::max<qreal>(0, std::min({radius, rect.width() / 2, rect.height() / 2}));
    }

    // body: BodyVertices; corners: CornerVertices. Returns the radius used.
    inline qreal build(const QRectF &rect, const QRectF &tex, qreal radius, Vertex *body,
                       CornerVertex *corners) {
        const qreal r  = clampRadius(rect, radius);
        const float oL = rect.left(), iL = rect.left() + r, iR = rect.right() - r,
                    oR = rect.right();
        const float oT = rect.top(), iT = rect.top() + r, iB = rect.bottom() - r,
                    oB  = rect.bottom();
        const qreal rx  = rect.width() > 0 ? r * tex.width() / rect.width() : 0;
        const qreal ry  = rect.height() > 0 ? r * tex.height() / rect.height() : 0;
        const float toL = tex.left(), tiL = tex.left() + rx, tiR = tex.left() + tex.width() - rx,
                    toR = tex.left() + tex.width();
        const float toT = tex.top(), tiT = tex.top() + ry, tiB = tex.top() + tex.height() - ry,
                    toB = tex.top() + tex.height();

        body[0] = {oL, iB, toL, tiB};
        body[1] = {oL, iT, toL, tiT};
        body[2] = {iL, oB, tiL, toB};
        body[3] = {iL, oT, tiL, toT};
        body[4] = {iR, oB, tiR, toB};
        body[5] = {iR, oT, tiR, toT};
        body[6] = {oR, iB, toR, tiB};
        body[7] = {oR, iT, toR, tiT};

        const auto corner = [&](int i, float ox, float oy, float tox, float toy, float ix, float iy,
                                float tix, float tiy) {
            corners[i]     = {ox, oy, tox, toy, 1, 1};
            corners[i + 1] = {ox, iy, tox, tiy, 1, 0};
            corners[i + 2] = {ix, oy, tix, toy, 0, 1};
        };
        corner(0, oL, oB, toL, toB, iL, iB, tiL, tiB);
        corner(3, oL, oT, toL, toT, iL, iT, tiL, tiT);
        corner(6, oR, oB, toR, toB, iR, iB, tiR, tiB);
        corner(9, oR, oT, toR, toT, iR, iT, tiR, tiT);
        return r;
    }

    // smoothstep edges for dot(c, c): the arc fades over aaWidth item pixels.
    inline QPointF cornerEdges(qreal radius, qreal aaWidth) {
        if (radius <= 0)
            return {1, 1};
        const qreal h = aaWidth / 2;
        return {((radius + h) / radius) * ((radius + h) / radius),
                ((radius - h) / radius) * ((radius - h) / radius)};
    }

} // namespace WindowTextureGeometry
