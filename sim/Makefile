# Verilator benches for the Ray Force video RTL.
#
#   make gfx    fetch tile rows through rf_gfx_bus and diff against f3_gfx.py
#
# Needs the gfx region dumps in ../dump -- see "How to run the video oracle"
# in HANDOFF.md.
VERILATOR ?= verilator
VFLAGS = -DVERILATOR --cc --exe --build -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
RTL = ../rtl

.PHONY: gfx clean

gfx: obj_dir/gfxtb
	./obj_dir/gfxtb ../dump fetched.txt
	python3 check_gfx.py

obj_dir/gfxtb: gfx_tb.cpp $(RTL)/rf_gfx_bus.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_gfx_bus $(RTL)/rf_gfx_bus.sv gfx_tb.cpp -o gfxtb

clean:
	rm -rf obj_dir fetched.txt
