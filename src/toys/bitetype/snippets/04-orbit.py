#! name: orbit
#! lang: python
#! knob SPEED 0.01 0.12 0.01
#! knob BODIES 2 14 1
#! knob SPREAD 1 8 1
import math, time, shutil
SPEED, BODIES, SPREAD = 0.035, 7, 3
w, h = shutil.get_terminal_size()
for f in range(190):
    print("\033[2J", end="")
    for i in range(BODIES):
        a = f / 12 + i * 0.9
        x = int(w/2 + math.cos(a) * (6 + i * SPREAD) * 2)
        y = int(h/2 + math.sin(a) * (3 + i * SPREAD / 2))
        print(f"\033[{y+1};{x+1}H\033[38;5;{200+i}m0", end="")
    print(flush=True, end=""); time.sleep(SPEED)
