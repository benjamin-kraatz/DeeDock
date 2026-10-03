#include <metal_stdlib>
using namespace metal;

// Experiment for the Ice Blocks style: paints one block with the captured backdrop, bent near
// the rim the way a thick slab of clear glass bends what is behind it.

static float dockIceRoundedRect(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// position: block-local points. origin: the block's top-left in the captured strip, in points.
// scale: backdrop pixels per point. bevel: width of the refracting rim. strength: how far, in
// points, the rim displaces the backdrop along the edge normal (negative bends inward).
[[ stitchable ]] half4 dockIceRefraction(float2 position, half4 color, float2 size, float radius,
                                         float2 origin, float scale, float bevel, float strength,
                                         float dispersion, texture2d<half> backdrop) {
    float2 halfSize = size * 0.5;
    float2 p = position - halfSize;
    float distance = dockIceRoundedRect(p, halfSize, radius);
    if (distance > 0.0) { return half4(0.0); }

    float e = 0.5;
    float2 gradient = float2(
        dockIceRoundedRect(p + float2(e, 0.0), halfSize, radius) - dockIceRoundedRect(p - float2(e, 0.0), halfSize, radius),
        dockIceRoundedRect(p + float2(0.0, e), halfSize, radius) - dockIceRoundedRect(p - float2(0.0, e), halfSize, radius));
    float2 normal = gradient / max(length(gradient), 0.0001);

    // Quadratic falloff: flat through the middle of the block, steep at the rim.
    float rim = saturate(1.0 + distance / max(bevel, 0.001));
    float bend = rim * rim * strength;

    constexpr sampler linear(address::clamp_to_edge, filter::linear);
    float2 texture = float2(backdrop.get_width(), backdrop.get_height());
    float2 base = (origin + position) * scale;
    // Each channel bends by a slightly different amount, which fringes the rim like real ice.
    half r = backdrop.sample(linear, (base + normal * bend * (1.0 + dispersion) * scale) / texture).r;
    half g = backdrop.sample(linear, (base + normal * bend * scale) / texture).g;
    half b = backdrop.sample(linear, (base + normal * bend * (1.0 - dispersion) * scale) / texture).b;
    return half4(r, g, b, 1.0);
}
