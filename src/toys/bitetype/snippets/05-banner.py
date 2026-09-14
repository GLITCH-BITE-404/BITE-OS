#! name: figlet banner
#! lang: python
#! knob SPEED 0.02 0.20 0.01
#! knob HUE 17 213 4
#! knob SHIFT 1 12 1
import subprocess, time, sys
SPEED, HUE, SHIFT = 0.06, 45, 3
art = subprocess.run(["figlet", "-f", sys.argv[1] if len(sys.argv) > 1 else "standard",
                      "BITE OS"], capture_output=True, text=True).stdout.split("\n")
for f in range(120):
    print("\033[H", end="")
    for i, line in enumerate(art):
        print(f"\033[38;5;{HUE + (i*SHIFT + f) % 36}m{line}\033[K")
    print(flush=True, end=""); time.sleep(SPEED)
