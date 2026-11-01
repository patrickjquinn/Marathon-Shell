// SPDX-License-Identifier: GPL-2.0
/*
 * q25-speech: minimal MD1 speech control over /dev/ccci_aud.
 *
 * Wire format decoded from the stock HAL (SpeechMessengerNormal::
 * speechMessageToCcciMessage / ccciMessageToSpeechMessage); message ids and
 * sph_info_t from MediaTek's open SpeechMessageID.h / SpeechType.h.
 *
 *   q25-speech on <8|16|32> [loopback] [seconds]
 *   q25-speech listen [seconds]
 *   q25-speech selftest [8|16|32]
 */
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#include <sound/asound.h>

#define CCCI_AUD		"/dev/ccci_aud"
#define CCCI_PCM_TX		5
#define MAILBOX_MAGIC		0xFFFFFFFFu
#define AP_PAYLOAD_SYNC		0xA2A2
#define CCCI_MAX_BUF		3456

#define MSG_A2M_SPH_ON		0x2F20
#define MSG_A2M_SPH_OFF		0x2F21
#define MSG_M2A_ACK		0x8000
#define DATA_TYPE_SPH_INFO	25

enum { APP_NORMAL = 0, APP_LOOPBACK = 2 };

struct sph_info {			/* sph_info_t, 128 bytes */
	uint8_t  application;
	uint8_t  bt_info;
	uint8_t  sample_rate_enum;	/* 0 8k, 1 16k, 2 32k, 3 48k */
	uint8_t  opendsp_flag;
	uint8_t  sph_param_path;	/* 0 via payload */
	uint8_t  sph_param_valid;	/* 0 invalid: modem defaults */
	uint16_t sph_param_length;
	uint16_t sph_param_index;
	uint16_t ext_dev_info;
	uint8_t  loopback_flag;
	uint8_t  loopback_delay;
	uint16_t echo_ref_delay_ms;
	uint8_t  mic_delay_ms;
	uint8_t  mute_info;
	uint16_t enh_dynamic_ctrl;
	uint32_t sph_param_usip_length;
	uint32_t sph_param_usip_index;
	uint16_t drv_common_param[12];
	uint16_t drv_debug_info[16];
	uint8_t  num_smart_pa;
	uint8_t  reserved[43];
};
_Static_assert(sizeof(struct sph_info) == 128, "sph_info_t is 128 bytes");

/* Modem notifications the stock HAL acknowledges with (id & 0x7fff). */
static const uint16_t auto_ack[] = { 0xAFA0 /* MD alive */, 0xAF78 /* EPOF */,
				     0xAF75 /* network status */, 0xAF90 /* NW codec */,
				     0xAF70 /* EM data request */ };

static int fd = -1;
static volatile sig_atomic_t stop;

static void on_signal(int sig) { (void)sig; stop = 1; }

static long now_ms(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000;
}

static int send_mailbox(uint16_t id, uint16_t p16, uint32_t p32)
{
	uint32_t h[4] = { MAILBOX_MAGIC, ((uint32_t)id << 16) | p16, CCCI_PCM_TX, p32 };

	return write(fd, h, sizeof(h)) == sizeof(h) ? 0 : -1;
}

static int send_payload(uint16_t id, uint16_t type, const void *data, uint16_t size)
{
	uint8_t buf[CCCI_MAX_BUF];
	uint32_t len = (uint32_t)size + 6;
	uint32_t h[4] = { 0, len, CCCI_PCM_TX, ((uint32_t)id << 16) | len };
	uint16_t ph[3] = { AP_PAYLOAD_SYNC, type, size };

	if (16 + len > sizeof(buf))
		return -1;
	memcpy(buf, h, 16);
	memcpy(buf + 16, ph, 6);
	memcpy(buf + 22, data, size);
	return write(fd, buf, 16 + len) == (ssize_t)(16 + len) ? 0 : -1;
}

