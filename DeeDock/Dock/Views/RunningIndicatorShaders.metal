#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Each style is a layer effect, not a color effect: it reads the application artwork it
// decorates, so the light follows the icon's own alpha silhouette and borrows the icon's
// own colors. The artwork itself is returned untouched; only transparent pixels around it
// and a narrow rim just inside it are lit.
//
// Positions arrive in SwiftUI logical points. Normalize each icon to [-1, 1] without
// consulting display pixels, so the artwork survives magnification and backing-scale changes.
static float2 indicatorPoint(float2 position, float size) {
    return position / max(size, 1.0f) * 2.0f - 1.0f;
}

// Per-icon variation comes from one seed, so a bundle identifier always produces the same
// lobe count, spin direction, and phase. `salt` separates the independent draws.
static float hash11(float seed, float salt) {
    return fract(sin(seed * 127.1f + salt * 311.7f) * 43758.5453123f);
}

// An integer harmonic of the animation cycle. Every time-dependent term must be an integer
// multiple of `turn`, because the host wraps elapsed time once per cycle to keep float
// precision; a non-integer rate would visibly jump at the wrap.
static float harmonic(float seed, float salt, float low, float high) {
    return floor(low + hash11(seed, salt) * (high - low + 1.0f));
}

static float3 spectrum(float phase) {
    return 0.55f + 0.45f * cos(6.2831853f * (phase + float3(0.0f, 0.33f, 0.67f)));
}

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1f, 311.7f))) * 43758.5453123f);
}

static float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 offset = fract(p);
    float2 blend = offset * offset * (3.0f - 2.0f * offset);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0f, 0.0f));
    float c = hash21(cell + float2(0.0f, 1.0f));
    float d = hash21(cell + float2(1.0f, 1.0f));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

// Three octaves are enough for a molten surface at icon scale and keep the per-pixel cost
// in the same order as the silhouette sampling below.
static float fbm(float2 p) {
    float sum = 0.0f;
    float amplitude = 0.5f;
    for (int octave = 0; octave < 3; ++octave) {
        sum += valueNoise(p) * amplitude;
        p *= 2.03f;
        amplitude *= 0.5f;
    }
    return sum / 0.875f;
}

/// What the shader knows about the artwork underneath a single output pixel.
struct IconEdge {
    /// Distance to the silhouette boundary, normalized by the sample radius.
    /// Negative on the artwork, positive in the transparent margin around it.
    float depth;
    /// Alpha-weighted color of the artwork within reach of this pixel.
    float3 bleed;
    /// Artwork alpha at this exact pixel.
    float coverage;
};

// One spiral of samples yields the signed silhouette distance and the nearby artwork color
// in a single pass. Rings are rotated against each other so no axis is left unsampled.
static IconEdge iconEdge(SwiftUI::Layer layer, float2 position, float radius) {
    constexpr int rings = 4;
    constexpr int spokes = 12;
    constexpr float solid = 0.35f;
    half4 here = layer.sample(position);
    float nearestOpaque = 1.0f;
    float nearestClear = 1.0f;
    float3 sum = float3(0.0f);
    float weight = 0.0f;
    for (int ring = 1; ring <= rings; ++ring) {
        float t = float(ring) / float(rings);
        float reach = t * radius;
        for (int spoke = 0; spoke < spokes; ++spoke) {
            float angle = (float(spoke) + 0.5f * float(ring)) / float(spokes) * 6.2831853f;
            half4 taken = layer.sample(position + float2(cos(angle), sin(angle)) * reach);
            float alpha = float(taken.a);
            nearestOpaque = min(nearestOpaque, mix(1.0f, t, step(solid, alpha)));
            nearestClear = min(nearestClear, mix(1.0f, t, step(alpha, solid)));
            // Layer samples are premultiplied, so this sum is already alpha-weighted.
            sum += float3(taken.rgb);
            weight += alpha;
        }
    }
    IconEdge edge;
    edge.coverage = float(here.a);
    edge.bleed = weight > 0.001f ? sum / weight : float3(1.0f);
    edge.depth = edge.coverage > solid ? -nearestClear : nearestOpaque;
    return edge;
}

