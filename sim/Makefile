# Verilator benches for the Ray Force video RTL.
#
#   make gfx    fetch tile rows through rf_gfx_bus and diff against f3_gfx.py
#   make line   decode line RAM through rf_video_line and diff against f3_render.py
#   make line-all  the same over every dumped frame
#   make eeprom   93C46 protocol: EWEN, WRITE, READ with the dummy bit, idle DO
#   make pf       a frame of playfield lines through rf_video_pf vs the model
#   make pf-mosaic  the same with mosaic forced on (Ray Force never uses it)
#   make pf-all   the playfield bench over every dumped frame
#
# Needs the gfx region dumps in ../dump -- see "How to run the video oracle"
# in HANDOFF.md.
VERILATOR ?= verilator
VFLAGS = -DVERILATOR --cc --exe --build -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
RTL = ../rtl

.PHONY: gfx line line-all eeprom pf pf-mosaic pf-all clean

gfx: obj_dir/gfxtb
	./obj_dir/gfxtb ../dump fetched.txt
	python3 check_gfx.py

obj_dir/gfxtb: gfx_tb.cpp $(RTL)/rf_gfx_bus.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_gfx_bus $(RTL)/rf_gfx_bus.sv gfx_tb.cpp -o gfxtb

line: obj_dir/linetb line_ref.txt
	./obj_dir/linetb ../dump/f3_01800_line_ram.bin 1 line_out.txt
	python3 check_line.py

line-all: obj_dir/linetb
	./run_line_all.sh

line_ref.txt: gen_line_ref.py ../tools/f3_render.py
	python3 gen_line_ref.py ../dump 1800 > $@

obj_dir/linetb: line_tb.cpp $(RTL)/rf_video_line.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_video_line $(RTL)/rf_video_line.sv line_tb.cpp -o linetb

eeprom: obj_dir/eetb
	./obj_dir/eetb

obj_dir/eetb: ee_tb.cpp $(RTL)/rf_eeprom_93c46.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_eeprom_93c46 $(RTL)/rf_eeprom_93c46.sv ee_tb.cpp -o eetb

PF_RTL = $(RTL)/rf_video_line.sv $(RTL)/rf_video_pf.sv $(RTL)/rf_gfx_bus.sv $(RTL)/rf_bram.sv

pf: obj_dir/pftb pf_ref.txt
	./obj_dir/pftb ../dump 1800 pf_out.txt
	python3 check_pf.py pf_ref.txt pf_out.txt

pf-mosaic: obj_dir/pftb
	python3 gen_pf_ref.py ../dump 1800 --mosaic 5 > pf_ref_m5.txt
	./obj_dir/pftb ../dump 1800 pf_out_m5.txt 5
	python3 check_pf.py pf_ref_m5.txt pf_out_m5.txt

pf-all: obj_dir/pftb
	./run_pf_all.sh

pf_ref.txt: gen_pf_ref.py ../tools/f3_render.py
	python3 gen_pf_ref.py ../dump 1800 > $@

obj_dir/pftb: pf_tb.cpp pf_top.sv $(PF_RTL)
	$(VERILATOR) $(VFLAGS) --top-module pf_top pf_top.sv $(PF_RTL) pf_tb.cpp -o pftb

clean:
	rm -rf obj_dir fetched.txt line_out.txt line_ref.txt pf_out*.txt pf_ref*.txt
