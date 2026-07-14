#version 300 es
// BITE-OS Glitch Mode — Hyprland screen shader (GLES 3.00).
// Effects: tear bands, VHS block displacement, chromatic aberration with hue
// pulse, RGB ghosting, scanlines, dedsec green tint, signal-loss bar,
// occasional pixelation tear, vignette, flicker drop, invert flash, datamosh.

precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
uniform float time;
out vec4 fragColor;

float hash11(float n) { return fract(sin(n * 12.9898) * 43758.5453); }
float hash21(vec2 p)  { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 hueShift(vec3 c, float a) {
    const vec3 k = vec3(0.57735, 0.57735, 0.57735);
    float ca = cos(a), sa = sin(a);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

void main() {
    vec2 uv = v_texcoord;

    // ---- horizontal tear bands ----
    float band = floor(uv.y * 80.0);
    float t = floor(time * 18.0);
    float trig = step(0.965, hash11(band + t * 7.13));
    float shift = (hash11(band * 2.7 + t) - 0.5) * 0.07 * trig;
    uv.x += shift;

    // ---- VHS-style block displacement ----
    float bigBand = floor(uv.y * 14.0);
    float bigT = floor(time * 4.0);
    float bigTrig = step(0.93, hash11(bigBand * 3.1 + bigT * 11.7));
    float bigShift = (hash11(bigBand + bigT * 2.3) - 0.5) * 0.18 * bigTrig;
    uv.x += bigShift;

    // ---- pixelation glitch tear (rare wide band that crushes resolution) ----
    float pxBand = floor(uv.y * 8.0);
    float pxT = floor(time * 3.0);
    float pxTrig = step(0.96, hash11(pxBand * 5.7 + pxT * 4.3));
    vec2 uvPx = uv;
    if (pxTrig > 0.5) {
        float blocks = mix(40.0, 120.0, hash11(pxT));
        uvPx = floor(uv * blocks) / blocks;
    }
    uv = mix(uv, uvPx, pxTrig);

    // ---- subtle CRT wobble ----
    uv.x += sin(uv.y * 70.0 + time * 3.0) * 0.0015;

    // ---- chromatic aberration (with rare strong pulse) ----
    float caBoost = step(0.985, hash11(floor(time * 6.0)));
    float ca = 0.0035 + 0.0025 * sin(time * 2.7) + caBoost * 0.012;
    float r = texture(tex, uv + vec2(ca, 0.0)).r;
    float g = texture(tex, uv).g;
    float b = texture(tex, uv - vec2(ca, 0.0)).b;
    vec3 col = vec3(r, g, b);

    // ---- RGB ghost trail ----
    vec3 ghost = texture(tex, uv + vec2(0.012 * sin(time * 1.3), 0.004)).rgb;
    col = mix(col, max(col, ghost * 0.55), 0.35);

    // ---- datamosh smear (blend with shifted neighborhood) ----
    float moshTrig = step(0.97, hash11(floor(time * 5.0) + 3.0));
    if (moshTrig > 0.5) {
        vec3 smear = texture(tex, uv + vec2(0.04, 0.0)).rgb;
        col = mix(col, smear, 0.35);
    }

    // ---- scanlines ----
    float scan = 0.86 + 0.14 * sin(uv.y * 900.0);
    col *= scan;

    // ---- hue rotation pulse ----
    float huePulse = step(0.985, hash11(floor(time * 8.0) + 1.0));
    col = mix(col, hueShift(col, 1.5), huePulse * 0.7);

    // ---- dedsec green tint ----
    col.r *= 0.92;
    col.g *= 1.08;
    col.b *= 0.95;

    // ---- noise grain ----
    float grain = (hash11(uv.x * 1024.0 + uv.y * 768.0 + time) - 0.5) * 0.08;
    col += grain;

    // ---- signal-loss bar ----
    float barY = fract(time * 0.18);
    float barDist = abs(uv.y - barY);
    float bar = smoothstep(0.06, 0.0, barDist);
    col = mix(col, col * vec3(0.2, 1.6, 0.4) + 0.05, bar * 0.55);

    // ---- vignette ----
    vec2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc, vc) * 0.7;
    col *= clamp(vig, 0.0, 1.0);

    // ---- flicker drop ----
    float flick = step(0.985, hash11(floor(time * 28.0)));
    col *= mix(1.0, 0.45, flick);

    // ---- rare invert flash ----
    float inv = step(0.997, hash11(floor(time * 24.0) + 0.5));
    col = mix(col, vec3(1.0) - col, inv);

    fragColor = vec4(col, 1.0);
}
