# name: doom fire
# about: the fire from PlayStation Doom, burning in your terminal
# level: medium
import os, random, sys, time

w, h = os.get_terminal_size()
h -= 1
heat = [[0] * w for _ in range(h)]
ramp = [16, 52, 88, 124, 160, 196, 202, 208, 214, 220, 226, 227, 229, 230, 231]
top = len(ramp) - 1

print("\033[2J\033[?25l", end="")
try:
    for frame in range(600):
        heat[h - 1] = [top] * w
        for y in range(h - 1):
            below = heat[y + 1]
            for x in range(w):
                src = below[min(w - 1, max(0, x + random.randint(-1, 1)))]
                heat[y][x] = max(0, src - random.randint(0, 1))
        rows = ["".join(f"\033[48;5;{ramp[v]}m " for v in row) for row in heat]
        sys.stdout.write("\033[H" + "\033[0m\n".join(rows) + "\033[0m")
        sys.stdout.flush()
        time.sleep(0.03)
finally:
    print("\033[0m\033[?25h")
