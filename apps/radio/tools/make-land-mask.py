#!/usr/bin/env python3
"""Rasterises Natural Earth's 1:110m land (public domain, naturalearthdata.com)
into the globe's land mask: an equirectangular 1024x512 greyscale PNG, land
white. Drawn 4x larger and scaled down, so the coast is soft and the globe's
shader can threshold it.

    curl -LO https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_land.geojson
    apps/radio/tools/make-land-mask.py ne_110m_land.geojson apps/radio/assets/land.png
"""
import json
import sys

from PIL import Image, ImageDraw

W, H, K = 1024, 512, 4


def xy(lon, lat):
    return ((lon + 180) / 360 * W * K, (90 - lat) / 180 * H * K)


def main(src, dst):
    big = Image.new("L", (W * K, H * K), 0)
    draw = ImageDraw.Draw(big)
    for feature in json.load(open(src))["features"]:
        geometry = feature["geometry"]
        polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
        for rings in polygons:
            draw.polygon([xy(*p) for p in rings[0]], fill=255)
            for hole in rings[1:]:
                draw.polygon([xy(*p) for p in hole], fill=0)
    big.resize((W, H), Image.LANCZOS).save(dst, optimize=True)


if __name__ == "__main__":
    main(*sys.argv[1:3])
