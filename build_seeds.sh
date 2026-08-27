#!/bin/sh
# Quick seed sweep — try a few seeds to close timing
set -e
cd "$(dirname "$0")"

export QUARTUS_ROOTDIR=/storage01/tools/intelFPGA_lite/17.0/quartus
export PATH="$QUARTUS_ROOTDIR/bin:$PATH"

SEEDS="3 8 11 13"
BEST_SEED=""
BEST_SLACK="-999"

for SEED in $SEEDS; do
    echo "=== Seed $SEED ==="
    sed -i "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED $SEED/" Rayforce.qsf

    rm -rf db incremental_db output_files
    systemd-run --user --scope --quiet \
        -p MemoryHigh=11G -p MemoryMax=11G -p CPUWeight=100 \
        nice -n 5 quartus_sh --flow compile Rayforce > /tmp/rf_seed_$SEED.log 2>&1

    if [ -f output_files/Rayforce.sta.rpt ]; then
        SLACK=$(grep "Worst-case setup slack" output_files/Rayforce.sta.rpt | awk '{print $5}')
        echo "Seed $SEED: slack = $SLACK"
        if [ -n "$SLACK" ] && [ "$(echo "$SLACK > $BEST_SLACK" | bc -l)" = "1" ]; then
            BEST_SLACK=$SLACK
            BEST_SEED=$SEED
        fi
    else
        echo "Seed $SEED: FAILED (no sta.rpt)"
    fi
done

echo ""
echo "Best seed: $BEST_SEED (slack = $BEST_SLACK)"
sed -i "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED $BEST_SEED/" Rayforce.qsf
echo "QSF updated to seed $BEST_SEED"