/* Returns the received msg id, 0 on timeout or signal, -1 on error. */
static int recv_msg(int timeout_ms)
{
	uint8_t buf[CCCI_MAX_BUF];
	struct pollfd p = { .fd = fd, .events = POLLIN };
	uint32_t h[4];
	uint16_t id;
	ssize_t n;
	unsigned int i;

	n = poll(&p, 1, timeout_ms);
	if (n <= 0)
		return n < 0 && errno != EINTR ? -1 : 0;
	n = read(fd, buf, sizeof(buf));
	if (n < 16)
		return n < 0 && errno != EINTR ? -1 : 0;
	memcpy(h, buf, 16);
	if (h[0] == MAILBOX_MAGIC) {
		id = h[1] >> 16;
		printf("rx mailbox id=0x%04x p16=0x%04x p32=0x%08x\n", id, h[1] & 0xffff, h[3]);
	} else {
		uint16_t ph[3] = { 0, 0, 0 };

		id = h[3] >> 16;
		if (n >= 22)
			memcpy(ph, buf + 16, 6);
		printf("rx payload id=0x%04x sync=0x%04x type=%u size=%u (%zd bytes)\n",
		       id, ph[0], ph[1], ph[2], n);
	}
	for (i = 0; i < sizeof(auto_ack) / sizeof(auto_ack[0]); i++) {
		if (id == auto_ack[i]) {
			send_mailbox(id & 0x7fff, 0, 0);
			printf("tx ack 0x%04x\n", id & 0x7fff);
		}
	}
	return id;
}

static int wait_ack(uint16_t want, int timeout_ms)
{
	long end = now_ms() + timeout_ms;
	int id;

	while (now_ms() < end) {
		id = recv_msg((int)(end - now_ms()));
		if (id < 0)
			return -1;
		if (id == want)
			return 0;
	}
	return -1;
}

/* Service modem messages until a signal, the deadline, or *done. */
static void hold(int seconds, volatile int *done)
{
	long end = seconds > 0 ? now_ms() + seconds * 1000L : 0;

	while (!stop && !(done && *done) && (!end || now_ms() < end))
		if (recv_msg(200) < 0)
			break;
}

static int speech_on(int app, int rate)
{
	struct sph_info info;
	long end = now_ms() + 1000;

	memset(&info, 0, sizeof(info));
	info.application = app;
	info.sample_rate_enum = rate == 8 ? 0 : rate == 32 ? 2 : 1;
	/* Ack anything queued (MD alive, EM requests), bounded. */
	while (!stop && now_ms() < end && recv_msg(100) > 0)
		;
	printf("tx SPH_ON app=%d rate=%dk\n", app, rate);
	if (send_payload(MSG_A2M_SPH_ON, DATA_TYPE_SPH_INFO, &info, sizeof(info)) ||
	    wait_ack(MSG_M2A_ACK | MSG_A2M_SPH_ON, 3000)) {
		fprintf(stderr, "SPH_ON: no ack\n");
		return -1;
	}
	printf("SPH_ON acked\n");
	return 0;
}

static int speech_off(void)
{
	printf("tx SPH_OFF\n");
	if (send_mailbox(MSG_A2M_SPH_OFF, 0, 0) ||
	    wait_ack(MSG_M2A_ACK | MSG_A2M_SPH_OFF, 1500)) {
		fprintf(stderr, "SPH_OFF: no ack\n");
		return -1;
	}
	printf("SPH_OFF acked\n");
	return 0;
}

/* ------------------------------------------------------------------ */
/* Self-test: tone -> Playback_2 (DL2) -> PCM_2 PB -> modem loopback -> */
/* PCM_2 CAP -> UL2 -> Capture_2, Hostless_Speech held for the clock.   */
/* ------------------------------------------------------------------ */

#define CARD		0
#define DEV_PLAY2	3
#define DEV_CAP2	4
#define DEV_HOSTLESS	5
#define CH		2
#define PERIOD_MS	20
#define TEST_SEC	4
#define TONE_A		700.0
#define TONE_B		1100.0

static const char *const routes[] = {
	"PCM_2_PB_CH1 DL2_CH1", "PCM_2_PB_CH2 DL2_CH2",		/* PLAYBACK2_TO_MD1 */
	"UL2_CH1 PCM_2_CAP_CH1", "UL2_CH2 PCM_2_CAP_CH1",	/* MD1_TO_CAPTURE2 */
	/* Hostless Speech DL reaches the PCM 2 BE only through one of its
	 * interconnects (mt6789-dai-hostless.c); this one feeds the earpiece,
	 * not the modem's uplink. */
	"ADDA_DL_CH1 PCM_2_CAP_CH1", "ADDA_DL_CH2 PCM_2_CAP_CH1",
};

