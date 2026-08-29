#!/usr/bin/env python3
"""Press keys on the board, so a hardware test can drive the game itself.

Screenshots prove what the core DRAWS; they cannot show that it reads the
controls. This makes a virtual keyboard on the MiSTer with /dev/uinput and
types into it, which is how Elevator Action Returns was taken from attract
through coin, start, character select and a stage on real hardware.

    python3 tools/rf_input.py --mra "/media/fat/_Arcade/Ray Force.mra" 5 1
    python3 tools/rf_input.py --shots 5 1 LCTRL RIGHT:6

THE ONE THING THAT MATTERS: MiSTer enumerates input devices when a core
loads and does NOT notice one plugged in afterwards. So the device has to
exist BEFORE the core is loaded -- hence --mra, which creates the keyboard,
loads the core, waits for the ROM download, and only then types. Without
that ordering every key is silently dropped, which looks exactly like a core
that ignores its inputs.

Keys are MiSTer's arcade defaults: 5/6 coin, 1/2 start, arrows for the
stick, LCTRL / LALT / SPACE for buttons 1-3, F12 for the OSD.

    --shots   screenshot after every key, fetched into screenshots/input/
    --mra P   load core P first (needed unless a run already did so)
    --wait N  seconds to wait after load_core (default 38)
"""
import argparse, os, posixpath, sys, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rf_deploy as d

BOARD = "/tmp/rf_input_run.py"

# The board-side half. It has to run there: /dev/uinput and /dev/MiSTer_cmd
# are the board's, and the device must stay open for the whole sequence.
RUNNER = r'''
import fcntl, glob, os, shutil, struct, sys, time
UI_SET_EVBIT, UI_SET_KEYBIT = 0x40045564, 0x40045565
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_KEY, EV_SYN = 0x01, 0x00
K = {"1":2,"2":3,"3":4,"4":5,"5":6,"6":7,"0":11,"ENTER":28,"ESC":1,
     "SPACE":57,"LCTRL":29,"LALT":56,"LSHIFT":42,"TAB":15,
     "UP":103,"DOWN":108,"LEFT":105,"RIGHT":106,"F12":88,
     "A":30,"B":48,"S":31,"W":17,"X":45,"Z":44}
mra, wait, shots = sys.argv[1], float(sys.argv[2]), sys.argv[3] == "1"
keys = sys.argv[4:]
OUT = "/tmp/rf_input_shots"
shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)

def emit(fd, t, c, v): os.write(fd, struct.pack("@llHHi", 0, 0, t, c, v))

def shot(fd_unused, n, label):
    src = glob.glob("/media/fat/screenshots/*/")
    for dirp in src:
        for f in glob.glob(dirp + "*.png"): os.remove(f)
    open("/dev/MiSTer_cmd", "w").write("screenshot\n"); time.sleep(3)
    for dirp in src:
        g = glob.glob(dirp + "*.png")
        if g: shutil.copy(g[0], "%s/%02d_%s.png" % (OUT, n, label)); return

fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
for c in set(K.values()): fcntl.ioctl(fd, UI_SET_KEYBIT, c)
os.write(fd, struct.pack("@80sHHHHi", b"rf-input", 3, 0x1234, 0x5678, 1, 0)
             + b"\x00" * (4 * 64 * 4))
fcntl.ioctl(fd, UI_DEV_CREATE)
print("keyboard up"); sys.stdout.flush()
time.sleep(2)
if mra != "-":
    open("/dev/MiSTer_cmd", "w").write("load_core %s\n" % mra)
    print("core loaded, waiting %gs" % wait); sys.stdout.flush()
    time.sleep(wait)
n = 0
if shots: shot(fd, n, "start"); n += 1
for tok in keys:
    name, _, rep = tok.partition(":")
    code = K.get(name.upper())
    if code is None:
        print("unknown key", name); continue
    for _ in range(int(rep) if rep else 1):
        emit(fd, EV_KEY, code, 1); emit(fd, EV_SYN, 0, 0); time.sleep(0.15)
        emit(fd, EV_KEY, code, 0); emit(fd, EV_SYN, 0, 0); time.sleep(0.35)
    print("pressed", tok); sys.stdout.flush()
    if shots: shot(fd, n, name.lower()); n += 1
print("done"); sys.stdout.flush()
time.sleep(1)
fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("keys", nargs="+", help="e.g. 5 1 LCTRL RIGHT:6")
    ap.add_argument("--mra", default="-", help="load this core first (see the note above)")
    ap.add_argument("--wait", type=float, default=38.0)
    ap.add_argument("--shots", action="store_true")
    a = ap.parse_args()

    c = d.connect()
    sftp = c.open_sftp()
    with sftp.open(BOARD, "w") as f:
        f.write(RUNNER)
    sftp.close()

    args = " ".join('"%s"' % x for x in [a.mra, a.wait, "1" if a.shots else "0"] + a.keys)
    d.run(c, "nohup python3 %s %s > /tmp/rf_input.log 2>&1 &" % (BOARD, args))
    print("running on the board...")

    deadline = time.time() + a.wait + 12 * len(a.keys) + 90
    while time.time() < deadline:
        time.sleep(6)
        log = d.run(c, "cat /tmp/rf_input.log 2>/dev/null")
        if "done" in log:
            print(log.strip())
            break
    else:
        sys.exit("timed out; /tmp/rf_input.log on the board has the detail")

    if a.shots:
        os.makedirs("screenshots/input", exist_ok=True)
        sftp = c.open_sftp()
        for f in sorted(sftp.listdir("/tmp/rf_input_shots")):
            sftp.get(posixpath.join("/tmp/rf_input_shots", f), "screenshots/input/" + f)
            print("  screenshots/input/" + f)
        sftp.close()
    c.close()


if __name__ == "__main__":
    main()
