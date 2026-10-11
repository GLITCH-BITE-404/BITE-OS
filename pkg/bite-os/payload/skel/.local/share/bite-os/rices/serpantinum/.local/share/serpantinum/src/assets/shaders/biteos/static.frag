// BITE-OS: notification "static": TV static in the card's shape that tunes into
// the card (gap 1 = pure static, 0 = clear), with rolling bars.
#version 440
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
float hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
vec4 tap(vec2 uv) {
    float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
    return texture(source, clamp(uv, 0.0, 1.0)) * inside;
}
vec4 rgbTap(vec2 uv, float a) {
    float ca = (2.0 + 9.0 * a) * a / max(itemSize.x, 1.0);
    vec4 r = tap(uv + vec2(ca, 0.0)); vec4 g = tap(uv); vec4 b = tap(uv - vec2(ca, 0.0));
    return vec4(r.r, g.g, b.b, max(g.a, max(r.a, b.a)));
}
void main() {
    vec2 uv = qt_TexCoord0;
    float g = clamp(gap, 0.0, 1.0);
    // vertical-hold wobble while tuning
    uv.x += (hash(floor(uv.y * 40.0) + floor(seed * 13.0)) - 0.5) * 0.04 * g;
    vec4 card = rgbTap(uv, clamp(amount + g * 0.5, 0.0, 1.0));
    vec2 cell = floor(uv * itemSize / 2.0);
    float n = hash2(cell + vec2(floor(seed * 97.0), floor(seed * 31.0)));
    float roll = 0.75 + 0.25 * sin((uv.y + seed * 0.3) * 18.0);
    vec3 noiseCol = vec3(n * roll);
    float a = tap(uv).a;
    vec3 rgb = mix(card.rgb, noiseCol * a, g);
    fragColor = vec4(rgb, max(card.a, a)) * qt_Opacity;
}
