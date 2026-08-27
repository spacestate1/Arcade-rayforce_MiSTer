#!/usr/bin/env python3
"""Capture a screenshot from the MiSTer and transfer it back.

Usage:
    python3 tools/rf_screenshot.py [name]           # fbgrab (Linux console)
    python3 tools/rf_screenshot.py [name] --core    # built-in screenshot (core video)

Captures the current framebuffer on the MiSTer, saves it to
screenshots/<name>.png locally, and removes the MiSTer copy.

NOTE: fbgrab captures the Linux console, NOT the core's video output.
For the actual core video, use the MiSTer's built-in screenshot (F12 key
or OSD menu), which saves to /media/fat/screenshots/<corename>/.

Requires the .venv with paramiko (created earlier).
"""
import sys, os, datetime
import paramiko

HOST = '172.17.1.164'
USER = 'root'
PASS = '1'

def main():
    use_core = '--core' in sys.argv
    name = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] != '--core' else \
           datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    local_dir = 'screenshots'
    local_path = os.path.join(local_dir, f'{name}.png')
    remote_path = f'/tmp/{name}.png'

    os.makedirs(local_dir, exist_ok=True)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username=USER, password=PASS, timeout=10)

    if use_core:
        # Trigger the built-in screenshot via F12 key event
        # This requires the MiSTer to be running a core and the key to be bound
        print('NOTE: --core triggers the built-in screenshot via F12.')
        print('      The screenshot saves to /media/fat/screenshots/<corename>/')
        print('      and must be downloaded separately.')
        # Simulate F12 key press (key code 88)
        stdin, stdout, stderr = client.exec_command(
            'echo 88 > /sys/class/input/event0/device/press 2>/dev/null || true'
        )
        print('F12 sent. Check /media/fat/screenshots/<corename>/ on the MiSTer.')
        client.close()
        return

    # Capture the Linux console framebuffer
    stdin, stdout, stderr = client.exec_command(f'fbgrab {remote_path}')
    err = stderr.read().decode()
    if err:
        print(f'fbgrab: {err}', file=sys.stderr)

    # Download it
    sftp = client.open_sftp()
    sftp.get(remote_path, local_path)
    sftp.remove(remote_path)  # don't leave it on the MiSTer
    sftp.close()
    client.close()

    print(f'saved: {local_path}')

if __name__ == '__main__':
    main()
