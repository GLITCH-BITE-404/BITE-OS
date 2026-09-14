#! name: sine wave
#! lang: python
#! knob SPEED 0.01 0.15 0.01
#! knob FREQ 2 20 1
#! knob HUE 17 213 4
import math, time, shutil
SPEED, FREQ, HUE = 0.03, 6, 45
w, h = shutil.get_terminal_size()
for f in range(170):
    print("\033[2J", end="")
    for x in range(w):
        y = int(h / 2 + math.sin(x / FREQ + f / 5) * (h / 3))
        print(f"\033[{y+1};{x+1}H\033[38;5;{HUE+x%6}m*", end="")
    print(flush=True, end=""); time.sleep(SPEED)
