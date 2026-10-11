#version 440
// BITE-OS: the popup "blast" in ONE pass: RGB-split outline blasting outward,
// glitch slivers flying off both sides, corner brackets slamming in.
// Cheap on integrated GPUs: the quad only has big margins left/right, pixels
// inside the popup exit at once, and slivers live in horizontal lanes so a
// pixel tests exactly ONE sliver (O(1)) instead of looping over all of them.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    vec4 frame;      // popup rect inside this quad (px)
    float progress;  // 0 -> 1
    float power;
    float jitter;    // -1..1
    float radius;
    float seed;      // new per burst
    float count;     // slivers per side
    float scale;
    vec4 colRed;
    vec4 colCyan;
    vec4 colMauve;
};

float hash(float n) { return fract(sin(n * 127.1 + 311.7) * 43758.5453); }

float sdRound(vec2 p, vec2 c, vec2 hs, float r) {
    vec2 q = abs(p - c) - (hs - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// premultiplied "over"
vec4 over(vec4 dst, vec3 c, float a) { return vec4(c * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a)); }

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    float p = clamp(progress, 0.0, 1.0);
    vec2 fmin = frame.xy, fmax = frame.xy + frame.zw;

    float arm = 26.0 * scale;
    // ── early exit: inside the popup, away from its corners → nothing to draw
    if (px.x > fmin.x + arm && px.x < fmax.x - arm && px.y > fmin.y + arm && px.y < fmax.y - arm) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 col = vec4(0.0);

    // ── slivers: O(1) — this pixel's lane holds at most one sliver ──
    bool left = px.x < fmin.x, right = px.x > fmax.x;
    if ((left || right) && px.y >= fmin.y && px.y <= fmax.y) {
        float side = left ? 0.0 : 1.0;
        float laneH = frame.w / count;
        float lane = floor((px.y - fmin.y) / laneH);
        float id = lane * 2.0 + side + seed * 13.0;
        float delay = hash(id * 3.1) * 0.3;
        float t = clamp((p - delay) / (1.0 - delay), 0.0, 1.0);
        float h = (2.0 + hash(id * 7.9) * 4.0) * scale;
        float y = fmin.y + lane * laneH + hash(id * 1.7) * max(0.0, laneH - h);
        if (t > 0.0 && px.y >= y && px.y <= y + h && hash(id * 4.4) > 0.25) {
            float len = (30.0 + hash(id * 5.3) * 150.0) * scale * (1.0 - 0.5 * t);
            float travel = (50.0 + hash(id * 9.7) * 170.0) * scale * power * t;
            float x0 = left ? fmin.x - len - travel : fmax.x + travel;
            if (px.x >= x0 && px.x <= x0 + len) {
                float m = mod(lane + side, 3.0);
                vec3 cc = m < 1.0 ? colRed.rgb : (m < 2.0 ? colCyan.rgb : colMauve.rgb);
                col = over(col, cc, 0.9 * (1.0 - t));
            }
        }
    }

    // ── RGB-split outline (only near the frame edge) ──
    float grow = 22.0 * scale * power * p;
    float bw = max(1.0, 2.0 * scale);
    vec2 c = (fmin + fmax) * 0.5, hs = frame.zw * 0.5;
    float d0 = sdRound(px, c, hs + vec2(grow), radius + grow);
    if (abs(d0) < 12.0 * scale * power + bw) {
        float fade = 1.0 - p;
        for (int k = -1; k <= 1; k++) {
            float fk = float(k);
            vec2 off = vec2(fk * 5.0 * scale * power * jitter, fk * 2.0 * scale * jitter);
            float d = abs(sdRound(px, c + off, hs + vec2(grow), radius + grow)) - bw * 0.5;
            float a = (1.0 - smoothstep(-0.5, 0.5, d)) * fade * (k == 0 ? 0.5 : 0.85);
            vec3 cc = k < 0 ? colRed.rgb : (k > 0 ? colCyan.rgb : vec3(1.0));
            col = over(col, cc, a);
        }
    }

    // ── corner brackets (only in the four corner boxes) ──
    float slam = max(0.0, 1.0 - p * 3.0);
    float off2 = 36.0 * scale * power * slam;
    float th = 3.0 * scale, inset = -6.0 * scale;
    float bfade = p < 0.6 ? 1.0 : (1.0 - p) / 0.4;
    bool r = px.x > c.x, b = px.y > c.y;
    vec2 o = vec2(r ? fmax.x - arm - inset + off2 : fmin.x + inset - off2,
                  b ? fmax.y - arm - inset + off2 : fmin.y + inset - off2);
    vec2 q = px - o;
    if (q.x >= 0.0 && q.x <= arm && q.y >= 0.0 && q.y <= arm) {
        bool hBar = b ? q.y >= arm - th : q.y <= th;
        bool vBar = r ? q.x >= arm - th : q.x <= th;
        if (hBar || vBar) col = over(col, colCyan.rgb, bfade);
    }

    fragColor = col * qt_Opacity;
}
