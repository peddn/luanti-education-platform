#!/usr/bin/env python3
"""Draws the textures of lep_math: display panel, key, and the glyphs.

The glyphs are white on transparent, in the style of a seven-segment
display. The mod colours them with texture modifiers. Run from the
repository root:  scripts/make-math-textures.py
"""
import os
import struct
import zlib

SIZE = 32
OUT = os.path.join("mods", "lep_math", "textures")


def write_png(name, pixels):
    raw = b"".join(
        b"\x00" + bytes(c for x in range(SIZE) for c in pixels[y][x]) for y in range(SIZE)
    )

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    with open(os.path.join(OUT, name), "wb") as handle:
        handle.write(
            b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b"")
        )


def canvas(colour=(0, 0, 0, 0)):
    return [[colour for _ in range(SIZE)] for _ in range(SIZE)]


def rect(pixels, x0, y0, x1, y1, colour=(255, 255, 255, 255)):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < SIZE and 0 <= y < SIZE:
                pixels[y][x] = colour


# The seven segments of a digit.
SEGMENTS = {
    "a": (11, 4, 20, 6),
    "b": (20, 6, 22, 15),
    "c": (20, 16, 22, 25),
    "d": (11, 25, 20, 27),
    "e": (9, 16, 11, 25),
    "f": (9, 6, 11, 15),
    "g": (11, 14, 20, 17),
}

DIGITS = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc",
    "5": "afgcd", "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}


def glyph(name, draw):
    pixels = canvas()
    draw(pixels)
    write_png("lep_math_glyph_" + name + ".png", pixels)


def segments(letters):
    def draw(pixels):
        for letter in letters:
            rect(pixels, *SEGMENTS[letter])
    return draw


def diagonal(pixels, x0, y0, step_x, length):
    for index in range(length):
        rect(pixels, x0 + index * step_x, y0 + index, x0 + index * step_x + 2, y0 + index + 2)


def main():
    os.makedirs(OUT, exist_ok=True)

    for digit, letters in DIGITS.items():
        glyph(digit, segments(letters))

    glyph("plus", lambda p: (rect(p, 8, 14, 23, 17), rect(p, 14, 8, 17, 23)))
    glyph("minus", lambda p: rect(p, 8, 14, 23, 17))
    glyph("times", lambda p: (diagonal(p, 8, 8, 1, 14), diagonal(p, 21, 8, -1, 14)))
    glyph("divide", lambda p: (rect(p, 8, 14, 23, 17), rect(p, 14, 7, 17, 10),
                               rect(p, 14, 21, 17, 24)))
    glyph("equals", lambda p: (rect(p, 8, 10, 23, 13), rect(p, 8, 18, 23, 21)))
    glyph("comma", lambda p: (rect(p, 14, 23, 17, 26), rect(p, 13, 27, 15, 29)))
    glyph("question", lambda p: (rect(p, 11, 4, 20, 6), rect(p, 20, 6, 22, 14),
                                 rect(p, 14, 14, 22, 16), rect(p, 14, 16, 16, 20),
                                 rect(p, 14, 24, 16, 27)))
    # Keys without a seven-segment form.
    glyph("back", lambda p: (rect(p, 10, 14, 24, 17), diagonal(p, 13, 8, -1, 7),
                             diagonal(p, 7, 15, 1, 7)))
    # The OK key shows an enter arrow: down, then to the left.
    glyph("ok", lambda p: (rect(p, 21, 6, 24, 20), rect(p, 10, 17, 24, 20),
                           diagonal(p, 13, 11, -1, 7), diagonal(p, 7, 18, 1, 7)))
    glyph("exit", lambda p: (rect(p, 6, 5, 8, 26), rect(p, 6, 5, 18, 7), rect(p, 6, 24, 18, 26),
                             rect(p, 13, 14, 25, 17), diagonal(p, 20, 9, 1, 6),
                             diagonal(p, 25, 15, -1, 6)))

    # Dark panel of the display with a thin frame.
    panel = canvas((14, 18, 22, 255))
    for i in range(SIZE):
        for x, y in ((i, 0), (i, SIZE - 1), (0, i), (SIZE - 1, i)):
            panel[y][x] = (40, 46, 54, 255)
    write_png("lep_math_panel.png", panel)

    # Light key with a raised look.
    key = canvas((196, 198, 202, 255))
    for i in range(SIZE):
        key[0][i] = key[i][0] = (236, 238, 240, 255)
        key[1][i] = key[i][1] = (236, 238, 240, 255)
        key[SIZE - 1][i] = key[i][SIZE - 1] = (110, 112, 118, 255)
        key[SIZE - 2][i] = key[i][SIZE - 2] = (110, 112, 118, 255)
    write_png("lep_math_key.png", key)


if __name__ == "__main__":
    main()
