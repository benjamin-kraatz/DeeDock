#!/usr/bin/env python3
"""Builds DeeDock/Resources/LineIcons/LineIcons.json, the bundled catalog behind the Line icon style.

Inputs, all under scripts/line-icons/:
  sources.json     pinned npm versions of Lucide (ISC) and Simple Icons (CC0-1.0)
  apps/*.json      curated entries: [{"icon": "<source>:<name>", "bundleIDs": [...], "names": [...]}]
  tiles.json       DOKK tile kinds ("launcher", "trash", ...) -> icon reference
  custom/*.svg     hand-drawn 24x24 line glyphs for apps neither library covers

Icon references are "lucide:<name>", "simple-icons:<slug>", or "custom:<file name without .svg>".
Lucide and custom glyphs are strokes; Simple Icons marks are filled silhouettes. Every path is
normalized to a 24x24 box and to absolute M, L, C, and Z commands, so the app's parser stays small.

Usage: python3 scripts/line-icons/build-line-icons.py [--cache DIR]
Needs network access for `npm pack` unless --cache already holds the extracted packages, and the
`svgelements` Python package (pip install svgelements).
"""
import argparse
import glob
import io
import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile

from svgelements import SVG, Arc, Close, CubicBezier, Line, Move, Path, QuadraticBezier, Shape

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, "scripts", "line-icons")
DESTINATION = os.path.join(ROOT, "DeeDock", "Resources", "LineIcons")


def fetch(package, version, cache):
    folder = os.path.join(cache, f"{package}-{version}")
    if not os.path.isdir(folder):
        os.makedirs(folder)
        archive = subprocess.check_output(["npm", "pack", f"{package}@{version}", "--silent"], cwd=cache).decode().strip()
        with tarfile.open(os.path.join(cache, archive)) as tar:
            tar.extractall(folder)
    return os.path.join(folder, "package")


def number(value):
    text = f"{value:.2f}".rstrip("0").rstrip(".")
    return "0" if text in ("-0", "") else text


def point(p):
    return f"{number(p.x)} {number(p.y)}"


def normalized(path):
    """Absolute M/L/C/Z path data. Arcs become cubics; quadratics are raised to cubics."""
    commands = []
    for segment in path:
        if isinstance(segment, Move):
            commands.append(f"M{point(segment.end)}")
        elif isinstance(segment, Close):
            commands.append("Z")
        elif isinstance(segment, Line):
            commands.append(f"L{point(segment.end)}")
        elif isinstance(segment, CubicBezier):
            commands.append(f"C{point(segment.control1)} {point(segment.control2)} {point(segment.end)}")
        elif isinstance(segment, QuadraticBezier):
            s, c, e = segment.start, segment.control, segment.end
            c1 = (s.x + 2 / 3 * (c.x - s.x), s.y + 2 / 3 * (c.y - s.y))
            c2 = (e.x + 2 / 3 * (c.x - e.x), e.y + 2 / 3 * (c.y - e.y))
            commands.append(f"C{number(c1[0])} {number(c1[1])} {number(c2[0])} {number(c2[1])} {point(e)}")
        elif isinstance(segment, Arc):
            for cubic in segment.as_cubic_curves():
                commands.append(f"C{point(cubic.control1)} {point(cubic.control2)} {point(cubic.end)}")
        else:
            raise ValueError(f"Unsupported segment {type(segment).__name__}")
    return "".join(commands)


def glyph(svg_text, default_mode):
    """Splits an SVG into stroked and filled 24x24 paths."""
    document = SVG.parse(io.StringIO(svg_text), reify=True, width=24, height=24)
    stroke, fill = [], []
    for element in document.elements():
        if not isinstance(element, Shape):
            continue
        values = getattr(element, "values", {})
        fill_value = (values.get("fill") or "").strip().lower()
        stroke_value = (values.get("stroke") or "").strip().lower()
        data = normalized(Path(element))
        if not data:
            continue
        if default_mode == "fill":
            fill.append(data)
        elif fill_value not in ("", "none") and stroke_value in ("", "none"):
            fill.append(data)
        else:
            stroke.append(data)
    result = {}
    if stroke:
        result["stroke"] = stroke
    if fill:
        result["fill"] = fill
    if not result:
        raise ValueError("SVG has no drawable shapes")
    return result


