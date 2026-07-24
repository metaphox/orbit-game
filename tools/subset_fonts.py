#!/usr/bin/env python3
"""Subset the CJK fallback fonts down to only the characters the game actually
uses, so we ship a few hundred KB instead of tens of MB.

  - M PLUS 1 Code (JP fallback)  -> characters used by ja.po
  - Noto Sans CJK SC (zh_CN + universal backstop) -> characters used by zh_CN.po,
    plus Cyrillic (for a future ru) and the shared symbol/Latin set.

Full source fonts live in .fonts_cache/ (git-ignored, downloaded on demand); the
committed outputs are the small subsets in assets/fonts/. Re-run this whenever the
translations change (a character that no locale uses is dropped from the font):

  python3 tools/subset_fonts.py

Requires: pip install fonttools
"""
import os
import re
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, ".fonts_cache")
TRANS = os.path.join(ROOT, "assets", "translations")
FONTS_OUT = os.path.join(ROOT, "assets", "fonts")

# ASCII printable — the primary Latin faces cover these, but including them keeps
# the fallback safe if it is ever reached for punctuation/digits.
ASCII = "".join(chr(c) for c in range(0x20, 0x7F))
# Latin-1 letters (German/French accents: ä ö ü ß é è à ç …).
LATIN1 = "".join(chr(c) for c in range(0xA0, 0x100))
# Cyrillic block, for a future Russian locale (rendered from Noto).
CYRILLIC = "".join(chr(c) for c in range(0x400, 0x500))
# Glyphs generated in code (not present in any .po): rewind pips, trend arrows, …
CODE_GLYPHS = "●○◉◇◆■□★☆✓✗⚠‖·—–…↑↓←→↕°±×÷≈≠≤≥ΔΩμ▲▼△▽◀▶"

QUOTED = re.compile(r'^(?:msgid|msgstr) "(.*)"$')


def chars_in_po(name):
    out = set()
    path = os.path.join(TRANS, name)
    for line in open(path, encoding="utf-8"):
        m = QUOTED.match(line.rstrip("\n"))
        if m:
            out.update(m.group(1))
    return out


def ensure_source(cfg):
    dst = os.path.join(CACHE, cfg["src"])
    if os.path.exists(dst) and os.path.getsize(dst) > 100_000:
        return dst
    os.makedirs(CACHE, exist_ok=True)
    print(f"  fetching {cfg['src']} …")
    urllib.request.urlretrieve(cfg["url"], dst)
    return dst


def subset(cfg, text):
    from fontTools.ttLib import TTFont
    from fontTools.subset import Subsetter, Options
    src = ensure_source(cfg)
    font = TTFont(src)
    # Flatten a variable font to a single weight — a fallback only needs one.
    if "instance" in cfg and "fvar" in font:
        from fontTools.varLib.instancer import instantiateVariableFont
        instantiateVariableFont(font, cfg["instance"], inplace=True)
    opts = Options()
    opts.name_IDs = ["*"]      # keep the name table (OFL copyright/license notices)
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["FFTM"]
    ss = Subsetter(options=opts)
    ss.populate(text="".join(sorted(text)))
    ss.subset(font)
    out = os.path.join(FONTS_OUT, cfg["out"])
    font.save(out)
    return out, os.path.getsize(out), len(text)


COMMON = set(ASCII) | set(LATIN1) | set(CODE_GLYPHS) \
    | chars_in_po("messages.pot") | chars_in_po("de.po")

FONTS = [
    {
        "name": "M PLUS 1 Code (JP)",
        "src": "MPLUS1Code-VF.ttf",
        "url": "https://github.com/google/fonts/raw/main/ofl/mplus1code/MPLUS1Code%5Bwght%5D.ttf",
        "out": "MPLUS1Code.subset.ttf",
        "instance": {"wght": 400},
        "text": COMMON | chars_in_po("ja.po"),
    },
    {
        "name": "Noto Sans CJK SC (zh_CN + universal backstop)",
        "src": "NotoSansCJKsc-Regular.otf",
        "url": "https://github.com/notofonts/noto-cjk/raw/main/Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf",
        "out": "NotoSansCJKsc.subset.otf",
        "text": COMMON | chars_in_po("zh_CN.po") | set(CYRILLIC),
    },
]


def main():
    for cfg in FONTS:
        print(cfg["name"])
        out, size, nchars = subset(cfg, cfg["text"])
        print(f"  {nchars} glyphs -> {os.path.relpath(out, ROOT)}  ({size/1024:.0f} KB)")
    print("done. Re-import in Godot (or it will on next launch).")


if __name__ == "__main__":
    main()
