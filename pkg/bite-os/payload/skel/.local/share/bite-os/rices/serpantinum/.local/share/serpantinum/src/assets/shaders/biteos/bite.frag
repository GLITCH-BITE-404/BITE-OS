#version 440
// BITE-OS: notification "bite". The card is cut along a zig-zag (teeth) line
// into an upper and a lower jaw. gap 0..1 pulls the jaws apart vertically;
// amount 0..1 adds the glitch (RGB split + slice tear) and a neon bite edge.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float gap;
    float amount;
    float seed;
    vec4 edgeColor;
};

layout(binding = 1) uniform sampler2D source;

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

// split line height (uv) at x: teeth ~22px wide, ~8px tall
float splitY(float x) {
    float teeth = max(4.0, floor(itemSize.x / 22.0));
    float tri = abs(fract(x * teeth) - 0.5) * 4.0 - 1.0;
    return 0.5 + tri * (4.0 / max(itemSize.y, 1.0));
}

vec4 tap(vec2 uv) {
    float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return texture(source, clamp(uv, 0.0, 1.0)) * inside;
}

vec4 glitchTap(vec2 uv, float a) {
    float band = floor(uv.y * 14.0 + hash(seed) * 3.0);
    float pick = hash(band * 1.7 + floor(seed * 31.0));
    uv.x += pick > 0.6 ? (hash(band * 3.3 + seed) - 0.5) * 0.14 * a : 0.0;
    float ca = (2.0 + 9.0 * a) * a / max(itemSize.x, 1.0);
    vec4 r = tap(uv + vec2(ca, 0.0));
    vec4 g = tap(uv);
    vec4 b = tap(uv - vec2(ca, 0.0));
    return vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
}

void main() {
    vec2 uv = qt_TexCoord0;
    float a = clamp(amount, 0.0, 1.0);
    float d = clamp(gap, 0.0, 1.0) * 0.6;

    vec2 top = uv + vec2(0.0, d);
    vec2 bot = uv - vec2(0.0, d);
    vec4 col = vec4(0.0);
    float edge = 1e9;
    if (top.y < splitY(top.x) && top.y >= 0.0) {
        col = glitchTap(top, a);
        edge = (splitY(top.x) - top.y) * itemSize.y;
    } else if (bot.y >= splitY(bot.x) && bot.y <= 1.0) {
        col = glitchTap(bot, a);
        edge = (bot.y - splitY(bot.x)) * itemSize.y;
    }

    // neon along the teeth while the bite glitches
    float glow = (1.0 - smoothstep(0.0, 2.5, edge)) * a * col.a;
    col.rgb = mix(col.rgb, edgeColor.rgb * col.a, glow * 0.9);

    fragColor = col * qt_Opacity;
}
