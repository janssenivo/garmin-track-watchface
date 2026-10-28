"""Generate the carbon fiber background bitmaps (2x2 twill weave).

Usage: python3 tools/gen_carbon.py

- resources/drawables/carbon.png: 454x454 smooth greys for AMOLED (fenix 8)
- resources-round-280x280/drawables/carbon.png: 280x280 for the fenix 6X, using
  only black and 0x555555, because the 64-colour MIP palette has no near-black greys
"""
import math
import os

from PIL import Image


def shade(along, across, cell, lo, hi):
    # Bright ridge along the middle of the tow, darker where it dips under the next one
    ridge = math.sin(math.pi * (across + 0.5) / cell)
    dip = 0.75 + 0.25 * math.sin(math.pi * (along + 0.5) / cell)
    return round(lo + (hi - lo) * ridge * dip)


def smooth(size, cell):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            u, v = x % cell, y % cell
            if (x // cell + y // cell) % 4 < 2:
                g = shade(u, v, cell, 0x0C, 0x24)  # horizontal tow, catches more light
            else:
                g = shade(v, u, cell, 0x06, 0x16)  # vertical tow
            px[x, y] = (g, g, g)
    return img


def dithered(size, cell):
    # 2x2 twill: each tow passes over two cells, then under two, stepping one
    # cell per row. With only two colours, shading is drawn as fibre rows whose
    # length shrinks towards the tow edges, giving each crossing a rounded
    # "pillow". Vertical tows use every other pixel so they read darker.
    img = Image.new("RGB", (size, size))
    px = img.load()
    run = 2 * cell
    for y in range(size):
        for x in range(size):
            k = (x // cell + y // cell) % 4
            horizontal = k < 2
            if horizontal:
                along, across = (k * cell + x % cell), y % cell
            else:
                along, across = ((k - 2) * cell + y % cell), x % cell
            on = False
            if 0 < across < cell - 1:  # outer rows are the gap between tows
                centre = abs(across - (cell - 1) / 2)
                half = (run / 2 - 1) * math.sqrt(max(0, 1 - (centre / (cell / 2)) ** 2))
                on = abs(along - (run - 1) / 2) <= half
                if not horizontal:
                    on = on and (along + across) % 2 == 0
                elif centre > 1:
                    on = on and along % 2 == 0
            px[x, y] = (0x55, 0x55, 0x55) if on else (0, 0, 0)
    return img


smooth(454, 8).save("resources/drawables/carbon.png")
os.makedirs("resources-round-280x280/drawables", exist_ok=True)
dithered(280, 6).save("resources-round-280x280/drawables/carbon.png")