// The artwork drives the hue; each style's own palette keeps grey icons from glowing white.
// `accentStrength` is zero when the icon has no dominant hue worth using.
static float3 iconTint(float3 bleed, half4 accent, float accentStrength, float3 palette, float share) {
    float3 art = mix(bleed, float3(accent.rgb), accentStrength * 0.45f);
    float peak = max(art.r, max(art.g, art.b));
    float valley = min(art.r, min(art.g, art.b));
    float saturation = peak > 0.001f ? (peak - valley) / peak : 0.0f;
    // Normalize brightness so a dark icon lights as strongly as a bright one, then pull
    // near-grey artwork back toward white before it is mixed with the palette.
    float3 vivid = peak > 0.001f ? art / peak : float3(1.0f);
    vivid = mix(float3(1.0f), vivid, saturate(saturation * 2.2f));
    return mix(palette, vivid, share * saturate(0.2f + saturation * 1.7f));
}

// A light on the artwork side of the boundary. Icons that fill their whole square have no
// transparent margin to glow into, so without this they would show no indicator at all.
static float innerRim(float depth, float falloff) {
    return depth < 0.0f ? exp(depth / falloff) : 0.0f;
}

// SwiftUI compositing is premultiplied: never leave RGB in a transparent pixel, and never
// let a channel exceed its own alpha. The glow sits behind the artwork; the rim is added
// over it. Reduce Transparency replaces graduated light with solid bands.
static half4 indicatorComposite(half4 source, float3 glow, float glowAlpha,
                                float3 rim, float rimAlpha, float2 p, float opaque) {
    // Even blurred artwork must stay inside its own icon when item spacing is zero.
    float fence = 1.0f - smoothstep(0.93f, 1.0f, max(abs(p.x), abs(p.y)));
    glowAlpha = saturate(glowAlpha);
    rimAlpha = saturate(rimAlpha);
    if (opaque > 0.5f) {
        glowAlpha = smoothstep(0.16f, 0.34f, glowAlpha);
        rimAlpha = smoothstep(0.16f, 0.34f, rimAlpha);
    }
    half behind = half(glowAlpha * fence) * (1.0h - source.a);
    half4 result = source + half4(half3(saturate(glow)) * behind, behind);
    result.rgb += half3(saturate(rim)) * half(rimAlpha * fence) * source.a;
    result.rgb = min(result.rgb, half3(result.a));
    return result;
}

// Two interfering waves ride around the silhouette as an electric filament and its corona.
[[ stitchable ]] half4 deeDockPlasma(float2 position, SwiftUI::Layer layer, float size, float radius,
                                     float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    IconEdge edge = iconEdge(layer, position, radius);
    float angle = atan2(p.y, p.x);
    float lobes = 5.0f + floor(hash11(seed, 1.0f) * 7.0f);
    float drift = mix(-1.0f, 1.0f, step(0.5f, hash11(seed, 2.0f)));
    float rate = harmonic(seed, 3.0f, 12.0f, 34.0f) * drift;
    float counter = harmonic(seed, 5.0f, 5.0f, 17.0f) * drift;
    float phase = hash11(seed, 4.0f) * 6.2831853f;
    float ripple = sin(angle * lobes + turn * rate + phase) * 0.20f
                 + sin(angle * lobes * 3.0f - turn * counter + phase * 1.7f) * 0.11f;
    float band = edge.depth - (0.24f + ripple * 0.16f);
    float filament = exp(-band * band / 0.010f);
    float corona = exp(-band * band / 0.150f) * 0.45f;
    float3 palette = mix(float3(0.42f, 0.08f, 1.0f), float3(0.10f, 0.95f, 1.0f),
                         0.5f + 0.5f * sin(angle * 3.0f + phase + turn * 3.0f * drift));
    float3 rgb = iconTint(edge.bleed, accent, accentStrength, palette, 0.55f);
    float3 hot = mix(rgb, float3(0.90f, 1.0f, 1.0f), filament * 0.6f);
    float rim = innerRim(edge.depth, 0.16f) * (0.45f + 0.35f * sin(angle * lobes + turn * rate + phase));
    return indicatorComposite(layer.sample(position), hot, filament + corona, rgb, rim, p, opaque);
}

