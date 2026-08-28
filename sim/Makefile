# Verilator benches for the Ray Force video RTL.
#
#   make gfx    fetch tile rows through rf_gfx_bus and diff against f3_gfx.py
#   make line   decode line RAM through rf_video_line and diff against f3_render.py
#   make line-all  the same over every dumped frame
#   make eeprom   93C46 protocol: EWEN, WRITE, READ with the dummy bit, idle DO
#   make pf       a frame of playfield lines through rf_video_pf vs the model
#   make pf-mosaic  the same with mosaic forced on (Ray Force never uses it)
#   make pf-all   the playfield bench over every dumped frame
#   make mix      END TO END: decode + playfields + tile fetch + mixer vs MAME's frame
#   make mix-all  the same over every frame that has its two predecessors dumped
#   make pipe     rf_video_pipe under real raster timing vs the playfields-only model
#   make pipe-60  the same with the 257-line 60 Hz frame (Refresh Rate OSD option)
#   make pipe-lat frame 3000 (114 sprite-rows on a line) at a hardware-like
#                 channel turnaround. The bench's latency IS the per-burst
#                 occupancy of the shared sprite channel (rf_spr_ch_share
#                 holds one burst outstanding), so it stands for the real
#                 controller's turnaround: ~14 ram clocks idle (traced through
#                 rf_sdram's states), more with the playfield channels
#                 contending. 24 is the gate; 34 is printed for information
#                 (the 114-record line cannot fit 228 bursts x 34 whatever the
#                 queue depth). The sprmax:missed field is what the self-test
#                 page's SPRLINE : MISS row reports, which calibrates this.
#
# Needs the gfx region dumps in ../dump -- see "How to run the video oracle"
# in HANDOFF.md.
VERILATOR ?= verilator
VFLAGS = -DVERILATOR --cc --exe --build -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC
RTL = ../rtl

.PHONY: gfx spr-gfx line line-all eeprom pf pf-mosaic pf-all mix mix-all pipe pipe-60 pipe-lat spr spr-all spr-line spr-line-all clean

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

MIX_RTL = $(PF_RTL) $(RTL)/rf_video_mix.sv

mix: obj_dir/mixtb mix_ref.txt
	./obj_dir/mixtb ../dump 1800 mix_ref.txt mix_out.txt

mix-all: obj_dir/mixtb
	./run_mix_all.sh

mix_ref.txt: gen_mix_ref.py ../tools/f3_render.py
	python3 gen_mix_ref.py ../dump 1800 > $@

obj_dir/mixtb: mix_tb.cpp mix_top.sv $(MIX_RTL)
	$(VERILATOR) $(VFLAGS) --top-module mix_top mix_top.sv $(MIX_RTL) mix_tb.cpp -o mixtb

PIPE_RTL = $(MIX_RTL) $(RTL)/rf_video_pivot.sv $(RTL)/rf_video_spr_list.sv $(RTL)/rf_spr_gfx_bus.sv $(RTL)/rf_spr_ch_share.sv $(RTL)/rf_video_spr.sv $(RTL)/rf_video_pipe.sv

# ---- sprite list walker (stage a) ----
spr: obj_dir/sprtb spr_ref.txt
	./obj_dir/sprtb ../dump 1800 spr_ref.txt

spr-all: obj_dir/sprtb
	@for f in $$(ls ../dump/f3_*_spriteram.bin | sed 's/.*f3_0*\([0-9]*\)_spriteram.bin/\1/'); do \
	  s2=$$(printf '../dump/f3_%05d_spriteram.bin' $$((f-2))); [ -f $$s2 ] || continue; \
	  python3 gen_spr_ref.py ../dump $$f > spr_ref_$$f.txt; \
	  printf '%-8s ' "frame $$f:"; ./obj_dir/sprtb ../dump $$f spr_ref_$$f.txt | tail -1 || exit 1; \
	done

spr_ref.txt: gen_spr_ref.py ../tools/f3_render.py
	python3 gen_spr_ref.py ../dump 1800 > $@

obj_dir/sprtb: spr_tb.cpp $(RTL)/rf_video_spr_list.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_video_spr_list $(RTL)/rf_video_spr_list.sv spr_tb.cpp -o sprtb

# ---- sprite gfx fetch (stage b) ----
spr-gfx: obj_dir/sprgfxtb
	./obj_dir/sprgfxtb ../dump spr_fetched.txt
	python3 check_spr_gfx.py ../dump spr_fetched.txt

obj_dir/sprgfxtb: spr_gfx_tb.cpp $(RTL)/rf_spr_gfx_bus.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_spr_gfx_bus $(RTL)/rf_spr_gfx_bus.sv spr_gfx_tb.cpp -o sprgfxtb

# ---- per-line sprite builder (stage c) ----
SPR_RTL = $(RTL)/rf_video_spr_list.sv $(RTL)/rf_spr_gfx_bus.sv $(RTL)/rf_bram.sv $(RTL)/rf_video_spr.sv

spr-line: obj_dir/sprlinetb spr_fb_ref.txt
	./obj_dir/sprlinetb ../dump 1800 spr_fb_ref.txt

