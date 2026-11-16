#!/usr/bin/env python3
"""Draws the texture of lep_quest_chest: a question mark that is laid
over the chest textures of Minetest Game. Run from the repository root:
scripts/make-quest-chest-textures.py
"""
import os
import struct
import zlib

SIZE = 16
OUT = os.path.join("mods", "lep_quest_chest", "textures")

MARK = [
    ".####.",
    "##..##",
    "....##",
    "...##.",
    "..##..",
    "..##..",
    "......",
    "..##..",
    "..##..",
]
FILL = (255, 214, 64, 255)
OUTLINE = (46, 30, 8, 255)
CLEAR = (0, 0, 0, 0)


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


def main():
    pixels = [[CLEAR for _ in range(SIZE)] for _ in range(SIZE)]
    left = (SIZE - len(MARK[0])) // 2
    top = (SIZE - len(MARK)) // 2
    filled = {
        (left + x, top + y)
        for y, row in enumerate(MARK)
        for x, cell in enumerate(row)
        if cell == "#"
    }
    for x, y in filled:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                if 0 <= x + dx < SIZE and 0 <= y + dy < SIZE:
                    pixels[y + dy][x + dx] = OUTLINE
    for x, y in filled:
        pixels[y][x] = FILL
    os.makedirs(OUT, exist_ok=True)
    write_png("lep_quest_chest_mark.png", pixels)


if __name__ == "__main__":
    main()
