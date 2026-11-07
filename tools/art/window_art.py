"""Draws the F4 window art (desk, papers, ISMIS monitor, buttons) into art/window/.

Pixel art is drawn at 1 art pixel per cell, then scaled up 3x with nearest neighbour, the same
scale the splash screen uses. Most pieces are 9-slice panels: UiKit loads them as StyleBoxTexture
with the margins listed in MARGINS below, so keep the two in sync when a piece changes size.

No dependencies beyond the standard library. Run from the repo root:
    python tools/art/window_art.py
"""

import os
import random
import struct
import zlib

SCALE = 3
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art", "window")

CLEAR = (0, 0, 0, 0)


def hex_color(text, alpha=255):
    text = text.lstrip("#")
    return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16), alpha)


# Same palette as scripts/ui/ui_kit.gd.
INK = hex_color("1d2a22")
CREAM = hex_color("fbfaf4")
GREEN = hex_color("1f5a3d")
GOLD = hex_color("e0b23a")
DISABLED = hex_color("c9cfcb")
SOFT = hex_color("9fb0aa")
SCREEN = hex_color("eef4f0")

PAPER_SHADE = hex_color("e9e3d0")
FLAP = hex_color("e3dcc6")

WOOD = hex_color("dcc08e")
WOOD_GRAIN = hex_color("d0b17c")
WOOD_DARK = hex_color("c3a06a")
WOOD_LIGHT = hex_color("e6cd9f")
WOOD_SEAM = hex_color("b8945e")
WOOD_LIP = hex_color("8a6a3c")
WOOD_SHINE = hex_color("f0dcb0")

PLASTIC = hex_color("d6d1bd")
PLASTIC_LIGHT = hex_color("ece8d8")
PLASTIC_SHADE = hex_color("aea88f")
PLASTIC_INNER = hex_color("8f8a76")
LED = hex_color("5fd37a")
LED_DARK = hex_color("2a6b3a")

# Buttons are grey so UiKit can tint them per action with modulate_color. The face is a little
# under white so the top-left highlight still shows after tinting.
BUTTON_FACE = (240, 240, 240, 255)
BUTTON_LIGHT = (255, 255, 255, 255)
BUTTON_SHADE = (196, 196, 196, 255)
BUTTON_SHADE_DARK = (164, 164, 164, 255)


