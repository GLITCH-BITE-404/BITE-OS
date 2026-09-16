# name: mandelbrot zoom
# about: diving into the Mandelbrot set in truecolor, two pixels per character
# level: extreme
import colorsys, os, sys

w, h = os.get_terminal_size()
w, rows = min(w, 120), min(h - 1, 30) * 2
cx, cy = -0.743643887, 0.131825904

def color(n, top):
    if n >= top:
        return (0, 0, 0)
    r, g, b = colorsys.hsv_to_rgb((n / 32) % 1, 0.85, 1)
    return (int(r * 255), int(g * 255), int(b * 255))

print("\033[2J\033[?25l", end="")
try:
    zoom = 1.0
    for frame in range(300):
        top = 40 + frame // 3
        span = 3 / zoom
        px = []
        for j in range(rows):
            y0 = cy + (j / rows - 0.5) * span
            line = []
            for i in range(w):
                x0 = cx + (i / w - 0.5) * span * w / rows
                x = y = 0.0
                n = 0
                while x * x + y * y < 4 and n < top:
                    x, y = x * x - y * y + x0, 2 * x * y + y0
                    n += 1
                line.append(color(n, top))
            px.append(line)
        out = []
        for j in range(0, rows - 1, 2):
            out.append("".join("\033[38;2;%d;%d;%dm\033[48;2;%d;%d;%dm▀" % (a + b)
                               for a, b in zip(px[j], px[j + 1])) + "\033[0m")
        sys.stdout.write("\033[H" + "\n".join(out))
        sys.stdout.flush()
        zoom *= 1.04
finally:
    print("\033[0m\033[?25h")
