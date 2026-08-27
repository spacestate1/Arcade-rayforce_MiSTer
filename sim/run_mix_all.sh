#!/bin/sh
# End-to-end mixer bench over every frame whose two predecessors were dumped
# (sprite_lag 2: the sprites on screen came from sprite RAM two frames ago).
set -e
cd "$(dirname "$0")"
ok=0; tot=0; sum=0
for lr in ../dump/f3_*_line_ram.bin; do
    f=$(basename "$lr" | sed 's/f3_0*\([0-9]*\)_line_ram.bin/\1/')
    p1=$(printf "../dump/f3_%05d_spriteram.bin" $((f - 1)))
    p2=$(printf "../dump/f3_%05d_spriteram.bin" $((f - 2)))
    [ -f "$p1" ] && [ -f "$p2" ] || continue
    python3 gen_mix_ref.py ../dump "$f" > /tmp/rf_mix_ref.txt
    tot=$((tot + 1))
    if r=$(./obj_dir/mixtb ../dump "$f" /tmp/rf_mix_ref.txt /tmp/rf_mix_out.txt | tail -1); then
        ok=$((ok + 1)); px=$(echo "$r" | sed 's/^\([0-9]*\)\/.*/\1/'); sum=$((sum + px))
    else
        printf "frame %5s: %s\n" "$f" "$r"
    fi
done
echo "$ok/$tot frames identical to MAME ($sum visible pixels)"
[ "$ok" = "$tot" ]
