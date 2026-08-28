#!/bin/sh
# Sound ring test: put the board in Sound Ring mode, load the given rbf,
# capture the UART for 15 s, compare with MAME's stream.
set -e
cd /storage01/code/c_things/raiden-mister/Arcade-rayforce_MiSTer
S=.
RBF=$1
.venv/bin/python3 tools/setcfg.py 38
timeout 180 .venv/bin/python3 tools/rf_deploy.py --rbf $RBF --no-shot | tail -1
sleep 10
timeout 60 .venv/bin/python3 tools/rf_uart.py -t 15 -o snd_ring.log | tail -1
python3 tools/rf_snd_ring_check.py snd_ring.log dump/en3/en_writes.txt
echo "--- first ring lines:"; grep -m5 "^W \|^===" snd_ring.log
