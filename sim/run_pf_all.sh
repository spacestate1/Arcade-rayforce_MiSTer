#!/bin/sh
# Playfield bench over every dumped frame. Different scenes use different
# zoom, rowscroll and tilemap rows, so the sweep is the coverage, not the
# single frame. Needs obj_dir/pftb (make -C sim pf).
set -e
cd "$(dirname "$0")"
ok=0; tot=0; sum=0
for lr in ../dump/f3_*_pf_ram.bin; do
    f=$(basename "$lr" | sed 's/f3_0*\([0-9]*\)_pf_ram.bin/\1/')
    python3 gen_pf_ref.py ../dump "$f" > /tmp/rf_pf_ref.txt
    ./obj_dir/pftb ../dump "$f" /tmp/rf_pf_out.txt > /tmp/rf_pf_time.txt
    # check_pf.py's exit status is the verdict: the compared-pixel count
    # varies per frame (rows nothing uses are not compared), so matching the
    # summary text against a fixed number wrongly failed clean frames
    tot=$((tot + 1))
    if r=$(python3 check_pf.py /tmp/rf_pf_ref.txt /tmp/rf_pf_out.txt | tail -1); then
        ok=$((ok + 1)); px=$(echo "$r" | sed 's/.*; \([0-9]*\)\/[0-9]* compared.*/\1/'); sum=$((sum + px))
    else
        printf "frame %5s: %s\n" "$f" "$r"
    fi
done
echo "$ok/$tot frames fully match ($sum compared pixels identical); last: $(cat /tmp/rf_pf_time.txt)"
[ "$ok" = "$tot" ]
