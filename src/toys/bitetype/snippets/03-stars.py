#! name: starfield
#! lang: python
#! knob SPEED 0.01 0.12 0.01
#! knob COUNT 20 300 10
#! knob WARP 1 6 1
import random, time, shutil
SPEED, COUNT, WARP = 0.03, 90, 2
w, h = shutil.get_terminal_size()
star = [[random.random()*w, random.randint(0,h-1), random.random()*WARP+0.2] for _ in range(COUNT)]
for f in range(180):
    print("\033[2J", end="")
    for s in star:
        s[0] -= s[2]
        if s[0] < 0: s[0] = w - 1
        print(f"\033[{s[1]+1};{int(s[0])+1}H\033[97m{'.:*'[int(s[2])%3]}", end="")
    print(flush=True, end=""); time.sleep(SPEED)
