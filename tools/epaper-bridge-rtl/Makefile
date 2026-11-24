# SPDX-License-Identifier: Apache-2.0
RTL := rtl/epd_unpack.v rtl/epd_line_fifo.v rtl/epd_timing.v rtl/epd_bridge_core.v

.PHONY: sim lut clean

sim: build/tb.vvp build/meta.hex
	vvp -n build/tb.vvp +frames=build/frames.hex +meta=build/meta.hex \
		+nframes=$$(wc -l < build/meta.hex) | tee build/sim.log
	@grep -q '^RESULT: PASS' build/sim.log

build/tb.vvp: $(RTL) rtl/crc16_mcrf4xx.vh tb/tb_bridge.v | build
	iverilog -g2012 -Wall -Wno-timescale -I rtl -s tb_bridge -o $@ tb/tb_bridge.v $(RTL)

build/meta.hex: tb/gen_vectors.py | build
	python3 tb/gen_vectors.py build

# Generic LUT5 estimate; memories stay as $mem cells so their bits can be
# counted as 9 Kbit DRMs. The D-PHY/DSI stub is a blackbox.
YS := read_verilog -I rtl $(RTL) rtl/epd_bridge_top.v; \
	read_verilog -lib rtl/dphy_rx_stub.v; \
	synth -lut 5 -top epd_bridge_top -run begin:fine; \
	opt -fast -full; techmap; opt -fast; abc -lut 5; opt -fast; \
	tee -o build/stat.txt stat; tee -q -o build/mem.txt dump t:$$mem_v2

lut: | build
	yosys -q -l build/lut.log -p '$(YS)' >/dev/null
	@rm -f abc.history
	@cat build/stat.txt
	@awk '/parameter .SIZE /{s=$$3} /parameter .WIDTH /{w=$$3} \
		END {printf "line FIFO RAM: %d x %d = %d bits (%.2f x 9 Kbit DRM at 1K x 9)\n", s, w, s*w, s/1024}' build/mem.txt

build:
	mkdir -p build

clean:
	rm -rf build
