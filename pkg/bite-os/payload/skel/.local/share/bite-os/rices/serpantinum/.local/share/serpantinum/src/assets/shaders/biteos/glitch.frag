#version 440
// BITE-OS: glitch burst for popups / notifications.
// amount 0..1 drives RGB split, slice tearing and scanlines; seed reshuffles slices.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float amount;
    float seed;
};

layout(binding = 1) uniform sampler2D source;

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

vec4 tap(vec2 uv) {
    float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return texture(source, clamp(uv, 0.0, 1.0)) * inside;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float a = clamp(amount, 0.0, 1.0);

    // slice tear: ~18 horizontal bands, a random third of them jump sideways
    float band = floor(uv.y * 18.0 + hash(seed) * 3.0);
    float pick = hash(band * 1.7 + floor(seed * 31.0));
    float shift = pick > 0.66 ? (hash(band * 3.3 + seed) - 0.5) * 0.12 * a : 0.0;
    uv.x += shift;

    // RGB split, in pixels so it looks the same on every popup size
    float ca = (2.0 + 10.0 * a) * a / max(itemSize.x, 1.0);
    vec4 r = tap(uv + vec2(ca, 0.0));
    vec4 g = tap(uv);
    vec4 b = tap(uv - vec2(ca, 0.0));
    vec4 col = vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));

    // scanlines
    float line = step(0.5, fract(qt_TexCoord0.y * itemSize.y / 3.0));
    col.rgb *= 1.0 - 0.18 * a * line;

    fragColor = col * qt_Opacity;
}