class Canvas:
    def __init__(self, width, height, fill=CLEAR):
        self.width = width
        self.height = height
        self.pixels = [[fill] * width for _ in range(height)]

    def set(self, x, y, color):
        if 0 <= x < self.width and 0 <= y < self.height:
            self.pixels[y][x] = color

    def rect(self, x0, y0, x1, y1, color):
        """Fills x0..x1, y0..y1 inclusive."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, color)

    def outline(self, x0, y0, x1, y1, color):
        self.rect(x0, y0, x1, y0, color)
        self.rect(x0, y1, x1, y1, color)
        self.rect(x0, y0, x0, y1, color)
        self.rect(x1, y0, x1, y1, color)

    def save(self, name, scale=SCALE):
        rows = []
        for row in self.pixels:
            line = bytearray([0])
            for color in row:
                line.extend(bytes(color) * scale)
            rows.extend([bytes(line)] * scale)
        width = self.width * scale
        height = self.height * scale

        def chunk(kind, data):
            body = kind + data
            return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

        header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
        png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
        png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
        os.makedirs(OUT, exist_ok=True)
        with open(os.path.join(OUT, name), "wb") as handle:
            handle.write(png)
        print("wrote art/window/%s (%dx%d)" % (name, width, height))


def drop_shadow(canvas, x1, y1):
    """A hard 1-pixel shadow to the right of and below a body that ends at x1, y1."""
    canvas.rect(x1 + 1, 1, x1 + 1, y1 + 1, INK)
    canvas.rect(1, y1 + 1, x1 + 1, y1 + 1, INK)


def desk_tile():
    """Laminated wood counter, tiles both ways. One plank per tile, grain wraps around."""
    width, height = 32, 16
    canvas = Canvas(width, height, WOOD)
    rng = random.Random(3)
    canvas.rect(0, 0, width - 1, 0, WOOD_LIGHT)
    canvas.rect(0, height - 1, width - 1, height - 1, WOOD_SEAM)
    for y in range(2, height - 2):
        if rng.random() < 0.35:
            continue
        start = rng.randrange(width)
        length = rng.randrange(5, 16)
        color = WOOD_DARK if rng.random() < 0.2 else WOOD_GRAIN
        for step in range(length):
            canvas.set((start + step) % width, y, color)
    # One knot, so the repeat is less obvious.
    for x, y in [(22, 7), (23, 7), (21, 8), (24, 8), (22, 9), (23, 9)]:
        canvas.set(x, y, WOOD_DARK)
    canvas.save("desk_tile.png")


def desk_edge():
    """The front lip of the counter, tiled along the top of the desk."""
    canvas = Canvas(4, 4)
    for y, color in enumerate([INK, WOOD_LIP, WOOD_SHINE, WOOD_LIGHT]):
        canvas.rect(0, y, 3, y, color)
    canvas.save("desk_edge.png")


def paper():
    """A form with a dog-eared top-right corner. Body 15x15, then the shadow."""
    canvas = Canvas(16, 16)
    last = 14
    canvas.rect(0, 0, last, last, CREAM)
    canvas.rect(last - 1, 0, last - 1, last - 1, PAPER_SHADE)
    canvas.rect(0, last - 1, last - 1, last - 1, PAPER_SHADE)
    canvas.outline(0, 0, last, last, INK)
    drop_shadow(canvas, last, last)
    fold = 4
    left = last - fold
    for y in range(fold + 1):
        for x in range(left, last + 2):
            d = x - left
            if d > y:
                # The torn-off corner, shadow included.
                canvas.set(x, y, CLEAR)
            elif d == y:
                canvas.set(x, y, INK)
            elif x == left or y == fold:
                canvas.set(x, y, INK)
            else:
                canvas.set(x, y, FLAP)
    canvas.set(last + 1, fold + 1, INK)
    canvas.save("paper.png")


def id_card():
    """The student ID: a white card with a green and gold band across the top."""
    canvas = Canvas(12, 12)
    last = 10
    canvas.rect(0, 0, last, last, CREAM)
    canvas.rect(1, 1, last - 1, 2, GREEN)
    canvas.rect(1, 3, last - 1, 3, GOLD)
    canvas.rect(last - 1, 4, last - 1, last - 1, PAPER_SHADE)
    canvas.rect(1, last - 1, last - 1, last - 1, PAPER_SHADE)
    canvas.outline(0, 0, last, last, INK)
    drop_shadow(canvas, last, last)
    canvas.save("id_card.png")


def monitor():
    """The ISMIS monitor bezel: beige plastic, dark glass surround, a chin with a power light."""
    canvas = Canvas(24, 24)
    last = 22
    canvas.rect(0, 0, last, last, PLASTIC)
    # Outer bevel: light from the top left.
    canvas.rect(1, 1, last - 1, 1, PLASTIC_LIGHT)
    canvas.rect(1, 1, 1, last - 1, PLASTIC_LIGHT)
    canvas.rect(last - 1, 1, last - 1, last - 1, PLASTIC_SHADE)
    canvas.rect(1, last - 1, last - 1, last - 1, PLASTIC_SHADE)
    # Inner bevel around the glass, the other way round. Each edge sits in a 9-slice margin, so
    # only the flat glass gets stretched.
    top, left, right, bottom = 4, 4, 18, 15
    canvas.rect(left, top, right, top, PLASTIC_INNER)
    canvas.rect(left, top, left, bottom, PLASTIC_INNER)
    canvas.rect(right, top, right, bottom, PLASTIC_LIGHT)
    canvas.rect(left, bottom, right, bottom, PLASTIC_LIGHT)
    canvas.rect(left + 1, top + 1, right - 1, bottom - 1, INK)
    canvas.outline(0, 0, last, last, INK)
    drop_shadow(canvas, last, last)
    # Power light in the chin's right corner.
    canvas.rect(19, 18, 20, 18, LED)
    canvas.rect(19, 19, 20, 19, LED_DARK)
    canvas.save("monitor.png")


def screen():
    """CRT scanlines for the ISMIS screen. Saved unscaled: 3 bright rows, then 3 a shade darker."""
    canvas = Canvas(1, 6, SCREEN)
    dim = tuple(max(0, c - 6) for c in SCREEN[:3]) + (255,)
    canvas.rect(0, 3, 0, 5, dim)
    canvas.save("screen_scanlines.png", scale=1)


def button(name, pressed=False, disabled=False):
    """Body 9x9 plus a 1-pixel shadow. Pressed buttons sit one pixel down-right, where the shadow was."""
    canvas = Canvas(10, 10)
    offset = 1 if pressed else 0
    x0, y0 = offset, offset
    x1, y1 = 8 + offset, 8 + offset
    if disabled:
        canvas.rect(x0, y0, x1, y1, DISABLED)
        canvas.outline(x0, y0, x1, y1, SOFT)
        canvas.save(name)
        return
    canvas.rect(x0, y0, x1, y1, BUTTON_FACE)
    # Pushed in: a flat face (UiKit darkens it) and no shadow.
    if not pressed:
        canvas.rect(x0 + 1, y0 + 1, x1 - 1, y0 + 1, BUTTON_LIGHT)
        canvas.rect(x0 + 1, y0 + 1, x0 + 1, y1 - 1, BUTTON_LIGHT)
        canvas.rect(x1 - 1, y0 + 1, x1 - 1, y1 - 1, BUTTON_SHADE)
        canvas.rect(x0 + 1, y1 - 2, x1 - 1, y1 - 2, BUTTON_SHADE)
        canvas.rect(x0 + 1, y1 - 1, x1 - 1, y1 - 1, BUTTON_SHADE_DARK)
        drop_shadow(canvas, x1, y1)
    canvas.outline(x0, y0, x1, y1, INK)
    canvas.save(name)


if __name__ == "__main__":
    desk_tile()
    desk_edge()
    paper()
    id_card()
    monitor()
    screen()
    button("button.png")
    button("button_pressed.png", pressed=True)
    button("button_disabled.png", disabled=True)
