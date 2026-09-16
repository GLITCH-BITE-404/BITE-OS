# name: game of life
# about: Conway's cells living and dying in your terminal
# level: medium
import os, random, sys, time

w, h = os.get_terminal_size()
h -= 1
cells = {(x, y) for x in range(w) for y in range(h) if random.random() < 0.25}

print("\033[2J\033[?25l", end="")
try:
    for gen in range(500):
        counts = {}
        for (x, y) in cells:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    if dx or dy:
                        k = ((x + dx) % w, (y + dy) % h)
                        counts[k] = counts.get(k, 0) + 1
        cells = {k for k, n in counts.items() if n == 3 or (n == 2 and k in cells)}
        grid = [[" "] * w for _ in range(h)]
        for (x, y) in cells:
            grid[y][x] = "█"
        sys.stdout.write("\033[H\033[92m" + "\n".join("".join(r) for r in grid))
        sys.stdout.flush()
        time.sleep(0.06)
finally:
    print("\033[0m\033[?25h")
