// BITE-OS: notification "pixel": the card assembles from chunky blocks that
// sharpen into focus (gap 1 = big sparse blocks, 0 = crisp).
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
void main() {
    vec2 uv = qt_TexCoord0;
    float g = clamp(gap, 0.0, 1.0);
    // block size steps down: 28px -> 1px
    float bs = max(1.0, floor(1.0 + g * g * 27.0));
    vec2 cell = floor(uv * itemSize / bs);
    vec2 cuv = (cell + 0.5) * bs / itemSize;
    vec4 col = g > 0.02 ? tap(cuv) : tap(uv);
    // blocks pop in randomly while large
    float present = step(clamp((g - 0.35) * 1.6, 0.0, 1.0), hash2(cell + 1.3));
    col *= present;
    // neon outline on fresh blocks
    vec2 inb = fract(uv * itemSize / bs);
    float border = (1.0 - step(0.08, inb.x) * step(inb.x, 0.92) * step(0.08, inb.y) * step(inb.y, 0.92)) * step(4.0, bs);
    col.rgb = mix(col.rgb, edgeColor.rgb * col.a, border * 0.5 * g);
    // glitch on impact
    if (amount > 0.01) {
        float ca = (2.0 + 9.0 * amount) * amount / max(itemSize.x, 1.0);
        col = vec4(tap(uv + vec2(ca, 0.0)).r, col.g, tap(uv - vec2(ca, 0.0)).b, col.a);
    }
    fragColor = col * qt_Opacity;
}