def name_key(name):
    """Matches the app's lookup: lowercased, without the .app extension."""
    name = name.strip()
    if name.lower().endswith(".app"):
        name = name[:-4]
    return name.lower()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", help="Directory that holds or receives the npm packages")
    arguments = parser.parse_args()
    cache = arguments.cache or tempfile.mkdtemp(prefix="line-icons-")
    os.makedirs(cache, exist_ok=True)

    sources = json.load(open(os.path.join(HERE, "sources.json")))
    lucide = fetch("lucide-static", sources["lucide-static"], cache)
    simple = fetch("simple-icons", sources["simple-icons"], cache)

    def load(reference):
        source, _, name = reference.partition(":")
        if source == "lucide":
            return glyph(open(os.path.join(lucide, "icons", f"{name}.svg")).read(), "stroke")
        if source == "simple-icons":
            return glyph(open(os.path.join(simple, "icons", f"{name}.svg")).read(), "fill")
        if source == "custom":
            return glyph(open(os.path.join(HERE, "custom", f"{name}.svg")).read(), "stroke")
        raise ValueError(f"Unknown icon source in {reference}")

    glyphs, bundles, names, problems = {}, {}, {}, []

    def use(reference, context):
        if reference not in glyphs:
            try:
                glyphs[reference] = load(reference)
            except (OSError, ValueError) as error:
                problems.append(f"{context}: {reference}: {error}")
                return False
        return True

    for file in sorted(glob.glob(os.path.join(HERE, "apps", "*.json"))):
        for entry in json.load(open(file)):
            reference = entry["icon"]
            if not use(reference, os.path.basename(file)):
                continue
            for identifier in entry.get("bundleIDs", []):
                if bundles.get(identifier, reference) != reference:
                    problems.append(f"{os.path.basename(file)}: {identifier} maps to both {bundles[identifier]} and {reference}")
                bundles.setdefault(identifier, reference)
            for name in entry.get("names", []):
                names.setdefault(name_key(name), reference)

    tiles = {}
    for kind, reference in json.load(open(os.path.join(HERE, "tiles.json"))).items():
        if use(reference, "tiles.json"):
            tiles[kind] = reference

    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)

    os.makedirs(DESTINATION, exist_ok=True)
    catalog = {
        "source": f"Lucide {sources['lucide-static']} (ISC), Simple Icons {sources['simple-icons']} (CC0-1.0), "
                  "and DOKK-drawn glyphs. Generated by scripts/line-icons/build-line-icons.py; do not edit.",
        "glyphs": dict(sorted(glyphs.items())),
        "bundleIdentifiers": dict(sorted(bundles.items())),
        "appNames": dict(sorted(names.items())),
        "tiles": dict(sorted(tiles.items())),
    }
    with open(os.path.join(DESTINATION, "LineIcons.json"), "w") as output:
        json.dump(catalog, output, separators=(",", ":"), ensure_ascii=False)
        output.write("\n")
    with open(os.path.join(lucide, "LICENSE")) as source, open(os.path.join(DESTINATION, "LucideLicense.txt"), "w") as target:
        target.write(source.read())
    with open(os.path.join(simple, "LICENSE.md")) as source, open(os.path.join(DESTINATION, "SimpleIconsLicense.txt"), "w") as target:
        target.write(source.read())
    print(f"{len(glyphs)} glyphs, {len(bundles)} bundle identifiers, {len(names)} app names, {len(tiles)} tiles")


if __name__ == "__main__":
    main()
