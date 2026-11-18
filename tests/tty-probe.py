# Runs inside the test terminal: puts the tty in raw mode and records every
# byte the terminal receives for N seconds, so the test can see exactly what
# was typed, including any Enter (\r or \n).
import os, sys, termios, time, tty, select
out, secs = sys.argv[1], float(sys.argv[2])
fd = sys.stdin.fileno()
old = termios.tcgetattr(fd)
tty.setraw(fd)
buf = b""
try:
    end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            buf += os.read(fd, 4096)
finally:
    termios.tcsetattr(fd, termios.TCSADRAIN, old)
open(out, "wb").write(buf)
