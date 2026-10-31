# Q25 modem userspace: the open CCCI daemons and q25-speech, static on musl.
# q25-modem's APKBUILD builds these (build-base, linux-headers).
CC ?= cc
CFLAGS ?= -O2 -g
CFLAGS += -std=gnu11 -Wall -Wextra -Werror -Wno-unused-parameter \
	  -Icompat -Icommon -fstack-protector-strong -D_FORTIFY_SOURCE=2
LDFLAGS += -static -pthread
COMPAT := compat/q25_compat.c common/nvram_shim_musl.c

all: out/ccci_mdinit out/ccci_fsd out/ccci_rpcd out/q25-speech

out/ccci_mdinit: mdinit/ccci_mdinit.c $(COMPAT)
	@mkdir -p out
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
out/ccci_fsd: fsd/ccci_fsd.c $(COMPAT)
	@mkdir -p out
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
out/ccci_rpcd: rpcd/ccci_rpcd.c common/ccci_rpc_route.c $(COMPAT)
	@mkdir -p out
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS)
out/q25-speech: speech/q25_speech.c
	@mkdir -p out
	$(CC) $(CFLAGS) -o $@ $^ $(LDFLAGS) -lm
clean:
	rm -rf out
