#!/usr/bin/env python3
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# mpvpaper-autopause — SIGSTOP mpvpaper while any window is fullscreen,
# SIGCONT when fullscreen exits. Reads Hyprland's IPC event socket
# directly via Python so we don't need socat/ncat installed.
import os, signal, socket, subprocess, sys, time

sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
if not sig:
    sys.stderr.write("[mpvpaper-autopause] no HYPRLAND_INSTANCE_SIGNATURE\n"); sys.exit(1)
sock_path = f"{os.environ['XDG_RUNTIME_DIR']}/hypr/{sig}/.socket2.sock"

stopped = False
def pause():
    global stopped
    if stopped: return
    subprocess.run(["pkill", "-STOP", "-x", "mpvpaper"], check=False)
    stopped = True
def resume():
    global stopped
    if not stopped: return
    subprocess.run(["pkill", "-CONT", "-x", "mpvpaper"], check=False)
    stopped = False

def cleanup(*_):
    resume(); sys.exit(0)
signal.signal(signal.SIGINT,  cleanup)
signal.signal(signal.SIGTERM, cleanup)
signal.signal(signal.SIGHUP,  cleanup)

# Retry the connect: at exec-once time the socket may not exist yet. Without
# this the daemon died on the first connect() and silently never ran — which
# is exactly why the ~9% fullscreen savings were never active.
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
for attempt in range(60):
    try:
        s.connect(sock_path); break
    except OSError:
        time.sleep(0.5)
else:
    sys.stderr.write(f"[mpvpaper-autopause] could not connect to {sock_path}\n"); sys.exit(1)

buf = b""
while True:
    chunk = s.recv(4096)
    if not chunk: break
    buf += chunk
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        try:    text = line.decode("utf-8", "replace")
        except: continue
        if   text == "fullscreen>>1": pause()
        elif text == "fullscreen>>0": resume()