// A diffraction rim with travelling scan lines and one reflection sweeping across the icon.
[[ stitchable ]] half4 deeDockHologram(float2 position, SwiftUI::Layer layer, float size, float radius,
                                       float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    IconEdge edge = iconEdge(layer, position, radius);
    float tilt = hash11(seed, 1.0f) * 3.1415927f;
    float2 axis = float2(cos(tilt), sin(tilt));
    float2 across = float2(-axis.y, axis.x);
    float frequency = 34.0f + hash11(seed, 2.0f) * 46.0f;
    float sweeps = harmonic(seed, 3.0f, 8.0f, 16.0f);
    float scan = 0.62f + 0.38f * cos(dot(p, across) * frequency - turn * 90.0f);
    float travel = fract(turn / 6.2831853f * sweeps + hash11(seed, 4.0f)) * 2.8f - 1.4f;
    float sweep = exp(-pow((dot(p, axis) - travel) / 0.22f, 2.0f));
    float rim = exp(-pow((edge.depth - 0.20f) / 0.30f, 2.0f));
    float3 palette = spectrum(dot(p, axis) * 0.6f + seed + turn / 6.2831853f * 2.0f);
    float3 rgb = iconTint(edge.bleed, accent, accentStrength, palette, 0.45f);
    rgb = mix(rgb, float3(0.88f, 1.0f, 1.0f), sweep * 0.8f);
    return indicatorComposite(layer.sample(position), rgb, rim * scan * 0.95f,
                              rgb, innerRim(edge.depth, 0.14f) * scan * (0.3f + sweep * 0.6f), p, opaque);
}

// A hot seam around the silhouette, with irregular rays reaching into the margin.
[[ stitchable ]] half4 deeDockSolarFlare(float2 position, SwiftUI::Layer layer, float size, float radius,
                                         float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    IconEdge edge = iconEdge(layer, position, radius);
    float rays = 11.0f + floor(hash11(seed, 1.0f) * 17.0f);
    float spin = harmonic(seed, 2.0f, 2.0f, 5.0f) * mix(-1.0f, 1.0f, step(0.5f, hash11(seed, 3.0f)));
    float phase = hash11(seed, 4.0f) * 6.2831853f;
    float angle = atan2(p.y, p.x) + turn * spin + phase;
    float crown = pow(0.5f + 0.5f * sin(angle * rays + sin(angle * 3.0f + turn * 40.0f)), 3.0f);
    float flicker = 0.85f + 0.15f * sin(turn * 150.0f + phase);
    float reach = (0.16f + crown * 0.60f) * flicker;
    float corona = edge.depth >= 0.0f ? exp(-edge.depth / max(reach, 0.05f)) : 0.0f;
    float core = exp(-pow(edge.depth / 0.11f, 2.0f));
    float heat = saturate(edge.depth / 0.6f);
    float3 palette = mix(float3(1.0f, 0.92f, 0.35f), float3(1.0f, 0.12f, 0.03f), heat);
    float3 rgb = iconTint(edge.bleed, accent, accentStrength, palette, 0.40f);
    float3 hot = mix(rgb, float3(1.0f, 1.0f, 0.85f), core * 0.65f);
    return indicatorComposite(layer.sample(position), hot, corona + core,
                              hot, innerRim(edge.depth, 0.12f) * flicker * 0.55f, p, opaque);
}

