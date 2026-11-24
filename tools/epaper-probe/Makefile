CC = musl-gcc
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter -std=gnu11 -idirafter build/kinc
LDFLAGS = -static
PY = python3
T = build/test

all: epdprobe

build/kinc:
	mkdir -p $@
	for d in linux asm asm-generic drm; do ln -sfn /usr/include/$$d $@/$$d; done

epdprobe: epdprobe.c | build/kinc
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $< -lm -lpthread

# Full plan dry run, then synthetic round trips through the analyser: two injected
# K1/K2 behaviours on the short plan and one run of every experiment, all checked
# against the injected truth. Videos are deleted once analysed.
ROUNDS = synth:per-pixel:restart synth:global:queue cover:region:lost

test: epdprobe
	mkdir -p $(T)
	$(PY) epdplan.py --profile full --seed 1 --out $(T)/full
	./epdprobe --dry-run --log $(T)/full.tsv $(T)/full.plan 2>/dev/null
	for p in synth cover; do \
		$(PY) epdplan.py --profile $$p --seed 7 --out $(T)/$$p && \
		./epdprobe --dry-run --log $(T)/$$p.tsv --dump $(T)/$$p.dump $(T)/$$p.plan 2>/dev/null \
			|| exit 1; \
	done
	for b in $(ROUNDS); do \
		p=$${b%%:*}; k=$${b#*:}; n=$$p-$$(echo $$k | tr : -); \
		$(PY) synth_video.py --manifest $(T)/$$p.json --log $(T)/$$p.tsv --dump $(T)/$$p.dump \
			--behaviour $$k --out $(T)/$$n || exit 1; \
		s=; [ -f $(T)/$$n.static.mp4 ] && s="--video4k $(T)/$$n.static.mp4"; \
		$(PY) epdanalyze.py --manifest $(T)/$$p.json --log $(T)/$$n.tsv --video $(T)/$$n.mp4 $$s \
			--width 480 --out $(T)/$$n.out --truth $(T)/$$n.truth.json; r=$$?; \
		rm -f $(T)/$$n.mp4 $(T)/$$n.static.mp4; [ $$r = 0 ] || exit 1; \
	done

clean:
	rm -rf build epdprobe

.PHONY: all test clean
