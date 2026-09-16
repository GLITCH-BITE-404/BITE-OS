# name: plasma
# about: a truecolor lava lamp made of sine waves
# level: hard
import math, os, sys, time

w, h = os.get_terminal_size()
w, h = min(w, 160), min(h - 1, 50)

print("\033[2J\033[?25l", end="")
try:
    t = 0.0
    while t < 40:
        rows = []
        for y in range(h):
            row = []
            for x in range(w):
                v = math.sin(x * 0.08 + t) + math.sin(y * 0.15 - t) + math.sin((x + y) * 0.05 + t * 1.3)
                r = int(127 + 127 * math.sin(v * math.pi))
                g = int(127 + 127 * math.sin(v * math.pi + 2))
                b = int(127 + 127 * math.sin(v * math.pi + 4))
                row.append(f"\033[48;2;{r};{g};{b}m ")
            rows.append("".join(row) + "\033[0m")
        sys.stdout.write("\033[H" + "\n".join(rows))
        sys.stdout.flush()
        t += 0.1
        time.sleep(0.02)
finally:
    print("\033[0m\033[?25h")
