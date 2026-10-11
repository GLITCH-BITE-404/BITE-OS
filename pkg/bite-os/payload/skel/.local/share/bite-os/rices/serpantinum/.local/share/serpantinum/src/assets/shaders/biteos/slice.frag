// BITE-OS: notification "slice": the card arrives as horizontal strips sliding in
// from alternating sides (gap 1 = strips off to the sides, 0 = assembled).
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
    float strips = max(5.0, floor(itemSize.y / 12.0));
    float i = floor(uv.y * strips);
    float dir = mod(i, 2.0) < 1.0 ? -1.0 : 1.0;
    // later strips lag behind -> staggered arrival
    float lag = 0.55 + 0.45 * hash(i + 3.1);
    float g = clamp(gap * (0.7 + lag), 0.0, 1.0);
    vec2 src = uv - vec2(dir * g * g * 1.15, 0.0);
    vec4 col = rgbTap(src, clamp(amount + g * 0.6, 0.0, 1.0));
    // neon leading edge on moving strips
    float edgeX = dir < 0.0 ? src.x : 1.0 - src.x;
    float lead = g > 0.01 ? (1.0 - smoothstep(0.0, 0.02, abs(edgeX))) : 0.0;
    col.rgb = mix(col.rgb, edgeColor.rgb * col.a, lead * 0.8);
    fragColor = col * qt_Opacity;
}