static int ctl_set(const char *name, long v)
{
	struct snd_ctl_elem_value ev;
	char path[32];
	int c, ret;

	snprintf(path, sizeof(path), "/dev/snd/controlC%d", CARD);
	c = open(path, O_RDWR);
	if (c < 0)
		return -1;
	memset(&ev, 0, sizeof(ev));
	ev.id.iface = SNDRV_CTL_ELEM_IFACE_MIXER;
	snprintf((char *)ev.id.name, sizeof(ev.id.name), "%s", name);
	ev.value.integer.value[0] = v;
	ev.value.integer.value[1] = v;
	ret = ioctl(c, SNDRV_CTL_IOCTL_ELEM_WRITE, &ev);
	if (ret < 0)
		fprintf(stderr, "mixer '%s'=%ld: %s\n", name, v, strerror(errno));
	close(c);
	return ret < 0 ? -1 : 0;
}

static void hw_mask(struct snd_pcm_hw_params *p, int n, unsigned int bit)
{
	struct snd_mask *m = &p->masks[n - SNDRV_PCM_HW_PARAM_FIRST_MASK];

	memset(m->bits, 0, sizeof(m->bits));
	m->bits[bit >> 5] |= 1u << (bit & 31);
}

static void hw_int(struct snd_pcm_hw_params *p, int n, unsigned int v)
{
	struct snd_interval *i = &p->intervals[n - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL];

	i->min = i->max = v;
	i->integer = 1;
}

static int pcm_open(int dev, int capture, unsigned int rate)
{
	struct snd_pcm_hw_params p;
	char path[40];
	unsigned int n;
	int f;

	snprintf(path, sizeof(path), "/dev/snd/pcmC%dD%d%c", CARD, dev, capture ? 'c' : 'p');
	f = open(path, O_RDWR);
	if (f < 0) {
		fprintf(stderr, "%s: %s\n", path, strerror(errno));
		return -1;
	}
	memset(&p, 0, sizeof(p));
	for (n = SNDRV_PCM_HW_PARAM_FIRST_MASK; n <= SNDRV_PCM_HW_PARAM_LAST_MASK; n++)
		memset(p.masks[n - SNDRV_PCM_HW_PARAM_FIRST_MASK].bits, 0xff,
		       sizeof(p.masks[0].bits));
	for (n = SNDRV_PCM_HW_PARAM_FIRST_INTERVAL; n <= SNDRV_PCM_HW_PARAM_LAST_INTERVAL; n++)
		p.intervals[n - SNDRV_PCM_HW_PARAM_FIRST_INTERVAL].max = ~0u;
	p.rmask = ~0u;
	p.info = ~0u;
	hw_mask(&p, SNDRV_PCM_HW_PARAM_ACCESS, SNDRV_PCM_ACCESS_RW_INTERLEAVED);
	hw_mask(&p, SNDRV_PCM_HW_PARAM_FORMAT, SNDRV_PCM_FORMAT_S16_LE);
	hw_mask(&p, SNDRV_PCM_HW_PARAM_SUBFORMAT, SNDRV_PCM_SUBFORMAT_STD);
	hw_int(&p, SNDRV_PCM_HW_PARAM_CHANNELS, CH);
	hw_int(&p, SNDRV_PCM_HW_PARAM_RATE, rate);
	hw_int(&p, SNDRV_PCM_HW_PARAM_PERIOD_SIZE, rate * PERIOD_MS / 1000);
	hw_int(&p, SNDRV_PCM_HW_PARAM_PERIODS, 4);
	if (ioctl(f, SNDRV_PCM_IOCTL_HW_PARAMS, &p) < 0 ||
	    ioctl(f, SNDRV_PCM_IOCTL_PREPARE) < 0) {
		fprintf(stderr, "%s hw_params/prepare: %s\n", path, strerror(errno));
		close(f);
		return -1;
	}
	return f;
}

/* start_threshold as given; never stop on xrun (stop_threshold = boundary). */
static int pcm_sw(int f, unsigned long buffer, unsigned long start)
{
	struct snd_pcm_sw_params sw;
	unsigned long boundary = buffer;

	while (boundary * 2 <= (unsigned long)(~0ul >> 1) - buffer)
		boundary *= 2;
	memset(&sw, 0, sizeof(sw));
	sw.tstamp_mode = SNDRV_PCM_TSTAMP_NONE;
	sw.period_step = 1;
	sw.avail_min = 1;
	sw.start_threshold = start;
	sw.stop_threshold = boundary;
	sw.boundary = boundary;
	return ioctl(f, SNDRV_PCM_IOCTL_SW_PARAMS, &sw);
}

