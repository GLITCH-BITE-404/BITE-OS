# name: spinning donut
# about: the famous donut.c — a lit 3D torus spinning in ASCII
# level: extreme
import math, os, sys, time

w, h = os.get_terminal_size()
h -= 1
shades = ".,-~:;=!*#$@"
A = B = 0.0

print("\033[2J\033[?25l", end="")
try:
    for frame in range(900):
        out = [" "] * (w * h)
        zbuf = [0.0] * (w * h)
        sA, cA, sB, cB = math.sin(A), math.cos(A), math.sin(B), math.cos(B)
        for j in range(0, 628, 7):
            ct, st = math.cos(j / 100), math.sin(j / 100)
            ring = ct + 2
            for i in range(0, 628, 2):
                sp, cp = math.sin(i / 100), math.cos(i / 100)
                d = 1 / (sp * ring * sA + st * cA + 5)
                t = sp * ring * cA - st * sA
                x = int(w / 2 + w * 0.35 * d * (cp * ring * cB - t * sB))
                y = int(h / 2 + h * 0.65 * d * (cp * ring * sB + t * cB))
                lum = int(8 * ((st * sA - sp * ct * cA) * cB - sp * ct * sA - st * cA - cp * ct * sB))
                if 0 <= y < h and 0 <= x < w and d > zbuf[y * w + x]:
                    zbuf[y * w + x] = d
                    out[y * w + x] = shades[max(0, min(11, lum))]
        rows = ("".join(out[r * w:(r + 1) * w]) for r in range(h))
        sys.stdout.write("\033[H\033[96m" + "\n".join(rows))
        sys.stdout.flush()
        A += 0.07
        B += 0.03
        time.sleep(0.02)
finally:
    print("\033[0m\033[?25h")
