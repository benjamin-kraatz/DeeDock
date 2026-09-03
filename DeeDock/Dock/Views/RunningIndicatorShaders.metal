#include <metal_stdlib>
using namespace metal;

// Positions arrive in SwiftUI logical points. Normalize each icon to [-1, 1] without
// consulting display pixels, so the artwork survives magnification and backing-scale changes.
static float2 indicatorPoint(float2 position, float size) {
    return position / max(size, 1.0f) * 2.0f - 1.0f;
}

static float roundedBoxDistance(float2 p, float extent, float radius) {
    float2 q = abs(p) - (extent - radius);
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - radius;
}

static float3 spectrum(float phase) {
    return 0.55f + 0.45f * cos(6.2831853f * (phase + float3(0.0f, 0.33f, 0.67f)));
}

// Every style fades before the rectangle's boundary. The icon center is masked by each
// caller. Reduce Transparency uses solid colored bands instead of translucent light.
// SwiftUI color filters require premultiplied output; never leave RGB in transparent pixels.
static half4 indicatorColor(float3 rgb, float coverage, float2 p, half sourceAlpha, float opaque) {
    float alpha = opaque > 0.5f ? smoothstep(0.15f, 0.3f, coverage) : saturate(coverage);
    alpha *= 1.0f - smoothstep(0.94f, 1.0f, max(abs(p.x), abs(p.y)));
    half a = half(alpha) * sourceAlpha;
    return half4(half3(saturate(rgb)) * a, a);
}

// Two interfering waves make an electric filament and its wider violet corona.
[[ stitchable ]] half4 deeDockPlasma(float2 position, half4 color, float size, float opaque) {
    float2 p = indicatorPoint(position, size);
    float angle = atan2(p.y, p.x);
    float wave = sin(angle * 7.0f + 0.8f) * 0.022f
               + sin(angle * 19.0f - 1.3f) * 0.012f;
    float distance = abs(roundedBoxDistance(p, 0.82f, 0.25f) + wave);
    float filament = 1.0f - smoothstep(0.015f, 0.05f, distance);
    float corona = (1.0f - smoothstep(0.025f, 0.14f, distance)) * 0.55f;
    float3 rgb = mix(float3(0.42f, 0.08f, 1.0f), float3(0.1f, 0.95f, 1.0f),
                     0.5f + 0.5f * sin(angle * 3.0f));
    rgb = mix(rgb, float3(0.85f, 1.0f, 1.0f), filament * 0.65f);
    return indicatorColor(rgb, filament + corona, p, color.a, opaque);
}

// A broad diffraction rim with fine scan lines and a diagonal white reflection.
[[ stitchable ]] half4 deeDockHologram(float2 position, half4 color, float size, float opaque) {
    float2 p = indicatorPoint(position, size);
    float distance = abs(roundedBoxDistance(p, 0.80f, 0.18f));
    float rim = 1.0f - smoothstep(0.04f, 0.115f, distance);
    float scan = 0.72f + 0.28f * cos(p.y * 70.0f);
    float reflection = 1.0f - smoothstep(0.0f, 0.16f, abs(p.x + p.y - 0.3f));
    float3 rgb = mix(spectrum(p.x * 0.65f + p.y * 0.3f), float3(0.88f, 1.0f, 1.0f),
                     reflection * 0.85f);
    return indicatorColor(rgb * scan, rim * 0.94f, p, color.a, opaque);
}

// A hot circular core with an irregular, finely rayed outer edge. No particle system.
[[ stitchable ]] half4 deeDockSolarFlare(float2 position, half4 color, float size, float opaque) {
    float2 p = indicatorPoint(position, size);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float rays = pow(0.5f + 0.5f * sin(angle * 23.0f + sin(angle * 7.0f)), 3.0f);
    float outer = 0.84f + rays * 0.13f;
    float corona = smoothstep(0.66f, 0.73f, radius) * (1.0f - smoothstep(0.77f, outer, radius));
    float core = 1.0f - smoothstep(0.014f, 0.045f, abs(radius - 0.735f));
    float heat = saturate((radius - 0.72f) / 0.22f);
    float3 rgb = mix(float3(1.0f, 0.92f, 0.35f), float3(1.0f, 0.12f, 0.025f), heat);
    rgb = mix(rgb, float3(1.0f, 1.0f, 0.8f), core * 0.7f);
    return indicatorColor(rgb, corona + core, p, color.a, opaque);
}

// An octagonal bevel with discrete spectral facets and narrow highlight seams.
[[ stitchable ]] half4 deeDockPrism(float2 position, half4 color, float size, float opaque) {
    float2 p = indicatorPoint(position, size);
    float2 q = abs(p);
    float octagon = max(max(q.x, q.y), (q.x + q.y) * 0.7071068f);
    float bevel = smoothstep(0.70f, 0.735f, octagon) * (1.0f - smoothstep(0.86f, 0.89f, octagon));
    float angle = atan2(p.y, p.x);
    float facet = floor((angle + 3.1415927f) / 0.7853982f);
    float3 rgb = spectrum(facet / 8.0f + 0.08f);
    float highlight = 1.0f - smoothstep(0.008f, 0.023f, abs(octagon - 0.85f));
    float innerShade = mix(0.5f, 1.0f, saturate((octagon - 0.73f) / 0.13f));
    rgb = mix(rgb * innerShade, float3(1.0f), highlight * 0.75f);
    return indicatorColor(rgb, bevel, p, color.a, opaque);
}