static int pcm_write_silence(int f, unsigned int frames)
{
	int16_t *buf = calloc((size_t)frames * CH, sizeof(*buf));
	struct snd_xferi x = { .buf = buf, .frames = frames };
	int ret;

	if (!buf)
		return -1;
	ret = ioctl(f, SNDRV_PCM_IOCTL_WRITEI_FRAMES, &x);
	free(buf);
	return ret;
}

struct play_ctx {
	int fd;
	unsigned int rate;
	volatile int done;
};

static void *play_thread(void *arg)
{
	struct play_ctx *c = arg;
	unsigned int frames = c->rate * PERIOD_MS / 1000, i, k = 0;
	unsigned int total = c->rate * TEST_SEC;
	int16_t *buf = calloc(frames * CH, sizeof(*buf));
	struct snd_xferi x;

	while (buf && k < total && !stop) {
		for (i = 0; i < frames; i++, k++) {
			/* Alternate two tones every 200 ms so speech enhancement
			 * does not treat it as stationary noise. */
			double hz = (k / (c->rate / 5)) % 2 ? TONE_B : TONE_A;
			int16_t s = (int16_t)(8192.0 * sin(2.0 * M_PI * hz * k / c->rate));

			buf[i * CH] = buf[i * CH + 1] = s;
		}
		x = (struct snd_xferi){ .buf = buf, .frames = frames };
		if (ioctl(c->fd, SNDRV_PCM_IOCTL_WRITEI_FRAMES, &x) < 0 && errno == EPIPE)
			ioctl(c->fd, SNDRV_PCM_IOCTL_PREPARE);
	}
	free(buf);
	c->done = 1;
	return NULL;
}

/* Goertzel power of channel 0 at hz, relative to full scale (dBFS). */
static double tone_dbfs(const int16_t *s, unsigned int n, unsigned int rate, double hz)
{
	double w = 2.0 * M_PI * hz / rate, c = 2.0 * cos(w), q0, q1 = 0, q2 = 0, pw;
	unsigned int i;

	for (i = 0; i < n; i++) {
		q0 = c * q1 - q2 + s[i * CH] / 32768.0;
		q2 = q1;
		q1 = q0;
	}
	pw = q1 * q1 + q2 * q2 - c * q1 * q2;
	/* A full-scale sine gives pw = (n/2)^2. The tone is on half the time. */
	return 10.0 * log10(pw / ((n / 2.0) * (n / 2.0)) + 1e-12);
}

static double rms_dbfs(const int16_t *s, unsigned int n)
{
	double acc = 0;
	unsigned int i;

	for (i = 0; i < n; i++)
		acc += (s[i * CH] / 32768.0) * (s[i * CH] / 32768.0);
	return 10.0 * log10(acc / (n ? n : 1) + 1e-12);
}

/* One capture pass; returns the minimum of the two tone levels in dBFS. */
static double run_pass(unsigned int rate, int with_speech, double *rms)
{
	unsigned int frames = rate * PERIOD_MS / 1000, total = rate * TEST_SEC, got = 0;
	int16_t *cap = calloc((size_t)total * CH, sizeof(*cap));
	struct play_ctx pc = { .rate = rate };
	struct snd_xferi x;
	pthread_t th;
	double a, b, lvl = -200.0;
	int fc;

	*rms = -200.0;
	if (!cap)
		return lvl;
	if (with_speech && speech_on(APP_LOOPBACK, rate / 1000))
		goto out_free;
	pc.fd = pcm_open(DEV_PLAY2, 0, rate);
	fc = pcm_open(DEV_CAP2, 1, rate);
	if (pc.fd < 0 || fc < 0 || pcm_sw(pc.fd, 4 * frames, 4 * frames) < 0)
		goto out_close;
	if (pthread_create(&th, NULL, play_thread, &pc))
		goto out_close;
	while (got + frames <= total && !stop) {
		x = (struct snd_xferi){ .buf = cap + (size_t)got * CH, .frames = frames };
		if (ioctl(fc, SNDRV_PCM_IOCTL_READI_FRAMES, &x) < 0) {
			if (errno == EPIPE) {
				ioctl(fc, SNDRV_PCM_IOCTL_PREPARE);
				continue;
			}
			fprintf(stderr, "capture: %s\n", strerror(errno));
			break;
		}
		got += x.result;
		if (with_speech)
			recv_msg(0);	/* keep acking modem notifications */
	}
	pthread_join(th, NULL);
	if (got > rate) {
		/* Skip the first second: start-up and modem loopback delay. */
		a = tone_dbfs(cap + (size_t)rate * CH, got - rate, rate, TONE_A);
		b = tone_dbfs(cap + (size_t)rate * CH, got - rate, rate, TONE_B);
		*rms = rms_dbfs(cap + (size_t)rate * CH, got - rate);
		lvl = a < b ? a : b;
		printf("pass(speech=%d): %u frames, %.0f Hz %.1f dBFS, %.0f Hz %.1f dBFS, rms %.1f dBFS\n",
		       with_speech, got, TONE_A, a, TONE_B, b, *rms);
	}
out_close:
	if (pc.fd >= 0)
		close(pc.fd);
	if (fc >= 0)
		close(fc);
	if (with_speech)
		speech_off();
out_free:
	free(cap);
	return lvl;
}

