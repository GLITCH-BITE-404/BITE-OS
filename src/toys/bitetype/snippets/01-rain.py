#! name: matrix rain
#! lang: python
#! knob SPEED 0.01 0.20 0.01
#! knob COLOR 31 96 1
#! knob COLS 1 4 1
import random, time, shutil
SPEED, COLOR, COLS = 0.04, 92, 1
w, h = shutil.get_terminal_size()
drop = [random.randint(0, h) for _ in range(w)]
for frame in range(140):
    for x in range(0, w, COLS):
        drop[x] = (drop[x] + 1) % h
        print(f"\033[{drop[x]+1};{x+1}H\033[{COLOR}m{chr(random.randint(33,126))}", end="")
    print(flush=True, end=""); time.sleep(SPEED)
