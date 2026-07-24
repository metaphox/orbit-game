#!/usr/bin/env python3
"""i18n lint (wired into tools/test.sh). Three checks:

  (A) coverage  — de.po / zh.po translate every messages.pot msgid.
  (B) tr-in-pot — every tr("literal") in src is a messages.pot msgid (else it
                  silently falls back to English at runtime).
  (C) prose     — no untranslated user-facing prose literal in display code:
                  a string literal that carries real words, is neither tr()-wrapped
                  nor a pot msgid, and isn't intentional English notation.

Intentional English (cockpit notation, units, key names) is recognised by the
NOTATION allowlist below; anything genuinely meant to stay English on a case
basis can carry a trailing `# i18n-ok: <reason>` comment on its line.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRANS = os.path.join(ROOT, "assets", "translations")

# Files that render user-facing text. Kept explicit so unrelated .gd (sim math,
# save IO, debug prints) don't trip the prose scan.
SCAN_DIRS = ["src/ui", "src/objectives", "src/autopilot"]
SCAN_FILES = ["src/game_root.gd", "src/campaign_root.gd", "src/sim/ship_sim.gd"]
# Infrastructure with no translatable UI text: theme/colour tokens, and the 3D
# world renderers (node paths, mesh names, dev-facing push_error messages).
EXCLUDE = ("src/ui/theme/", "src/ui/world/")

# Uppercase cockpit/telemetry notation and units deliberately kept English.
# (Translated words like NODE/BURN/PAR are NOT here — they belong in the POT.)
NOTATION = {
    "MET", "ALT", "VEL", "WARP", "SOI", "ACC", "THR", "PROP", "AP", "PE", "TGT",
    "OFF", "PRO", "FPS", "SAS", "DIST", "RADAR", "CORRIDOR", "INC", "REL",
    "CLOSEST", "HS", "VS", "KM",
}

IDENT_RE = re.compile(r"^[a-z][A-Za-z0-9_]*$")  # identifier / action / dict key / locale code (zh_CN)

STRING_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
WORD_RE = re.compile(r"[A-Za-z]{2,}")
# printf-style specifiers, so "%.2f km" reduces to just "km".
FMT_RE = re.compile(r"%[-+0-9.# ]*[a-zA-Z%]")


def parse_po(path):
    entries = {}
    ctx = key = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = re.match(r'^msgctxt "(.*)"$', line)
            if m:
                ctx = m.group(1)
                continue
            m = re.match(r'^msgid "(.*)"$', line)
            if m:
                key = (ctx, m.group(1))
                ctx = None
                continue
            m = re.match(r'^msgstr "(.*)"$', line)
            if m and key is not None:
                entries[key] = m.group(1)
                key = None
    entries.pop((None, ""), None)  # header
    return entries


def gd_files():
    out = []
    for d in SCAN_DIRS:
        for root, _dirs, files in os.walk(os.path.join(ROOT, d)):
            out += [os.path.join(root, f) for f in files if f.endswith(".gd")]
    out += [os.path.join(ROOT, f) for f in SCAN_FILES]
    out = [p for p in out if not any(x in p.replace(os.sep, "/") for x in EXCLUDE)]
    return sorted(out)


def is_prose(literal):
    """True if the literal is user-facing text needing translation: it carries a
    real word once notation/format specifiers are removed, and is not a code
    identifier (snake_case) or a resource path."""
    if "://" in literal or (IDENT_RE.match(literal) and " " not in literal):
        return False
    if re.match(r"^%[A-Za-z][A-Za-z0-9]*$", literal):  # %UniqueNodeName lookup
        return False
    stripped = FMT_RE.sub(" ", literal)
    return any(w.upper() not in NOTATION for w in WORD_RE.findall(stripped))


def main():
    pot = parse_po(os.path.join(TRANS, "messages.pot"))
    pot_ids = {mid for _ctx, mid in pot}
    errors = []

    # (A) coverage
    for loc in ("de", "zh_CN", "ja"):  # zh_TW is a deferred placeholder (not enforced)
        po = parse_po(os.path.join(TRANS, f"{loc}.po"))
        for key in pot:
            if not po.get(key):
                errors.append(f"[coverage] {loc}.po missing translation for {key[1]!r}")

    # (B) + (C) source scan
    for path in gd_files():
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as fh:
            for n, line in enumerate(fh, 1):
                code = line.split("#", 1)[0]
                if '"' not in code:
                    continue
                exempt = "# i18n-ok" in line
                for m in STRING_RE.finditer(code):
                    literal = m.group(1)
                    before = code[:m.start()]
                    tr_wrapped = re.search(r'\btr\(\s*$', before) is not None
                    if tr_wrapped:
                        # (B) tr()'d strings must exist in the POT.
                        if literal not in pot_ids:
                            errors.append(f"[tr-not-in-pot] {rel}:{n}  tr({literal!r})")
                    elif not exempt and literal not in pot_ids and is_prose(literal):
                        # (C) prose displayed without tr() and not a msgid.
                        errors.append(f"[untranslated] {rel}:{n}  {literal!r}")

    if errors:
        print("\033[31mi18n LINT FAILED:\033[0m")
        for e in errors:
            print("  " + e)
        print(f"\n{len(errors)} issue(s). Wrap in tr() + add to messages.pot, or mark "
              "the line `# i18n-ok: <reason>` if it is intentionally English.")
        return 1
    print("\033[32mi18n lint OK\033[0m - de/zh_CN/ja cover the POT; no untranslated prose in display code.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
