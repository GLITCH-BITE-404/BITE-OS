# name: matrix rain
# about: green code falling down your terminal
# level: easy
import os, random, sys, time

w, h = os.get_terminal_size()
drops = [random.randint(-h, 0) for _ in range(w)]

print("\033[2J\033[?25l", end="")
try:
    for frame in range(800):
        out = []
        for x in range(0, w, 2):
            y = drops[x]
            if 0 <= y < h:
                out.append(f"\033[{y + 1};{x + 1}H\033[97m{chr(random.randint(33, 126))}")
            if 1 <= y <= h:
                out.append(f"\033[{y};{x + 1}H\033[32m{chr(random.randint(33, 126))}")
            if 0 <= y - 12 < h:
                out.append(f"\033[{y - 11};{x + 1}H ")
            drops[x] = y + 1 if y < h + 12 else random.randint(-h, 0)
        sys.stdout.write("".join(out))
        sys.stdout.flush()
        time.sleep(0.04)
finally:
    print("\033[0m\033[2J\033[H\033[?25h")