// Discrete spectral facets turning slowly around the silhouette, with bright seams.
[[ stitchable ]] half4 deeDockPrism(float2 position, SwiftUI::Layer layer, float size, float radius,
                                    float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    IconEdge edge = iconEdge(layer, position, radius);
    float facets = 6.0f + floor(hash11(seed, 1.0f) * 7.0f);
    float spin = harmonic(seed, 2.0f, 2.0f, 6.0f) * mix(-1.0f, 1.0f, step(0.5f, hash11(seed, 3.0f)));
    float angle = atan2(p.y, p.x) + turn * spin + hash11(seed, 4.0f) * 6.2831853f;
    float wheel = (angle + 3.1415927f) / 6.2831853f * facets;
    float facet = floor(wheel);
    // Distance to the nearest facet seam, zero on the seam itself.
    float seam = abs(fract(wheel) - 0.5f) * 2.0f;
    float bevel = exp(-pow((edge.depth - 0.22f) / 0.28f, 2.0f));
    float3 palette = spectrum(facet / facets + seed);
    float3 rgb = iconTint(edge.bleed, accent, accentStrength, palette, 0.50f);
    float highlight = smoothstep(0.12f, 0.0f, seam);
    float3 lit = mix(rgb, float3(1.0f), highlight * 0.7f);
    return indicatorComposite(layer.sample(position), lit, bevel * (0.55f + highlight * 0.45f),
                              lit, innerRim(edge.depth, 0.13f) * (0.3f + highlight * 0.5f), p, opaque);
}

// Molten metal creeping in from the icon's outline. Flow noise displaces the artwork along
// its outward normal, so corners and edges are chewed away or dragged into drips while the
// middle of the icon is never touched and the application stays recognizable.
[[ stitchable ]] half4 deeDockLavaChrome(float2 position, SwiftUI::Layer layer, float size, float radius,
                                         float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    IconEdge edge = iconEdge(layer, position, radius);
    // The noise is sampled along wide circular orbits rather than translated: translation is
    // not periodic in the animation cycle and the wrap would show as a jump, but an orbit
    // this large still sweeps whole features through the icon.
    float churnA = harmonic(seed, 1.0f, 5.0f, 9.0f);
    float churnB = harmonic(seed, 5.0f, 11.0f, 19.0f);
    float grain = 2.0f + hash11(seed, 2.0f) * 1.6f;
    float2 orbitA = float2(cos(turn * churnA), sin(turn * churnA)) * 1.6f;
    float2 orbitB = float2(cos(turn * churnB), -sin(turn * churnB)) * 1.1f;
    // Domain warping — one noise field displacing the input of another — is what makes the
    // surface boil and fold instead of merely sliding past.
    float2 warp = float2(fbm(p * grain + orbitA), fbm(p * grain * 1.7f + orbitB)) - 0.5f;
    float flow = fbm(p * grain * 1.4f + warp * 1.8f + orbitB * 0.5f);

    // Corners lie furthest from the centre, so weighting the bite by radius eats them first.
    float exposure = smoothstep(0.45f, 1.0f, length(p));
    // The melt line advances and retreats, so the metal is visibly feeding rather than
    // sitting at a fixed depth.
    float tide = 0.72f + 0.28f * sin(turn * harmonic(seed, 6.0f, 3.0f, 7.0f) + hash11(seed, 7.0f) * 6.2831853f);
    float appetite = (0.55f + hash11(seed, 3.0f) * 0.45f) * tide;
    float chew = (flow - 0.42f) * exposure * appetite;
    // Molten material is heavy: biasing the displacement downward turns the overhangs into
    // drips instead of a uniform ring of erosion.
    float2 radial = length(p) > 0.001f ? normalize(p) : float2(0.0f, 1.0f);
    float2 outward = normalize(radial + float2(0.0f, 0.42f));
    // Positive chew samples further out, so the artwork recedes; negative drags it into a drip.
    half4 source = layer.sample(position + outward * chew * radius);
    // The distance field is shifted by what the artwork was shifted by, which holds while
    // the displacement runs along the normal.
    float melted = edge.depth + chew;

    float seam = exp(-melted * melted / 0.020f);
    float shell = melted > 0.0f ? smoothstep(0.85f, 0.0f, melted) : 0.0f;
    float3 tint = iconTint(edge.bleed, accent, accentStrength, float3(0.62f, 0.66f, 0.74f), 0.35f);
    // Hard tonal banding plus one narrow specular streak reads as polished metal; a smooth
    // gradient reads as plastic.
    float bands = fract(flow * 3.0f + 0.15f);
    float3 chrome = mix(float3(0.10f, 0.11f, 0.14f), float3(0.90f, 0.93f, 1.0f), smoothstep(0.15f, 0.85f, bands));
    chrome = mix(chrome, tint, 0.30f) + pow(saturate(bands), 12.0f) * 0.6f;
    float3 lava = mix(float3(1.0f, 0.96f, 0.78f), float3(0.72f, 0.06f, 0.01f), saturate(melted / 0.55f));
    float heat = saturate(seam * 1.3f + shell * flow * 0.3f);
    float3 rgb = mix(chrome, lava, heat);
    float rim = innerRim(melted, 0.10f) * (0.35f + flow * 0.5f);
    return indicatorComposite(source, rgb, max(shell * (0.55f + flow * 0.45f), seam), lava, rim, p, opaque);
}