spr-line-all: obj_dir/sprlinetb
	@for f in $$(ls ../dump/f3_*_spriteram.bin | sed 's/.*f3_0*\([0-9]*\)_spriteram.bin/\1/'); do \
	  s2=$$(printf '../dump/f3_%05d_spriteram.bin' $$((f-2))); [ -f $$s2 ] || continue; \
	  python3 gen_spr_fb_ref.py ../dump $$f > spr_fb_ref_$$f.txt; \
	  printf '%-10s ' "frame $$f:"; ./obj_dir/sprlinetb ../dump $$f spr_fb_ref_$$f.txt | tail -1 || exit 1; \
	done

spr_fb_ref.txt: gen_spr_fb_ref.py ../tools/f3_render.py
	python3 gen_spr_fb_ref.py ../dump 1800 > $@

obj_dir/sprlinetb: spr_line_tb.cpp $(SPR_RTL)
	$(VERILATOR) $(VFLAGS) --top-module rf_video_spr $(SPR_RTL) spr_line_tb.cpp -o sprlinetb

pipe: obj_dir/pipetb pipe_ref.txt
	./obj_dir/pipetb ../dump 1800 pipe_ref.txt pipe_out.ppm

# every frame whose two predecessors were dumped (the sprite lag), each
# against its own reference
pipe-all: obj_dir/pipetb
	@for f in $$(ls ../dump/f3_*_frame.argb | sed 's/.*f3_0*\([0-9]*\)_frame.argb/\1/'); do \
	  p1=$$(printf '../dump/f3_%05d_frame.argb' $$((f-1))); p2=$$(printf '../dump/f3_%05d_frame.argb' $$((f-2))); \
	  [ -f $$p1 ] && [ -f $$p2 ] || continue; \
	  python3 gen_pipe_ref.py ../dump $$f > pipe_ref_$$f.txt; \
	  echo "== frame $$f"; ./obj_dir/pipetb ../dump $$f pipe_ref_$$f.txt pipe_out_$$f.ppm | tail -1 || exit 1; \
	done

pipe-60: obj_dir/pipetb pipe_ref.txt
	./obj_dir/pipetb ../dump 1800 pipe_ref.txt pipe_out.ppm 14 1

# ---- ES5505 sampler vs the Python model (Phase 3, stage 2) ----
#   the model's raw 8-channel output for the captured stream, and the ROM
#   bytes it read, are the reference; 45 s of writes at 29.76 kHz
es5505: obj_dir/es5505tb es5505_rom.bin $(ES5505_REF)
	./obj_dir/es5505tb $(ES5505_STREAM) es5505_rom.bin $(ES5505_REF) $(ES5505_N)

ES5505_N ?= 60000
# the write(+read) stream and the model's raw reference for it; en5 carries
# the driver's ES5505 READS (ESR lines), which the bench checks too
ES5505_STREAM ?= ../dump/en3/en_writes.txt
ES5505_REF ?= es5505_ref.raw

es5505-rw:
	$(MAKE) es5505 ES5505_STREAM=../dump/en5/en_writes.txt ES5505_REF=es5505_ref5.raw ES5505_N=$(ES5505_N)

es5505_ref5.raw: ../tools/es5505_model.py
	python3 ../tools/es5505_model.py ../dump/en5 --rom .. --seconds 45 --raw $@

es5505_rom.bin: ../tools/es5505_model.py
	python3 ../tools/es5505_model.py ../dump/en3 --rom .. --dump-rom $@

es5505_ref.raw: ../tools/es5505_model.py
	python3 ../tools/es5505_model.py ../dump/en3 --rom .. --seconds 45 --raw $@

obj_dir/es5505tb: es5505_tb.cpp $(RTL)/rf_es5505.sv
	$(VERILATOR) $(VFLAGS) --top-module rf_es5505 $(RTL)/rf_es5505.sv es5505_tb.cpp -o es5505tb

pipe-lat: obj_dir/pipetb
	python3 gen_pipe_ref.py ../dump 3000 > pipe_ref_3000.txt
	./obj_dir/pipetb ../dump 3000 pipe_ref_3000.txt pipe_out_3000_lat.ppm 24
	-./obj_dir/pipetb ../dump 3000 pipe_ref_3000.txt pipe_out_3000_lat34.ppm 34 | tail -2

pipe_ref.txt: gen_pipe_ref.py ../tools/f3_render.py
	python3 gen_pipe_ref.py ../dump 1800 > $@

obj_dir/pipetb: pipe_tb.cpp pipe_top.sv $(PIPE_RTL)
	$(VERILATOR) $(VFLAGS) --top-module pipe_top pipe_top.sv $(PIPE_RTL) pipe_tb.cpp -o pipetb

clean:
	rm -rf obj_dir fetched.txt spr_fetched.txt line_out.txt line_ref.txt pf_out*.txt pf_ref*.txt mix_out*.txt mix_ref*.txt pipe_out*.ppm pipe_ref*.txt spr_ref*.txt spr_fb_ref*.txt