static int selftest(unsigned int rate)
{
	int hp = -1, hc = -1, ret = 1;
	double ctl, lvl, rms_ctl, rms;
	unsigned int i;

	for (i = 0; i < sizeof(routes) / sizeof(routes[0]); i++)
		if (ctl_set(routes[i], 1))
			goto out;
	/* As the HAL: prefill the hostless playback with silence, start it,
	 * then the capture; neither is fed or read afterwards. */
	hp = pcm_open(DEV_HOSTLESS, 0, rate);
	hc = pcm_open(DEV_HOSTLESS, 1, rate);
	if (hp < 0 || hc < 0 ||
	    pcm_sw(hp, 4 * (rate * PERIOD_MS / 1000), ~0ul >> 2) < 0 ||
	    pcm_sw(hc, 4 * (rate * PERIOD_MS / 1000), ~0ul >> 2) < 0 ||
	    pcm_write_silence(hp, rate / 5 < 4 * rate * PERIOD_MS / 1000 ?
			      rate / 5 : 4 * rate * PERIOD_MS / 1000) < 0 ||
	    ioctl(hp, SNDRV_PCM_IOCTL_START) < 0 ||
	    ioctl(hc, SNDRV_PCM_IOCTL_START) < 0) {
		fprintf(stderr, "Hostless_Speech start: %s\n", strerror(errno));
		goto out;
	}
	ctl = run_pass(rate, 0, &rms_ctl);
	lvl = run_pass(rate, 1, &rms);
	/* PASS: both tones come back through the modem at a usable level,
	 * well above what the same path gives with speech off. */
	ret = !(lvl > -45.0 && lvl - ctl > 20.0);
	printf("RESULT %s: tones %.1f dBFS with speech, %.1f dBFS without (rate %u)\n",
	       ret ? "FAIL" : "PASS", lvl, ctl, rate);
out:
	if (hp >= 0)
		close(hp);
	if (hc >= 0)
		close(hc);
	for (i = 0; i < sizeof(routes) / sizeof(routes[0]); i++)
		ctl_set(routes[i], 0);
	return ret;
}

int main(int argc, char **argv)
{
	struct sigaction sa = { .sa_handler = on_signal };	/* no SA_RESTART */
	int rate = 16, app = APP_NORMAL, secs = 0, ret = 0, i;

	if (argc < 2) {
		fprintf(stderr, "usage: %s on <8|16|32> [loopback] [seconds] | listen [seconds] |"
			" selftest [8|16|32]\n", argv[0]);
		return 2;
	}
	setvbuf(stdout, NULL, _IOLBF, 0);
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	fd = open(CCCI_AUD, O_RDWR);
	if (fd < 0) {
		perror(CCCI_AUD);
		return 1;
	}

	if (!strcmp(argv[1], "listen")) {
		hold(argc > 2 ? atoi(argv[2]) : 0, NULL);
		return 0;
	}
	if (!strcmp(argv[1], "selftest"))
		return selftest((argc > 2 ? atoi(argv[2]) : 16) * 1000);
	if (strcmp(argv[1], "on") || argc < 3)
		return 2;
	rate = atoi(argv[2]);
	for (i = 3; i < argc; i++) {
		if (!strcmp(argv[i], "loopback"))
			app = APP_LOOPBACK;
		else
			secs = atoi(argv[i]);
	}
	if (speech_on(app, rate) == 0) {
		printf("holding (SIGINT/SIGTERM to stop)\n");
		hold(secs, NULL);
	} else {
		ret = 1;
	}
	if (speech_off())
		ret = 1;
	close(fd);
	return ret;
}
