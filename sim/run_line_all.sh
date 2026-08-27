#!/bin/sh
# Run the line-RAM decoder bench over every dumped frame.
#
# One frame proves only the decode paths that frame happens to exercise;
# different scenes latch different sections, so the sweep is what actually
# covers the module. Needs obj_dir/linetb built (make -C sim line).
set -e
cd "$(dirname "$0")"
ok=0; tot=0
for lr in ../dump/f3_*_line_ram.bin; do
    f=$(basename "$lr" | sed 's/f3_0*\([0-9]*\)_line_ram.bin/\1/')
    python3 gen_line_ref.py ../dump "$f" > /tmp/rf_line_ref.txt
    ext=$(head -1 /tmp/rf_line_ref.txt | awk '{print $3}')
    ./obj_dir/linetb "$lr" "$ext" /tmp/rf_line_out.txt > /dev/null
    r=$(python3 check_line.py /tmp/rf_line_ref.txt /tmp/rf_line_out.txt | head -1)
    tot=$((tot + 1))
    case "$r" in 256/256*) ok=$((ok + 1)) ;; *) printf "frame %5s: %s\n" "$f" "$r" ;; esac
done
echo "$ok/$tot frames fully match ($((ok * 256)) lines)"
[ "$ok" = "$tot" ]
