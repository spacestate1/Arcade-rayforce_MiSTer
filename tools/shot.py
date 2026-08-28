import sys, time, os
sys.path.insert(0, 'tools')
import rf_deploy as d
tag = sys.argv[1]
c = d.connect()
d.run(c, "rm -f /media/fat/screenshots/rayforce/*.png")
d.run(c, 'echo "screenshot" > /dev/MiSTer_cmd')
time.sleep(4)
sftp = c.open_sftp()
for f in sftp.listdir("/media/fat/screenshots/rayforce"):
    if f.endswith(".png"):
        sftp.get(f"/media/fat/screenshots/rayforce/{f}", f"screenshots/{tag}_{f}")
        print("screenshot -> screenshots/" + f"{tag}_{f}")
sftp.close(); c.close()
