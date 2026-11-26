# SPDX-License-Identifier: Apache-2.0
CORE := rtl/epd_unpack.v rtl/epd_line_fifo.v rtl/epd_timing.v rtl/epd_dc_guard.v \
	rtl/epd_rails.v rtl/epd_bridge_core.v
CFG  := rtl/i2c_slave.v rtl/cfg_bridge.v rtl/por_sync.v
TOPS := rtl/epd_bridge_top.v rtl/epd_stage1_top.v
PANGO := rtl/pango/pgc_ccs_apb.v rtl/pango/pgc_osc.v
IV := iverilog -g2012 -Wall -Wno-timescale -I rtl

.PHONY: test sim i2c lut test-engine clean

test: sim i2c lut

sim: build/tb.vvp build/meta.hex
	vvp -n build/tb.vvp +frames=build/frames.hex +meta=build/meta.hex \
		+nframes=$$(wc -l < build/meta.hex) | tee build/sim.log
	@grep -q '^RESULT: PASS' build/sim.log

i2c: build/tb_i2c.vvp
	vvp -n build/tb_i2c.vvp +dm=0 | tee build/i2c0.log
	vvp -n build/tb_i2c.vvp +dm=1 | tee build/i2c1.log
	@grep -q '^RESULT: PASS' build/i2c0.log && grep -q '^RESULT: PASS' build/i2c1.log

build/tb.vvp: $(CORE) rtl/crc16_mcrf4xx.vh tb/tb_bridge.v | build
	$(IV) -s tb_bridge -o $@ tb/tb_bridge.v $(CORE)

build/tb_i2c.vvp: $(CFG) rtl/epd_stage1_top.v tb/tb_i2c.v tb/ccs_model.v tb/osc_model.v | build
	$(IV) -s tb_i2c -o $@ tb/tb_i2c.v tb/ccs_model.v tb/osc_model.v $(CFG) rtl/epd_stage1_top.v

build/meta.hex: tb/gen_vectors.py | build
	python3 tb/gen_vectors.py build

# Frames from the real engine: EPD_TOOL=path/to/epd-tool (cargo build -p marathon-epd).
test-engine: build/tb.vvp | build
	@test -n "$(EPD_TOOL)" || { echo "set EPD_TOOL=path/to/epd-tool"; exit 2; }
	rm -rf build/engine && $(EPD_TOOL) vectors build/engine
	python3 tb/engine_vectors.py build/engine build/engine
	vvp -n build/tb.vvp +frames=build/engine/frames.hex +meta=build/engine/meta.hex \
		+nframes=$$(wc -l < build/engine/meta.hex) | tee build/engine.log
	@grep -q '^RESULT: PASS' build/engine.log

# Generic LUT4 estimate (not Pango-mapped). The D-PHY stub and the Pango
# primitives are blackboxes; the line FIFO stays a $$mem cell, counted in DRMs.
YS = read_verilog -I rtl $(CORE) $(CFG) $(TOPS) $(PANGO); \
	read_verilog -lib rtl/dphy_rx_stub.v rtl/pango/gtp_blackbox.v; \
	hierarchy -top $(1); proc; tribuf -logic; synth -flatten -lut 4 -top $(1) -run begin:fine; \
	opt -fast -full; techmap; opt -fast; abc -lut 4; opt -fast; \
	tee -o build/stat-$(1).txt stat; tee -q -o build/mem-$(1).txt dump t:$$mem_v2

lut: | build
	yosys -q -l build/lut.log -p '$(call YS,epd_bridge_top)' >/dev/null
	yosys -q -l build/lut1.log -p '$(call YS,epd_stage1_top)' >/dev/null
	@rm -f abc.history
	@for t in epd_bridge_top epd_stage1_top; do \
		printf '%-16s ' $$t; \
		awk '$$2 == "$$lut" {l = $$1} $$2 ~ /DFF/ {f += $$1} END {printf "%d LUT4, %d FF", l, f}' \
			build/stat-$$t.txt; \
		awk '/parameter .SIZE /{s=$$3} /parameter .WIDTH /{w=$$3} \
			END {if (s) printf ", RAM %d x %d (%d bits)", s, w, s*w; print ""}' build/mem-$$t.txt; \
	done

build:
	mkdir -p build

clean:
	rm -rf build