// Intermittent signal failure. Whole rows slip sideways, the colour channels separate, and
// tear bars cut across in the style's original cyan and magenta. Bursts are quantized in
// time so the icon reads normally between them instead of shimmering without pause.
[[ stitchable ]] half4 deeDockGlitch(float2 position, SwiftUI::Layer layer, float size, float radius,
                                     float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    float cycle = turn / 6.2831853f;
    float frame = floor(cycle * 600.0f);
    float episode = floor(cycle * 40.0f);
    // A floor keeps a still indicator — Reduce Motion, or animation switched off — looking
    // broken rather than merely offset.
    float energy = max(0.30f, step(0.62f, hash11(seed + episode, 7.0f))
                              * (0.45f + hash11(seed + episode, 8.0f) * 0.55f));

    float rows = 6.0f + floor(hash11(seed, 1.0f) * 10.0f);
    float row = floor((p.y * 0.5f + 0.5f) * rows);
    // Only some rows move. Displacing all of them at once reads as a wobble, not a fault.
    float slip = (hash11(seed + row * 3.0f + frame, 2.0f) - 0.5f) * energy * 0.22f
               * step(0.45f, hash11(seed + row + frame, 3.0f));
    float split = (0.02f + energy * 0.05f) * mix(-1.0f, 1.0f, step(0.5f, hash11(seed, 4.0f)));

    float2 offset = float2(slip * size, 0.0f);
    float2 aberration = float2(split * size, 0.0f);
    half4 warm = layer.sample(position + offset + aberration);
    half4 mid = layer.sample(position + offset);
    half4 cool = layer.sample(position + offset - aberration);
    // The union of the three alphas keeps a solid silhouette with coloured fringes, and each
    // premultiplied channel still sits at or below it.
    half4 source = half4(warm.r, mid.g, cool.b, max(warm.a, max(mid.a, cool.a)));

    float3 bleed = mid.a > 0.01h ? float3(mid.rgb) / float(mid.a) : float3(1.0f);
    float3 cyan = iconTint(bleed, accent, accentStrength, float3(0.10f, 0.95f, 1.0f), 0.30f);
    float3 magenta = iconTint(bleed, accent, accentStrength, float3(1.0f, 0.18f, 0.72f), 0.30f);
    float upper = 1.0f - smoothstep(0.0f, 0.06f, abs(p.y - (hash11(seed + frame, 5.0f) * 1.9f - 0.95f)));
    float lower = 1.0f - smoothstep(0.0f, 0.04f, abs(p.y - (hash11(seed + frame, 6.0f) * 1.9f - 0.95f)));
    float scan = 0.85f + 0.15f * cos(p.y * 90.0f - turn * 120.0f);
    float3 bars = (cyan * upper + magenta * lower) / max(upper + lower, 0.001f);
    float coverage = (upper + lower) * (0.25f + energy * 0.55f) * scan;
    return indicatorComposite(source, bars, coverage, bars, (upper + lower) * energy * 0.35f, p, opaque);
}

