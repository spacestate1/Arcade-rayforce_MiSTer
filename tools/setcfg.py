# Set the core's saved OSD status byte 0 on the board, e.g. 0x38 = Self Test
# Off + UART Debug = Sound Ring; 0x08 = Self Test Off + UART = Self Test page.
import sys
sys.path.insert(0, 'tools')
import rf_deploy as d
val = int(sys.argv[1], 16)
c = d.connect()
sftp = c.open_sftp()
path = "/media/fat/config/Rayforce.CFG"
try:
    cur = bytearray(sftp.open(path, "rb").read())
except IOError:
    cur = bytearray(16)
if len(cur) < 1: cur = bytearray(16)
cur[0] = val & 0xff
sftp.open(path, "wb").write(bytes(cur))
sftp.close(); c.close()
print(f"Rayforce.CFG[0] = {val:02x}")
