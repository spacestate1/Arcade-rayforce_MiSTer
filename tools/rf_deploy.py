#!/usr/bin/env python3
"""Deploy the built core to the MiSTer and load it.

    .venv/bin/python3 tools/rf_deploy.py            # upload + load + screenshot
    .venv/bin/python3 tools/rf_deploy.py --no-load  # upload only

Plain ssh key auth does not work on this board -- use paramiko with the
password, which is what this does. The MRA's <rbf>Rayforce</rbf> matches any
cores/Rayforce*.rbf, and MiSTer takes the last one by name, so the uploaded
file is named with a timestamp and sorts newest-last.
"""
import argparse
import datetime
import os
import sys
import time

import paramiko

HOST = "172.17.1.164"
USER = "root"
PASSWORD = "1"
MRA = "/media/fat/_Arcade/Ray Force.mra"
RBF = "output_files/Rayforce.rbf"


def connect():
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, username=USER, password=PASSWORD, timeout=15)
    return c


def run(c, cmd, timeout=40):
    _, out, err = c.exec_command(cmd, timeout=timeout)
    return out.read().decode(errors="ignore") + err.read().decode(errors="ignore")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-load", action="store_true")
    ap.add_argument("--no-shot", action="store_true")
    ap.add_argument("--wait", type=int, default=25, help="seconds to wait after load_core")
    ap.add_argument("--rbf", default=RBF, help="bitstream to upload (build.sh wipes "
                    "output_files/, so a build kept aside needs this)")
    ap.add_argument("--mra", action="store_true", help="also upload releases/Ray Force.mra")
    args = ap.parse_args()
    rbf = args.rbf

    if not os.path.exists(rbf):
        sys.exit(f"{rbf} not found -- run ./build.sh first")

    c = connect()
    name = "Rayforce_%s.rbf" % datetime.datetime.now().strftime("%Y%m%d_%H%M")
    sftp = c.open_sftp()
    sftp.put(rbf, f"/media/fat/_Arcade/cores/{name}")
    if args.mra:
        sftp.put("releases/Ray Force.mra", MRA)
        print("uploaded MRA")
    sftp.close()
    print("uploaded", name)

    if not args.no_load:
        print(run(c, f'echo "load_core {MRA}" > /dev/MiSTer_cmd && echo sent').strip())
        # The ROM download runs during this wait; the self-test page shows
        # BUSY until it finishes.
        time.sleep(args.wait)
        print(f"waited {args.wait}s for the core to load and download the ROM")

    if not args.no_shot:
        run(c, "rm -f /media/fat/screenshots/rayforce/*.png")
        run(c, 'echo "screenshot" > /dev/MiSTer_cmd')
        time.sleep(4)
        sftp = c.open_sftp()
        d = "/media/fat/screenshots/rayforce"
        os.makedirs("screenshots", exist_ok=True)
        for f in sftp.listdir(d):
            if f.endswith(".png"):
                sftp.get(f"{d}/{f}", f"screenshots/{f}")
                print("screenshot -> screenshots/" + f)
        sftp.close()

    c.close()


if __name__ == "__main__":
    main()
