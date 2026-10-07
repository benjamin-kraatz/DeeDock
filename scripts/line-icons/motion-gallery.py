#!/usr/bin/env python3
"""Checks DeeDock/Resources/LineIcons/LineIconMotions.json and writes a browser gallery of it.

The gallery is one self-contained HTML file: every glyph with its own motion, plus a sample of
glyphs that play a shared fallback. Hover a tile to play it, or drag the scrubber to hold every
glyph on one frame. The page's JavaScript mirrors LineIconMotion.swift, so what plays here is what
the dock plays; keep the two in step when the format changes.

The check fails, with a message per problem, on anything the app would reject or ignore: an
unknown glyph, a part the glyph does not have, keyframes out of order, or a track that does not
end at rest.

Usage: python3 scripts/line-icons/motion-gallery.py [--out FILE] [--all] [--check]
  --out FILE  where to write the page (default: build/line-icon-motions.html, which git ignores)
  --all       include every catalog glyph instead of a sample of the fallback ones
  --check     only validate; write nothing
Needs only the Python standard library.
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RESOURCES = os.path.join(ROOT, "DeeDock", "Resources", "LineIcons")

PROPERTIES = {"rotate": 0, "x": 0, "y": 0, "turn": 0, "erase": 0, "scale": 1, "scaleX": 1, "scaleY": 1, "draw": 1}
EASINGS = ("linear", "in", "out", "inOut", "back")
FALLBACK_SAMPLE = 28


def subpaths(glyph, layer):
    """One path-data string per subpath, in catalog order: the parts a motion addresses."""
    return ["M" + piece for data in glyph.get(layer, []) for piece in data.split("M") if piece]


def problems_in(motion, counts=None):
    """Everything wrong with one motion. `counts` is (strokes, fills), or None for a fallback."""
    found = []
    duration = motion.get("duration")
    if not isinstance(duration, (int, float)) or not 0 < duration <= 3:
        found.append("duration must be above 0 and at most 3 seconds")
    tracks = motion.get("tracks")
    if not tracks:
        return found + ["no tracks"]
    for number, track in enumerate(tracks):
        where = f"track {number}"
        names = [name for name in PROPERTIES if name in track]
        if len(names) != 1:
            found.append(f"{where}: needs exactly one property, has {names or 'none'}")
            continue
        name = names[0]
        keyframes = track[name]
        times = [keyframe[0] for keyframe in keyframes]
        spread = track.get("spread", 0)
        if not keyframes or times != sorted(set(times)) or times[0] < 0 or times[-1] + spread > 1 + 1e-9:
            found.append(f"{where}: keyframe times must ascend within 0...1, leaving room for the spread")
        for keyframe in keyframes:
            if len(keyframe) not in (2, 3) or (len(keyframe) == 3 and keyframe[2] not in EASINGS):
                found.append(f"{where}: bad keyframe {keyframe}")
        last = keyframes[-1][1] if keyframes else None
        at_rest = last is not None and (abs(last - round(last / 360) * 360) < 1e-6 if name in ("rotate", "turn")
                                        else abs(last - PROPERTIES[name]) < 1e-6)
        if not at_rest:
            found.append(f"{where}: {name} ends on {last}, not on its resting value")
        parts = track.get("parts", "all")
        if isinstance(parts, list):
            for token in parts:
                layer, index = token[:1], token[1:]
                if layer not in ("s", "f") or not index.isdigit():
                    found.append(f"{where}: part {token!r} should look like s0 or f2")
                elif counts and int(index) >= counts[0 if layer == "s" else 1]:
                    found.append(f"{where}: the glyph has no part {token}")
                elif layer == "f" and name in ("draw", "erase"):
                    found.append(f"{where}: {name} only affects stroke parts, not {token}")
        elif parts not in ("all", "strokes", "fills"):
            found.append(f"{where}: parts is all, strokes, fills, or a list of tokens")
        if "anchor" in track and (not isinstance(track["anchor"], list) or len(track["anchor"]) != 2):
            found.append(f"{where}: anchor is [x, y]")
    return found


def stable_hash(text):
    """FNV-1a, the same pick LineIconMotionLibrary.stableHash makes."""
    value = 2166136261
    for byte in text.encode():
        value = ((value ^ byte) * 16777619) & 0xFFFFFFFF
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=os.path.join(ROOT, "build", "line-icon-motions.html"))
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    catalog = json.load(open(os.path.join(RESOURCES, "LineIcons.json")))
    library = json.load(open(os.path.join(RESOURCES, "LineIconMotions.json")))
    glyphs, motions = catalog["glyphs"], library.get("motions", {})
    fallbacks = library.get("fallbacks", {})

    problems = []
    for reference, motion in motions.items():
        if reference not in glyphs:
            problems.append(f"{reference}: not in the catalog")
            continue
        counts = (len(subpaths(glyphs[reference], "stroke")), len(subpaths(glyphs[reference], "fill")))
        problems += [f"{reference}: {problem}" for problem in problems_in(motion, counts)]
    for kind in ("stroke", "fill"):
        for number, motion in enumerate(fallbacks.get(kind, [])):
            problems += [f"fallbacks.{kind}[{number}]: {problem}" for problem in problems_in(motion)]
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    print(f"{len(motions)} glyphs have their own motion; "
          f"{len(fallbacks.get('stroke', []))} stroke and {len(fallbacks.get('fill', []))} fill fallbacks")
    if arguments.check:
        return

    names = {}
    for name, reference in sorted(catalog.get("appNames", {}).items()):
        names.setdefault(reference, name)
    for tile, reference in catalog.get("tiles", {}).items():
        names[reference] = f"{tile} tile"

    def tile(reference, motion, own):
        glyph = glyphs[reference]
        return {"id": reference, "name": names.get(reference, reference.split(":")[1]), "own": own,
                "about": motion.get("about", ""), "motion": motion,
                "stroke": subpaths(glyph, "stroke"), "fill": subpaths(glyph, "fill")}

    tiles = [tile(reference, motion, True) for reference, motion in motions.items()]
    others = [reference for reference in sorted(glyphs) if reference not in motions]
    if not arguments.all:
        # Every nth glyph, so the sample spans the sources instead of the first letters of one.
        others = others[::max(1, len(others) // FALLBACK_SAMPLE)][:FALLBACK_SAMPLE]
    for reference in others:
        pool = fallbacks.get("stroke" if "stroke" in glyphs[reference] else "fill", [])
        if pool:
            tiles.append(tile(reference, pool[stable_hash(reference) % len(pool)], False))

    os.makedirs(os.path.dirname(os.path.abspath(arguments.out)), exist_ok=True)
    with open(arguments.out, "w") as output:
        output.write(PAGE.replace("/*TILES*/", json.dumps(tiles, separators=(",", ":"))))
    print(f"Wrote {arguments.out}")


PAGE = r"""<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DOKK line icon motions</title>
<style>
  :root { color-scheme: dark; }
  body { margin: 0; padding: 28px 32px 48px; font: 13px/1.4 -apple-system, system-ui, sans-serif; color: #e9ecf5;
         -webkit-tap-highlight-color: transparent;
         background: radial-gradient(1200px 700px at 30% 0%, #1c3f9c 0%, #0b1a4a 45%, #060b1f 100%) fixed; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 13px; font-weight: 600; letter-spacing: .04em; text-transform: uppercase; opacity: .65; margin: 30px 0 12px; }
  p { margin: 0; opacity: .7; }
  .bar { display: flex; gap: 14px; align-items: center; margin-top: 16px; flex-wrap: wrap; }
  button { font: inherit; color: inherit; padding: 6px 14px; border-radius: 999px; border: 1px solid #ffffff38;
           background: #ffffff1c; cursor: pointer; }
  button:hover { background: #ffffff30; }
  label { display: flex; gap: 8px; align-items: center; flex: 1 1 240px; }
  input[type=range] { flex: 1; min-width: 120px; max-width: 320px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; }
  .tile { position: relative; padding: 14px 10px 12px; border-radius: 18px; text-align: center; cursor: pointer;
          user-select: none; -webkit-user-select: none; touch-action: manipulation;
          background: #0a12306b; border: 1px solid #ffffff1a; backdrop-filter: blur(18px); }
  .art { position: relative; width: 72px; height: 72px; margin: 0 auto 6px; }
  .art svg { position: absolute; inset: 0; overflow: visible; opacity: .92;
             filter: drop-shadow(0 0 1px #0009); transition: opacity .18s, filter .18s; }
  .glow { position: absolute; inset: 10%; border-radius: 50%; opacity: 0; filter: blur(18px); transition: opacity .3s;
          background: conic-gradient(#ff5fa2, #ff9a3c, #3c8cff, #a55cff, #ff5fa2); }
  .tile:hover .glow, .tile.lit .glow { opacity: .9; transition-duration: .18s; }
  .tile:hover svg, .tile.lit svg { opacity: 1; filter: drop-shadow(0 0 4px #fff9); }
  .name { font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ref { font-size: 11px; opacity: .5; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .about { font-size: 11.5px; opacity: .75; margin-top: 6px; min-height: 2.8em; }
  @media (max-width: 600px) {
    body { padding: 18px 14px 36px; }
    h1 { font-size: 18px; }
    .grid { grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); gap: 8px; }
    .tile { padding: 10px 6px 8px; border-radius: 14px; }
    .art { width: 56px; height: 56px; }
    .ref, .about { display: none; }
    .name { font-size: 12px; }
  }
  @media (hover: none) {
    .tile:hover .glow { opacity: 0; }
    .tile:hover svg { opacity: .92; filter: drop-shadow(0 0 1px #0009); }
    .tile.lit .glow { opacity: .9; }
    .tile.lit svg { opacity: 1; filter: drop-shadow(0 0 4px #fff9); }
  }
</style>
<h1>DOKK line icon motions</h1>
<p>Hover or tap a tile to play its motion, as the dock does. The scrubber holds every glyph on one frame.</p>
<div class="bar">
  <button id="play">Play all</button>
  <label>Frame <input id="scrub" type="range" min="0" max="1" step="0.005" value="1"> <span id="at">rest</span></label>
</div>
<h2>Own motion</h2>
<div class="grid" id="own"></div>
<h2>Shared fallbacks</h2>
<div class="grid" id="shared"></div>
<script>
const TILES = /*TILES*/;
const CANVAS = 24, BOX = 0.62, STROKE = 1.5, DWELL = 70;
const REST = {rotate: 0, x: 0, y: 0, turn: 0, erase: 0, scale: 1, scaleX: 1, scaleY: 1, draw: 1};
const CURVES = {linear: [0, 0, 1, 1], in: [.42, 0, 1, 1], out: [0, 0, .58, 1], inOut: [.42, 0, .58, 1], back: [.34, 1.56, .64, 1]};

// Mirrors LineIconMotion.Easing.value(at:).
function ease(name, fraction) {
  const x = Math.min(Math.max(fraction, 0), 1);
  if (name === "linear") return x;
  const [x1, y1, x2, y2] = CURVES[name];
  const curve = (t, a, b) => 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t;
  let low = 0, high = 1;
  for (let step = 0; step < 24; step++) {
    const middle = (low + high) / 2;
    if (curve(middle, x1, x2) < x) low = middle; else high = middle;
  }
  return curve((low + high) / 2, y1, y2);
}

// Mirrors LineIconMotion.Track.value(at:).
function valueAt(keyframes, time) {
  const first = keyframes[0], last = keyframes[keyframes.length - 1];
  if (time <= first[0]) return first[1];
  if (time >= last[0]) return last[1];
  const next = keyframes.findIndex(keyframe => keyframe[0] > time);
  const from = keyframes[next - 1], to = keyframes[next];
  return from[1] + (to[1] - from[1]) * ease(to[2] || "inOut", (time - from[0]) / (to[0] - from[0]));
}

// Affine transforms as [a, b, c, d, e, f]: x' = a*x + c*y + e, y' = b*x + d*y + f.
const then = (m, n) => [n[0] * m[0] + n[2] * m[1], n[1] * m[0] + n[3] * m[1], n[0] * m[2] + n[2] * m[3],
                        n[1] * m[2] + n[3] * m[3], n[0] * m[4] + n[2] * m[5] + n[4], n[1] * m[4] + n[3] * m[5] + n[5]];
const about = (change, [ax, ay]) => then(then([1, 0, 0, 1, -ax, -ay], change), [1, 0, 0, 1, ax, ay]);

// Mirrors LineIconMotion.pose(for:at:strokeCount:fillCount:).
function pose(motion, layer, index, strokes, fills, progress) {
  const result = {matrix: [1, 0, 0, 1, 0, 0], start: 0, end: 1};
  if (progress >= 1) return result;
  for (const track of motion.tracks) {
    const parts = track.parts || "all";
    let slot = -1, count = 0;
    if (Array.isArray(parts)) { slot = parts.indexOf(layer + index); count = parts.length; }
    else if (parts === "all") { slot = layer === "s" ? index : strokes + index; count = strokes + fills; }
    else if (parts === "strokes" && layer === "s") { slot = index; count = strokes; }
    else if (parts === "fills" && layer === "f") { slot = index; count = fills; }
    if (slot < 0) continue;
    const name = Object.keys(REST).find(key => key in track);
    const delay = count > 1 ? (track.spread || 0) * slot / (count - 1) : 0;
    const value = valueAt(track[name], progress - delay), anchor = track.anchor || [12, 12];
    const radians = value * Math.PI / 180;
    let change;
    switch (name) {
      case "rotate": change = about([Math.cos(radians), Math.sin(radians), -Math.sin(radians), Math.cos(radians), 0, 0], anchor); break;
      case "x": change = [1, 0, 0, 1, value, 0]; break;
      case "y": change = [1, 0, 0, 1, 0, value]; break;
      case "scale": change = about([value, 0, 0, value, 0, 0], anchor); break;
      case "scaleX": change = about([value, 0, 0, 1, 0, 0], anchor); break;
      case "scaleY": change = about([1, 0, 0, value, 0, 0], anchor); break;
      case "turn": change = about([Math.cos(radians), 0, 0, 1, 0, 0], anchor); break;
      case "draw": result.end = Math.min(Math.max(value, 0), 1); continue;
      case "erase": result.start = Math.min(Math.max(value, 0), 1); continue;
    }
    result.matrix = then(result.matrix, change);
  }
  return result;
}

// Catalog path data is absolute M, L, C, and Z only, so every number pair is a point.
function moved(data, m) {
  return data.replace(/(-?\d*\.?\d+)[ ,]+(-?\d*\.?\d+)/g, (_, px, py) => {
    const x = +px, y = +py;
    return `${+(m[0] * x + m[2] * y + m[4]).toFixed(3)} ${+(m[1] * x + m[3] * y + m[5]).toFixed(3)}`;
  });
}

function build(tile) {
  const NS = "http://www.w3.org/2000/svg";
  const filledMark = tile.stroke.length === 0;
  const side = CANVAS / (BOX * (filledMark ? 0.86 : 1)), inset = (side - CANVAS) / 2;
  const svg = document.createElementNS(NS, "svg");
  svg.setAttribute("viewBox", `${-inset} ${-inset} ${side} ${side}`);
  const fill = document.createElementNS(NS, "path");
  fill.setAttribute("fill", "#fff");
  if (tile.fill.length) svg.append(fill);
  const strokes = tile.stroke.map(() => {
    const path = document.createElementNS(NS, "path");
    for (const [key, value] of Object.entries({fill: "none", stroke: "#fff", "stroke-width": STROKE,
         "stroke-linecap": "round", "stroke-linejoin": "round", pathLength: 1})) path.setAttribute(key, value);
    svg.append(path);
    return path;
  });
  const draw = progress => {
    fill.setAttribute("d", tile.fill.map((data, index) =>
      moved(data, pose(tile.motion, "f", index, tile.stroke.length, tile.fill.length, progress).matrix)).join(""));
    strokes.forEach((path, index) => {
      const posed = pose(tile.motion, "s", index, tile.stroke.length, tile.fill.length, progress);
      path.setAttribute("d", moved(tile.stroke[index], posed.matrix));
      const whole = posed.start <= 0 && posed.end >= 1;
      path.style.visibility = posed.end > posed.start ? "visible" : "hidden";
      path.style.strokeDasharray = whole ? "none" : `${posed.end - posed.start} 2`;
      path.style.strokeDashoffset = whole ? 0 : -posed.start;
    });
  };
  draw(1);

  const element = document.createElement("div");
  element.className = "tile";
  element.title = tile.id;
  element.innerHTML = `<div class="art"><div class="glow"></div></div><div class="name"></div><div class="ref"></div><div class="about"></div>`;
  element.querySelector(".art").append(svg);
  element.querySelector(".name").textContent = tile.name;
  element.querySelector(".ref").textContent = tile.id;
  element.querySelector(".about").textContent = tile.about;

  let playing = false, dwell;
  const play = () => {
    if (playing) return;
    playing = true;
    element.classList.add("lit");
    const began = performance.now();
    const frame = now => {
      const progress = Math.min((now - began) / (tile.motion.duration * 1000), 1);
      draw(progress);
      if (progress < 1) requestAnimationFrame(frame); else { playing = false; element.classList.remove("lit"); }
    };
    requestAnimationFrame(frame);
  };
  element.addEventListener("mouseenter", () => { dwell = setTimeout(play, DWELL); });
  element.addEventListener("mouseleave", () => clearTimeout(dwell));
  // Touch screens have no hover, so a tap plays the tile and lights its glow for the duration.
  element.addEventListener("click", play);
  return {element, draw, play, own: tile.own};
}

const built = TILES.map(build);
for (const tile of built) document.getElementById(tile.own ? "own" : "shared").append(tile.element);
document.getElementById("play").addEventListener("click", () => built.forEach(tile => tile.play()));
const scrub = document.getElementById("scrub"), at = document.getElementById("at");
const hold = () => {
  at.textContent = +scrub.value >= 1 ? "rest" : (+scrub.value).toFixed(2);
  built.forEach(tile => tile.draw(+scrub.value));
};
scrub.addEventListener("input", hold);
// ?t=0.35 opens the page held on that frame, for screenshots.
const held = new URLSearchParams(location.search).get("t");
if (held !== null) { scrub.value = held; hold(); }
</script>
</html>
"""


if __name__ == "__main__":
    main()