// A collapsed star in orbit around the icon. It lenses the artwork toward itself, tears a
// void where its event horizon passes, and lights a photon ring and accretion disk in the
// colours of whatever it is currently swallowing. Deflection falls off with the square of
// the distance, so the middle of the icon never moves and the application stays readable.
[[ stitchable ]] half4 deeDockSingularity(float2 position, SwiftUI::Layer layer, float size, float radius,
                                          float turn, float seed, float opaque, half4 accent, float accentStrength) {
    float2 p = indicatorPoint(position, size);
    float sweep = harmonic(seed, 1.0f, 2.0f, 5.0f) * mix(-1.0f, 1.0f, step(0.5f, hash11(seed, 2.0f)));
    float phase = hash11(seed, 3.0f) * 6.2831853f;
    float tilt = hash11(seed, 4.0f) * 3.1415927f;
    float angle = turn * sweep + phase;
    // An inclined orbit: circular in its own plane, foreshortened and rotated into ours.
    float2 orbit = float2(cos(angle) * 0.78f, sin(angle) * 0.50f);
    float2 hole = float2(orbit.x * cos(tilt) - orbit.y * sin(tilt),
                         orbit.x * sin(tilt) + orbit.y * cos(tilt));

    float2 toward = hole - p;
    float distance = length(toward);
    float horizon = 0.13f + hash11(seed, 5.0f) * 0.05f;
    float2 direction = distance > 0.0001f ? toward / distance : float2(0.0f, 0.0f);

    // Radial deflection plus a tangential frame-dragging term: the swirl is what separates
    // a black hole from a magnifying glass.
    float pull = min(0.28f, horizon * horizon * 1.9f / (distance * distance + 0.006f));
    float2 drag = float2(-direction.y, direction.x) * pull * 0.85f * sign(sweep);
    half4 lensed = layer.sample(position + (direction * pull + drag) * size * 0.5f);

    // Whatever the horizon has reached is already gone.
    float swallowed = smoothstep(horizon * 0.72f, horizon * 1.12f, distance);
    half4 source = lensed * half(swallowed);

    // The rings are lit by the light falling into them, which is the icon's own artwork.
    float3 infalling = lensed.a > 0.01h ? float3(lensed.rgb) / float(lensed.a) : float3(1.0f);
    float3 tint = iconTint(infalling, accent, accentStrength, float3(0.55f, 0.72f, 1.0f), 0.55f);

    float ring = exp(-pow((distance - horizon * 1.22f) / (horizon * 0.17f), 2.0f));
    float disk = exp(-pow((distance - horizon * 2.1f) / (horizon * 1.5f), 2.0f));
    float halo = exp(-pow(distance / (horizon * 4.5f), 2.0f)) * 0.22f;
    float armAngle = atan2(p.y - hole.y, p.x - hole.x);
    // Spiral arms wound into the hole, turning far faster than the orbit itself.
    float arms = 0.5f + 0.5f * sin(armAngle * 2.0f - distance / max(horizon, 0.01f) * 4.0f
                                   + turn * 120.0f * sign(sweep));
    // Relativistic beaming: the limb rotating toward the viewer is far brighter.
    float doppler = 0.35f + 0.65f * saturate(sin(armAngle - angle));

    float3 ringColor = mix(float3(1.0f, 0.99f, 0.94f), tint, 0.35f);
    float3 diskColor = mix(float3(0.16f, 0.07f, 0.48f), mix(float3(1.0f, 0.82f, 0.48f), tint, 0.40f),
                           doppler * arms);
    float3 glow = mix(diskColor, ringColor, saturate(ring * 1.4f));
    float coverage = saturate(ring * 1.15f + disk * arms * doppler * 0.85f + halo) * swallowed;
    // A hot inner edge where the artwork is being stretched into the hole.
    float stretched = exp(-pow((distance - horizon * 1.5f) / (horizon * 0.9f), 2.0f)) * 0.5f;
    return indicatorComposite(source, glow, coverage, ringColor, stretched, p, opaque);
}
