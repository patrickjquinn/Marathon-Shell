// epdprobe: scripted e-paper characterisation client for the MP01 (EPAPER_GPU_TCON.md §4).
// Raw DRM and evdev, no libraries. The only sysfs writes are refresh_mode (a name),
// full_refresh ("1") and the backlight brightness.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <linux/input.h>

#ifdef EPDPROBE_E13
#error "E13 (stopped link) needs a separate kernel build and is deliberately not implemented"
#endif

#define PW 800
#define PH 600
#define NS 1000000000LL
#define MS 1000000LL
#define MAX_INPUTS 8
#define FOURCC_XRGB8888 ('X' | ('R' << 8) | ('2' << 16) | ('4' << 24))

static const char *const mode_names[] = { "quality", "clean", "text", "fast" };

enum op {
	OP_PLAN, OP_TRIAL, OP_END, OP_MODE, OP_CLEAR, OP_BG, OP_RECT, OP_RAMP, OP_CHECKER,
	OP_TEXT, OP_PAGE, OP_FLIP, OP_MARK, OP_AT, OP_SLEEP, OP_POLL, OP_REGSNAP,
	OP_WAITTOUCH, OP_ANIM, OP_OBSERVE, OP_NOTE, OP_STROBE,
};

struct cmd {
	enum op op;
	int line;
	double a[9];
	int na;
	char *s;
};

static struct {
	const char *card, *epd, *bl, *regmap, *plan, *log, *dump;
	const char *inputs[MAX_INPUTS];
	int ninputs, dry, nodrm;
	double poll_hz, l0_pct, dry_hz;
} opt = {
	.card = "/dev/dri/card0",
	.epd = "/sys/bus/i2c/devices/7-004b",
	.bl = "/sys/class/backlight/disp_pwm",
	.regmap = "/sys/kernel/debug/regmap/7-004b",
	.log = "epdprobe.tsv",
	.poll_hz = 1000, .l0_pct = 30, .dry_hz = 60,
};

static volatile sig_atomic_t quit;
static FILE *out_log;
static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;
static int64_t vclock;

static int drm_fd = -1, ts_mono;
static uint32_t crtc_id, conn_id, fb_w, fb_h;
static int rotated;
static struct drm_mode_modeinfo mode;
static struct buf { uint32_t handle, pitch, fb; uint64_t size; uint32_t *map; } bufs[3];
static int next_buf, prepared, flip_pending;
static int64_t last_vbl;
static uint32_t last_vbl_seq;
static uint32_t canvas[PH][PW];

static int fd_mode = -1, fd_clear = -1, fd_bl = -1;
static int bl_max, bl_orig = -1, bl_l0;

static int in_fd[MAX_INPUTS], nin;
static int touching;
static unsigned touch_slots[MAX_INPUTS];
static int touch_btn[MAX_INPUTS], cur_slot[MAX_INPUTS];

static int reg_fd = -1, reg_on, reg_thread_run;
static const int reg_list[4] = { 0x89, 0x8b, 0x8d, 0x8f };
static off_t reg_off[4];
static int reg_linelen, reg_hexlen;
static pthread_t reg_thread;

static int trial_seq = -1, flip_no, flip_total;
static int64_t mark_t;

static void die(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "epdprobe: ");
	vfprintf(stderr, fmt, ap);
	fputc('\n', stderr);
	va_end(ap);
	quit = 2;
}

static int64_t mono(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * NS + ts.tv_nsec;
}

static int64_t now(void) { return opt.dry ? vclock : mono(); }

static void emit(int64_t t, const char *kind, const char *fmt, ...)
{
	va_list ap;
	pthread_mutex_lock(&log_lock);
	fprintf(out_log, "%lld\t%s", (long long)t, kind);
	if (fmt) {
		fputc('\t', out_log);
		va_start(ap, fmt);
		vfprintf(out_log, fmt, ap);
		va_end(ap);
	}
	fputc('\n', out_log);
	pthread_mutex_unlock(&log_lock);
}

/* ---- plan ---- */

static const struct { const char *name; enum op op; int min, max; int text; } ops[] = {
	{ "plan", OP_PLAN, 0, 0, 1 },     { "trial", OP_TRIAL, 2, 2, 1 },
	{ "end", OP_END, 0, 0, 0 },       { "mode", OP_MODE, 0, 0, 1 },
	{ "clear", OP_CLEAR, 0, 0, 0 },   { "bg", OP_BG, 1, 1, 0 },
	{ "rect", OP_RECT, 5, 7, 0 },     { "ramp", OP_RAMP, 8, 8, 0 },
	{ "checker", OP_CHECKER, 7, 7, 0 }, { "text", OP_TEXT, 4, 4, 1 },
	{ "page", OP_PAGE, 2, 2, 0 },     { "flip", OP_FLIP, 0, 0, 0 },
	{ "mark", OP_MARK, 0, 0, 0 },     { "at", OP_AT, 1, 1, 0 },
	{ "sleep", OP_SLEEP, 1, 1, 0 },   { "poll", OP_POLL, 1, 1, 0 },
	{ "regsnap", OP_REGSNAP, 0, 0, 0 }, { "waittouch", OP_WAITTOUCH, 0, 0, 0 },
	{ "anim", OP_ANIM, 8, 8, 0 },     { "observe", OP_OBSERVE, 1, 1, 0 },
	{ "note", OP_NOTE, 0, 0, 1 },     { "strobe", OP_STROBE, 1, 1, 0 },
};

static struct cmd *plan;
static int nplan;

static int load_plan(const char *path)
{
	FILE *f = strcmp(path, "-") ? fopen(path, "r") : stdin;
	char line[1024];
	int ln = 0, cap = 0, cleans = 0, draws = 0, err = 0;

	if (!f) {
		die("%s: %s", path, strerror(errno));
		return -1;
	}
	while (fgets(line, sizeof(line), f)) {
		char *p = line, *tok, *save;
		struct cmd c = { .line = ++ln };
		size_t i;

		line[strcspn(line, "\r\n")] = 0;
		while (*p == ' ' || *p == '\t')
			p++;
		if (!*p || *p == '#')
			continue;
		tok = strtok_r(p, " \t", &save);
		for (i = 0; i < sizeof(ops) / sizeof(ops[0]); i++)
			if (!strcmp(tok, ops[i].name))
				break;
		if (i == sizeof(ops) / sizeof(ops[0])) {
			fprintf(stderr, "plan:%d: unknown command '%s'\n", ln, tok);
			err = 1;
			continue;
		}
		c.op = ops[i].op;
		while (c.na < ops[i].max && (tok = strtok_r(NULL, " \t", &save))) {
			char *end;
			if (c.op == OP_POLL)
				c.a[c.na++] = !strcmp(tok, "on");
			else if ((c.a[c.na] = strtod(tok, &end)), *end) {
				fprintf(stderr, "plan:%d: bad number '%s'\n", ln, tok);
				err = 1;
				break;
			} else
				c.na++;
		}
		if (ops[i].text) {
			char *rest = strtok_r(NULL, "", &save);
			c.s = strdup(rest ? rest : "");
		} else if (strtok_r(NULL, " \t", &save)) {
			fprintf(stderr, "plan:%d: too many arguments\n", ln);
			err = 1;
		}
		if (c.na < ops[i].min || (c.op == OP_RECT && c.na == 6)) {
			fprintf(stderr, "plan:%d: '%s' needs %d..%d numbers\n", ln, ops[i].name,
				ops[i].min, ops[i].max);
			err = 1;
		}
		if (c.op == OP_MODE) {
			int k, ok = 0;
			for (k = 0; k < 4; k++)
				ok |= !strcmp(c.s, mode_names[k]);
			if (!ok) {
				fprintf(stderr, "plan:%d: unknown mode '%s'\n", ln, c.s);
				err = 1;
			}
			/* `clean` double-flashes; the plan may enter it once, in E6c's last step. */
			if (!strcmp(c.s, "clean") && ++cleans > 1) {
				fprintf(stderr, "plan:%d: 'mode clean' may appear only once\n", ln);
				err = 1;
			}
		}
		if (c.op >= OP_BG && c.op <= OP_MARK && c.op != OP_CLEAR)
			draws = 1;
		if (c.op == OP_ANIM || c.op == OP_AT)
			draws = 1;
		if (nplan == cap) {
			cap = cap ? cap * 2 : 1024;
			plan = realloc(plan, cap * sizeof(*plan));
		}
		plan[nplan++] = c;
	}
	if (f != stdin)
		fclose(f);
	if (opt.nodrm && draws) {
		fprintf(stderr, "plan draws or flips, which --no-drm cannot do\n");
		err = 1;
	}
	if (err)
		die("plan rejected; nothing was run");
	return err ? -1 : 0;
}

/* ---- drawing ---- */

static const char font_chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,-:";
static const uint8_t font[][7] = {
	{ 0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 }, { 0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E },
	{ 0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E }, { 0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C },
	{ 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F }, { 0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10 },
	{ 0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F }, { 0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11 },
	{ 0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E }, { 0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C },
	{ 0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11 }, { 0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F },
	{ 0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11 }, { 0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11 },
	{ 0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E }, { 0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10 },
	{ 0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D }, { 0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11 },
	{ 0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E }, { 0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04 },
	{ 0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E }, { 0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04 },
	{ 0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A }, { 0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11 },
	{ 0x11, 0x11, 0x11, 0x0A, 0x04, 0x04, 0x04 }, { 0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F },
	{ 0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E }, { 0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E },
	{ 0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F }, { 0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E },
	{ 0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02 }, { 0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E },
	{ 0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E }, { 0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },
	{ 0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E }, { 0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C },
	{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C }, { 0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08 },
	{ 0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00 }, { 0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00 },
};

static int glyph_bit(int ch, int gx, int gy)
{
	const char *p;
	if (ch >= 'a' && ch <= 'z')
		ch -= 32;
	p = ch ? strchr(font_chars, ch) : NULL;
	if (!p || gx < 0 || gx > 4 || gy < 0 || gy > 6)
		return 0;
	return font[p - font_chars][gy] >> (4 - gx) & 1;
}

static uint32_t grey(int v) { return (uint32_t)v * 0x010101u; }

static void fill(int x, int y, int w, int h, uint32_t c)
{
	int x1 = x + w > PW ? PW : x + w, y1 = y + h > PH ? PH : y + h, i, j;
	for (j = y < 0 ? 0 : y; j < y1; j++)
		for (i = x < 0 ? 0 : x; i < x1; i++)
			canvas[j][i] = c;
}

/* R2 low-discrepancy threshold: a cheap blue-noise stand-in, anchored to content coordinates. */
static int dither(int v, int cx, int cy)
{
	double t = fmod(cx * 0.7548776662466927 + cy * 0.5698402909980532, 1.0);
	return v / 255.0 > t ? 255 : 0;
}

static void draw_text(int x, int y, int scale, int v, const char *s)
{
	int i, gx, gy;
	for (i = 0; s[i]; i++)
		for (gy = 0; gy < 7; gy++)
			for (gx = 0; gx < 5; gx++)
				if (glyph_bit(s[i], gx, gy))
					fill(x + (i * 6 + gx) * scale, y + gy * scale, scale, scale, grey(v));
}

/* E11's scrolling page: text lines and a grey image block, a function of content coordinates. */
#define PAGE_X 52
#define PAGE_Y 72
#define PAGE_W 696
#define PAGE_H 456
static int page_px(int cx, int cy, int dith)
{
	int r = cy % 240, line, col, ch;
	uint32_t h;
	if (r < 160) {
		line = cy / 20;
		col = cx / 12;
		h = (uint32_t)(line * 73856093u) ^ (uint32_t)(col * 19349663u);
		h ^= h >> 13;
		h *= 0x5bd1e995u;
		h ^= h >> 15;
		ch = (h % 7 == 0 || cx < 12 || cx >= PAGE_W - 12) ? 0 : 'A' + (int)(h >> 8) % 26;
		return cy % 20 >= 3 && glyph_bit(ch, (cx % 12) / 2, (cy % 20 - 3) / 2) ? 0 : 255;
	}
	if (r < 168 || r >= 232 || cx < 24 || cx >= PAGE_W - 24)
		return 255;
	{
		double g = (cx - 24) / (double)(PAGE_W - 48);
		int v = (int)lround(255 * (0.5 * g + 0.25 + 0.25 * sin(cx / 14.0) * cos((r - 168) / 9.0)));
		return dith ? dither(v, cx, cy) : v;
	}
}

static void draw_page(int offset, int dith)
{
	int x, y;
	for (y = 0; y < PAGE_H; y++)
		for (x = 0; x < PAGE_W; x++)
			canvas[PAGE_Y + y][PAGE_X + x] = grey(page_px(x, y + offset, dith));
}

/* Fiducials (top-left one has a hole, so orientation is unambiguous) and the reference patch. */
static void overlay(uint32_t *row0, uint32_t pitch_px)
{
	static const int fx[4] = { 0, PW - 64, 0, PW - 64 }, fy[4] = { 0, 0, PH - 64, PH - 64 };
	int k, i, j;
	for (k = 0; k < 4; k++)
		for (j = 0; j < 64; j++)
			for (i = 0; i < 64; i++) {
				int in = i >= 12 && i < 52 && j >= 12 && j < 52;
				int hole = k == 0 && i >= 26 && i < 38 && j >= 26 && j < 38;
				row0[(fy[k] + j) * pitch_px + fx[k] + i] = in && !hole ? 0 : 0xffffff;
			}
	for (j = 8; j < 64; j++)
		for (i = 352; i < 448; i++)
			row0[j * pitch_px + i] = 0xffffff;
}

/* ---- sysfs: the only three writable files ---- */

static int sysfs_put(int fd, const char *s)
{
	ssize_t n = pwrite(fd, s, strlen(s), 0);
	return n == (ssize_t)strlen(s) ? 0 : -1;
}

static void set_mode(const char *name)
{
	int64_t t0 = now();
	int err = 0;
	if (!opt.dry)
		err = sysfs_put(fd_mode, name);
	emit(now(), "mode", "%s\t%lld\t%d", name, (long long)t0, err ? errno : 0);
	if (opt.dry)
		vclock += MS / 5;
}

static void full_refresh(void)
{
	int64_t t0 = now();
	int err = 0;
	if (!opt.dry)
		err = sysfs_put(fd_clear, "1");
	emit(now(), "clear", "%lld\t%d", (long long)t0, err ? errno : 0);
	if (opt.dry)
		vclock += MS;
}

static void bl_set(int v, int seq, int bit)
{
	char b[16];
	int64_t t0 = now();
	if (v < 0)
		v = 0;
	if (v > bl_max)
		v = bl_max;
	snprintf(b, sizeof(b), "%d", v);
	if (!opt.dry && sysfs_put(fd_bl, b))
		die("backlight write: %s", strerror(errno));
	if (opt.dry)
		vclock += MS / 20;
	emit(now(), "bl", "%d\t%d\t%d\t%lld", seq, bit, v, (long long)t0);
}

static int read_int(const char *dir, const char *name)
{
	char p[512], b[32];
	int fd, n;
	snprintf(p, sizeof(p), "%s/%s", dir, name);
	fd = open(p, O_RDONLY);
	if (fd < 0)
		return -1;
	n = read(fd, b, sizeof(b) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	b[n] = 0;
	return atoi(b);
}

static int open_wo(const char *dir, const char *name)
{
	char p[512];
	int fd;
	snprintf(p, sizeof(p), "%s/%s", dir, name);
	fd = open(p, O_WRONLY);
	if (fd < 0)
		die("%s: %s", p, strerror(errno));
	return fd;
}

/* ---- regmap debugfs: read-only, one register per pread ---- */

static int reg_setup(void)
{
	char p[512], b[256];
	int fd, n, lo, hi, maxreg = 0, idx = 0, k, found = 0;
	char *s;

	snprintf(p, sizeof(p), "%s/range", opt.regmap);
	fd = open(p, O_RDONLY);
	if (fd < 0)
		return -1;
	n = read(fd, b, sizeof(b) - 1);
	close(fd);
	if (n <= 0)
		return -1;
	b[n] = 0;
	for (s = b; sscanf(s, "%x-%x", &lo, &hi) == 2; s = strchr(s, '\n') + 1) {
		maxreg = hi;
		if (!strchr(s, '\n'))
			break;
	}
	reg_hexlen = snprintf(NULL, 0, "%x", maxreg);
	reg_linelen = reg_hexlen + 2 + 2 + 1;
	for (s = b; sscanf(s, "%x-%x", &lo, &hi) == 2;) {
		int r;
		for (r = lo; r <= hi; r++, idx++)
			for (k = 0; k < 4; k++)
				if (reg_list[k] == r) {
					reg_off[k] = (off_t)idx * reg_linelen;
					found++;
				}
		s = strchr(s, '\n');
		if (!s)
			break;
		s++;
	}
	if (found != 4)
		return -1;
	snprintf(p, sizeof(p), "%s/registers", opt.regmap);
	reg_fd = open(p, O_RDONLY);
	return reg_fd < 0 ? -1 : 0;
}

static void reg_sample(void)
{
	char b[16], want[8];
	int k, v[4];
	int64_t t = mono();
	for (k = 0; k < 4; k++) {
		ssize_t n = pread(reg_fd, b, reg_linelen, reg_off[k]);
		snprintf(want, sizeof(want), "%0*x:", reg_hexlen, reg_list[k]);
		if (n != reg_linelen || strncmp(b, want, reg_hexlen + 1)) {
			fprintf(stderr, "epdprobe: regmap layout is not what range promised; polling stopped\n");
			__atomic_store_n(&reg_thread_run, 0, __ATOMIC_RELAXED);
			return;
		}
		b[n - 1] = 0;
		v[k] = b[reg_hexlen + 2] == 'X' ? -1 : (int)strtol(b + reg_hexlen + 2, NULL, 16);
	}
	emit(t, "reg", "%d\t%d\t%d\t%d", v[0], v[1], v[2], v[3]);
}

static void *reg_loop(void *arg)
{
	int64_t period = (int64_t)(NS / opt.poll_hz), t = mono();
	(void)arg;
	while (__atomic_load_n(&reg_thread_run, __ATOMIC_RELAXED)) {
		struct timespec ts;
		if (__atomic_load_n(&reg_on, __ATOMIC_RELAXED))
			reg_sample();
		t += period;
		if (t < mono())
			t = mono();
		ts.tv_sec = t / NS;
		ts.tv_nsec = t % NS;
		clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &ts, NULL);
	}
	return NULL;
}

/* ---- input ---- */

static int test_bit(const unsigned long *bits, int n)
{
	return bits[n / (8 * sizeof(long))] >> (n % (8 * sizeof(long))) & 1;
}

static void open_input(const char *path)
{
	unsigned long absb[(ABS_CNT + 63) / 64] = { 0 }, keyb[(KEY_CNT + 63) / 64] = { 0 };
	struct input_absinfo ax = { 0 }, ay = { 0 };
	char name[128] = "?";
	int clk = CLOCK_MONOTONIC, fd, mt;

	if (nin == MAX_INPUTS)
		return;
	fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0)
		return;
	ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absb)), absb);
	ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keyb)), keyb);
	mt = test_bit(absb, ABS_MT_POSITION_X);
	if (!opt.ninputs && !mt && !test_bit(keyb, BTN_TOUCH)) {
		close(fd);
		return;
	}
	if (ioctl(fd, EVIOCSCLOCKID, &clk)) {
		die("%s: EVIOCSCLOCKID: %s", path, strerror(errno));
		close(fd);
		return;
	}
	ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
	ioctl(fd, EVIOCGABS(mt ? ABS_MT_POSITION_X : ABS_X), &ax);
	ioctl(fd, EVIOCGABS(mt ? ABS_MT_POSITION_Y : ABS_Y), &ay);
	touch_btn[nin] = test_bit(keyb, BTN_TOUCH);
	emit(mono(), "input", "%d\t%s\t%s\t%d\t%d\t%d\t%d", nin, path, name, ax.minimum, ax.maximum,
	     ay.minimum, ay.maximum);
	in_fd[nin++] = fd;
}

static void open_inputs(void)
{
	int i;
	if (opt.ninputs) {
		for (i = 0; i < opt.ninputs; i++)
			open_input(opt.inputs[i]);
		return;
	}
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	if (!d)
		return;
	while ((e = readdir(d))) {
		char p[300];
		if (strncmp(e->d_name, "event", 5))
			continue;
		snprintf(p, sizeof(p), "/dev/input/%s", e->d_name);
		open_input(p);
	}
	closedir(d);
}

static void read_input(int i)
{
	struct input_event ev[64];
	ssize_t n;
	int k;
	while ((n = read(in_fd[i], ev, sizeof(ev))) > 0)
		for (k = 0; k < n / (ssize_t)sizeof(ev[0]); k++) {
			struct input_event *e = &ev[k];
			int64_t t = e->input_event_sec * NS + e->input_event_usec * 1000LL;
			emit(t, "ev", "%d\t%d\t%d\t%d", i, e->type, e->code, e->value);
			if (e->type == EV_ABS && e->code == ABS_MT_SLOT)
				cur_slot[i] = e->value & 31;
			else if (e->type == EV_ABS && e->code == ABS_MT_TRACKING_ID && !touch_btn[i])
				touch_slots[i] = e->value >= 0 ? touch_slots[i] | 1u << cur_slot[i]
							       : touch_slots[i] & ~(1u << cur_slot[i]);
			else if (e->type == EV_KEY && e->code == BTN_TOUCH)
				touch_slots[i] = e->value ? 1 : 0;
			else if (e->type == EV_SYN && e->code == SYN_REPORT) {
				int any = 0, j;
				for (j = 0; j < nin; j++)
					any |= touch_slots[j] != 0;
				if (any != touching) {
					touching = any;
					emit(t, "touch", any ? "down" : "up");
				}
			}
		}
}

/* ---- DRM ---- */

static void read_drm(void)
{
	char b[1024];
	ssize_t n = read(drm_fd, b, sizeof(b)), o = 0;
	while (n > 0 && o + (ssize_t)sizeof(struct drm_event) <= n) {
		struct drm_event *e = (struct drm_event *)(b + o);
		if (e->type == DRM_EVENT_FLIP_COMPLETE) {
			struct drm_event_vblank *v = (struct drm_event_vblank *)e;
			last_vbl = v->tv_sec * NS + v->tv_usec * 1000LL;
			last_vbl_seq = v->sequence;
			flip_pending = 0;
		}
		o += e->length;
	}
}

/* Waits until `deadline` (or a flip completes, if want_flip), servicing input and DRM. */
static void pump(int64_t deadline, int want_flip)
{
	if (opt.dry) {
		if (vclock < deadline)
			vclock = deadline;
		return;
	}
	while (!quit) {
		struct pollfd pf[MAX_INPUTS + 1];
		struct timespec ts;
		int64_t left = deadline - mono();
		int n = 0, i;
		if (want_flip && !flip_pending)
			return;
		if (!want_flip && left <= 0)
			return;
		if (left < 0)
			left = 0;
		if (want_flip && left > NS)
			left = NS;
		for (i = 0; i < nin; i++)
			pf[n++] = (struct pollfd){ .fd = in_fd[i], .events = POLLIN };
		if (drm_fd >= 0)
			pf[n++] = (struct pollfd){ .fd = drm_fd, .events = POLLIN };
		ts.tv_sec = left / NS;
		ts.tv_nsec = left % NS;
		if (ppoll(pf, n, &ts, NULL) < 0 && errno != EINTR)
			return;
		for (i = 0; i < nin; i++)
			if (pf[i].revents & POLLIN)
				read_input(i);
		if (drm_fd >= 0 && pf[n - 1].revents & POLLIN)
			read_drm();
		if (want_flip && flip_pending && mono() > deadline) {
			die("page flip timed out");
			return;
		}
	}
}

static int drm_setup(void)
{
	struct drm_mode_card_res res = { 0 };
	struct drm_get_cap cap = { .capability = DRM_CAP_TIMESTAMP_MONOTONIC };
	uint32_t *conns, *crtcs, *encs;
	uint32_t i;
	int k;

	drm_fd = open(opt.card, O_RDWR | O_CLOEXEC);
	if (drm_fd < 0) {
		die("%s: %s", opt.card, strerror(errno));
		return -1;
	}
	if (ioctl(drm_fd, DRM_IOCTL_SET_MASTER, 0)) {
		die("cannot become DRM master on %s (%s): run `systemctl stop marathon-shell` first",
		    opt.card, strerror(errno));
		return -1;
	}
	ts_mono = !ioctl(drm_fd, DRM_IOCTL_GET_CAP, &cap) && cap.value;
	if (ioctl(drm_fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
		goto fail;
	conns = calloc(res.count_connectors + 1, 4);
	crtcs = calloc(res.count_crtcs + 1, 4);
	encs = calloc(res.count_encoders + 1, 4);
	res.connector_id_ptr = (uintptr_t)conns;
	res.crtc_id_ptr = (uintptr_t)crtcs;
	res.encoder_id_ptr = (uintptr_t)encs;
	res.count_fbs = 0;
	if (ioctl(drm_fd, DRM_IOCTL_MODE_GETRESOURCES, &res))
		goto fail;

	for (i = 0; i < res.count_connectors && !crtc_id; i++) {
		struct drm_mode_get_connector c = { .connector_id = conns[i] };
		struct drm_mode_modeinfo *modes;
		uint32_t *cencs, e;
		if (ioctl(drm_fd, DRM_IOCTL_MODE_GETCONNECTOR, &c) || c.connection != 1 || !c.count_modes)
			continue;
		modes = calloc(c.count_modes, sizeof(*modes));
		cencs = calloc(c.count_encoders + 1, 4);
		c.modes_ptr = (uintptr_t)modes;
		c.encoders_ptr = (uintptr_t)cencs;
		c.count_props = 0;
		if (ioctl(drm_fd, DRM_IOCTL_MODE_GETCONNECTOR, &c))
			continue;
		mode = modes[0];
		for (k = 0; k < (int)c.count_modes; k++)
			if (modes[k].type & DRM_MODE_TYPE_PREFERRED) {
				mode = modes[k];
				break;
			}
		for (e = 0; e < c.count_encoders && !crtc_id; e++) {
			struct drm_mode_get_encoder enc = { .encoder_id = cencs[e] };
			if (ioctl(drm_fd, DRM_IOCTL_MODE_GETENCODER, &enc))
				continue;
			if (enc.encoder_id == c.encoder_id && enc.crtc_id)
				crtc_id = enc.crtc_id;
			for (k = 0; k < (int)res.count_crtcs && !crtc_id; k++)
				if (enc.possible_crtcs & 1u << k)
					crtc_id = crtcs[k];
		}
		conn_id = c.connector_id;
	}
	if (!crtc_id) {
		die("no connected connector with a usable CRTC on %s", opt.card);
		return -1;
	}
	rotated = mode.hdisplay < PW && mode.hdisplay >= PH && mode.vdisplay >= PW;
	if (!rotated && (mode.hdisplay < PW || mode.vdisplay < PH)) {
		die("mode %ux%u does not hold the %dx%d panel", mode.hdisplay, mode.vdisplay, PW, PH);
		return -1;
	}
	fb_w = mode.hdisplay;
	fb_h = mode.vdisplay;
	for (k = 0; k < 3; k++) {
		struct drm_mode_create_dumb c = { .height = fb_h, .width = fb_w, .bpp = 32 };
		struct drm_mode_fb_cmd2 f = { .width = fb_w, .height = fb_h,
					      .pixel_format = FOURCC_XRGB8888 };
		struct drm_mode_map_dumb m = { 0 };
		if (ioctl(drm_fd, DRM_IOCTL_MODE_CREATE_DUMB, &c))
			goto fail;
		f.handles[0] = c.handle;
		f.pitches[0] = c.pitch;
		if (ioctl(drm_fd, DRM_IOCTL_MODE_ADDFB2, &f))
			goto fail;
		m.handle = c.handle;
		if (ioctl(drm_fd, DRM_IOCTL_MODE_MAP_DUMB, &m))
			goto fail;
		bufs[k] = (struct buf){ c.handle, c.pitch, f.fb_id, c.size, NULL };
		bufs[k].map = mmap(NULL, c.size, PROT_READ | PROT_WRITE, MAP_SHARED, drm_fd, m.offset);
		if (bufs[k].map == MAP_FAILED)
			goto fail;
		memset(bufs[k].map, 0, c.size);
	}
	return 0;
fail:
	die("DRM setup on %s: %s", opt.card, strerror(errno));
	return -1;
}

static void prepare(void)
{
	struct buf *b = &bufs[next_buf];
	uint32_t pp, y;
	if (prepared)
		return;
	if (!opt.dry && !rotated) {
		pp = b->pitch / 4;
		for (y = 0; y < PH; y++)
			memcpy(b->map + y * pp, canvas[y], PW * 4);
		overlay(b->map, pp);
	} else if (!opt.dry) {
		/* Portrait scan-out: canvas x runs down the buffer; the fiducials keep orientation. */
		static uint32_t tmp[PH][PW];
		uint32_t x;
		memcpy(tmp, canvas, sizeof(tmp));
		overlay(&tmp[0][0], PW);
		pp = b->pitch / 4;
		for (y = 0; y < PH; y++)
			for (x = 0; x < PW; x++)
				b->map[x * pp + (PH - 1 - y)] = tmp[y][x];
	}
	prepared = 1;
}

static int crtc_set;
static FILE *dump_f;

/* --dump: each flipped frame as 8x8-cell grey means (100x75 bytes), for synth_video.py. */
static void dump_frame(void)
{
	static uint32_t img[PH][PW];
	uint8_t cells[PH / 8][PW / 8];
	int cx, cy, x, y;
	memcpy(img, canvas, sizeof(img));
	overlay(&img[0][0], PW);
	for (cy = 0; cy < PH / 8; cy++)
		for (cx = 0; cx < PW / 8; cx++) {
			unsigned sum = 0;
			for (y = 0; y < 8; y++)
				for (x = 0; x < 8; x++) {
					uint32_t p = img[cy * 8 + y][cx * 8 + x];
					sum += (299 * (p >> 16 & 255) + 587 * (p >> 8 & 255) + 114 * (p & 255)) / 1000;
				}
			cells[cy][cx] = sum / 64;
		}
	fwrite(cells, sizeof(cells), 1, dump_f);
}

static void flip(void)
{
	int64_t submit;
	prepare();
	submit = now();
	if (opt.dry) {
		int64_t per = (int64_t)(NS / opt.dry_hz);
		last_vbl = (submit / per + 1) * per;
		last_vbl_seq = (uint32_t)(last_vbl / per);
		vclock = last_vbl + MS / 2;
	} else if (!crtc_set) {
		struct drm_mode_crtc c = { .set_connectors_ptr = (uintptr_t)&conn_id,
					   .count_connectors = 1, .crtc_id = crtc_id,
					   .fb_id = bufs[next_buf].fb, .mode_valid = 1, .mode = mode };
		if (ioctl(drm_fd, DRM_IOCTL_MODE_SETCRTC, &c)) {
			die("SETCRTC: %s", strerror(errno));
			return;
		}
		crtc_set = 1;
		last_vbl = mono();
		last_vbl_seq = 0;
	} else {
		struct drm_mode_crtc_page_flip f = { .crtc_id = crtc_id, .fb_id = bufs[next_buf].fb,
						     .flags = DRM_MODE_PAGE_FLIP_EVENT };
		if (ioctl(drm_fd, DRM_IOCTL_MODE_PAGE_FLIP, &f)) {
			die("PAGE_FLIP: %s", strerror(errno));
			return;
		}
		flip_pending = 1;
		pump(submit + NS, 1);
	}
	if (dump_f)
		dump_frame();
	emit(now(), "flip", "%d\t%d\t%lld\t%u\t%lld\t%d", trial_seq, flip_no, (long long)last_vbl,
	     last_vbl_seq, (long long)submit, flip_total);
	flip_no++;
	flip_total++;
	next_buf = (next_buf + 1) % 3;
	prepared = 0;
}

/* ---- trial machinery ---- */

static void strobe(int seq, int id)
{
	int64_t t = now();
	int i;
	emit(t, "code", "%d\t%d", seq, id);
	bl_set(bl_max, seq, -1);
	pump(t + 50 * MS, 0);
	for (i = 0; i < 8 && !quit; i++) {
		bl_set(id >> (7 - i) & 1 ? bl_max : bl_l0, seq, i);
		pump(t + (50 + 25 * (i + 1)) * MS, 0);
	}
	bl_set(bl_l0, seq, 8);
}

static void wait_touch(void)
{
	if (opt.dry) {
		emit(now(), "touch", "down");
		vclock += 300 * MS;
		emit(now(), "touch", "up");
	} else {
		fprintf(stderr, "epdprobe: waiting for a touch\n");
		while (!quit && !touching)
			pump(now() + 100 * MS, 0);
		while (!quit && touching)
			pump(now() + 100 * MS, 0);
	}
}

static void anim(const double *a)
{
	int x = a[0], y = a[1], w = a[2], h = a[3], v = a[4], f, n = a[6], k = a[7] < 1 ? 1 : a[7];
	double dx = a[5];
	for (f = 0; f < n && !quit; f++) {
		int pos = x + (int)lround(dx * k * (f / k));
		fill(x, y, (int)lround(dx * n) + w, h, grey(255));
		fill(pos, y, w, h, grey(v));
		prepared = 0;
		flip();
	}
}

static void run(void)
{
	int i;
	for (i = 0; i < nplan && !quit; i++) {
		struct cmd *c = &plan[i];
		const double *a = c->a;
		if (c->op >= OP_BG && c->op <= OP_PAGE)
			prepared = 0;
		switch (c->op) {
		case OP_PLAN:
			emit(now(), "plan", "%s", c->s);
			break;
		case OP_TRIAL:
			trial_seq = (int)a[0];
			flip_no = 0;
			emit(now(), "trial", "%d\t%d\t%s", trial_seq, (int)a[1] & 255, c->s);
			fprintf(stderr, "epdprobe: trial %d %s\n", trial_seq, c->s);
			strobe(trial_seq, (int)a[1] & 255);
			break;
		case OP_END:
			emit(now(), "end", "%d", trial_seq);
			break;
		case OP_MODE:
			set_mode(c->s);
			break;
		case OP_CLEAR:
			full_refresh();
			break;
		case OP_BG:
			fill(0, 0, PW, PH, grey((int)a[0] & 255));
			break;
		case OP_RECT:
			fill(a[0], a[1], a[2], a[3],
			     c->na == 7 ? ((uint32_t)a[4] & 255) << 16 | ((uint32_t)a[5] & 255) << 8 |
						  ((uint32_t)a[6] & 255)
					: grey((int)a[4] & 255));
			break;
		case OP_RAMP: {
			int cols = a[4], rows = a[5], n = a[6], r, cc, j, q;
			for (r = 0; r < rows; r++)
				for (cc = 0; cc < cols; cc++) {
					int idx = r * cols + cc, v = (int)lround(255.0 * idx / (n - 1));
					int x0 = a[0] + cc * a[2], y0 = a[1] + r * a[3];
					if (idx >= n)
						continue;
					if (!a[7]) {
						fill(x0, y0, a[2], a[3], grey(v));
						continue;
					}
					for (j = 0; j < a[3]; j++)
						for (q = 0; q < a[2]; q++)
							if (y0 + j < PH && x0 + q < PW)
								canvas[y0 + j][x0 + q] =
									grey(dither(v, x0 + q - (int)a[0],
										    y0 + j - (int)a[1]));
				}
			break;
		}
		case OP_CHECKER: {
			int x0 = a[0], y0 = a[1], cell = a[4], j, q;
			for (j = 0; j < a[3] && y0 + j < PH; j++)
				for (q = 0; q < a[2] && x0 + q < PW; q++)
					canvas[y0 + j][x0 + q] =
						grey(((q / cell + j / cell) & 1 ? (int)a[6] : (int)a[5]) & 255);
			break;
		}
		case OP_TEXT:
			draw_text(a[0], a[1], a[2], (int)a[3] & 255, c->s);
			break;
		case OP_PAGE:
			draw_page(a[0], a[1] != 0);
			break;
		case OP_FLIP:
			flip();
			break;
		case OP_MARK:
			mark_t = last_vbl;
			emit(now(), "mark", "%d\t%lld", trial_seq, (long long)mark_t);
			break;
		case OP_AT:
			prepare();
			pump(mark_t + (int64_t)(a[0] * MS), 0);
			break;
		case OP_SLEEP:
			pump(now() + (int64_t)(a[0] * MS), 0);
			break;
		case OP_POLL:
			__atomic_store_n(&reg_on, reg_fd >= 0 && a[0], __ATOMIC_RELAXED);
			break;
		case OP_REGSNAP:
			if (reg_fd >= 0)
				reg_sample();
			break;
		case OP_WAITTOUCH:
			wait_touch();
			break;
		case OP_ANIM:
			anim(a);
			break;
		case OP_OBSERVE:
			pump(now() + (int64_t)(a[0] * MS), 0);
			break;
		case OP_NOTE:
			emit(now(), "note", "%s", c->s);
			break;
		case OP_STROBE:
			strobe(trial_seq, (int)a[0] & 255);
			break;
		}
	}
}

static void on_signal(int sig)
{
	(void)sig;
	quit = 1;
}

static void usage(void)
{
	fprintf(stderr,
		"usage: epdprobe [options] PLAN\n"
		"  --card PATH      DRM card (default %s)\n"
		"  --epd DIR        CPLD i2c device dir with refresh_mode/full_refresh (default %s)\n"
		"  --backlight DIR  backlight class dir used as the strobe (default %s)\n"
		"  --regmap DIR     regmap debugfs dir, '' to disable (default %s)\n"
		"  --poll-hz N      register poll rate during 'poll on' (default %.0f)\n"
		"  --l0 PCT         base frontlight level (default %.0f)\n"
		"  --input PATH     evdev device to log (repeatable; default: all touch devices)\n"
		"  --log PATH       output log (default %s)\n"
		"  --no-drm         log input/registers and strobe only (E14, shell running)\n"
		"  --dry-run        run the plan without DRM or sysfs, on a virtual clock\n"
		"  --dry-hz N       virtual vblank rate for --dry-run (default %.0f)\n"
		"  --dump PATH      with --dry-run: write every flipped frame as 8x8-cell means\n",
		opt.card, opt.epd, opt.bl, opt.regmap, opt.poll_hz, opt.l0_pct,
		opt.log, opt.dry_hz);
	exit(2);
}

int main(int argc, char **argv)
{
	struct sigaction sa = { .sa_handler = on_signal };
	int i, uses_epd = 0;

	for (i = 1; i < argc; i++) {
		const char *a = argv[i], *v = i + 1 < argc ? argv[i + 1] : NULL;
#define ARG(name) (!strcmp(a, name) && v && (i++, 1))
		if (ARG("--card"))
			opt.card = v;
		else if (ARG("--epd"))
			opt.epd = v;
		else if (ARG("--backlight"))
			opt.bl = v;
		else if (ARG("--regmap"))
			opt.regmap = v;
		else if (ARG("--poll-hz"))
			opt.poll_hz = atof(v);
		else if (ARG("--l0"))
			opt.l0_pct = atof(v);
		else if (ARG("--log"))
			opt.log = v;
		else if (ARG("--dump"))
			opt.dump = v;
		else if (ARG("--dry-hz"))
			opt.dry_hz = atof(v);
		else if (ARG("--input") && opt.ninputs < MAX_INPUTS)
			opt.inputs[opt.ninputs++] = v;
		else if (!strcmp(a, "--dry-run"))
			opt.dry = 1;
		else if (!strcmp(a, "--no-drm"))
			opt.nodrm = 1;
		else if (a[0] == '-' && a[1])
			usage();
		else
			opt.plan = a;
#undef ARG
	}
	if (!opt.plan || opt.poll_hz <= 0 || opt.poll_hz > 5000 || opt.l0_pct < 1 ||
	    opt.l0_pct > 100 || opt.dry_hz <= 0)
		usage();
	if (load_plan(opt.plan))
		return 1;
	for (i = 0; i < nplan; i++)
		uses_epd |= plan[i].op == OP_MODE || plan[i].op == OP_CLEAR;

	out_log = fopen(opt.log, "w");
	if (!out_log) {
		perror(opt.log);
		return 1;
	}
	setvbuf(out_log, NULL, _IOFBF, 1 << 20);
	if (opt.dump && opt.dry && !(dump_f = fopen(opt.dump, "wb"))) {
		perror(opt.dump);
		return 1;
	}
	sigaction(SIGINT, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);

	if (opt.dry) {
		bl_max = 255;
		vclock = 1000 * NS;
	} else {
		if (uses_epd) {
			fd_mode = open_wo(opt.epd, "refresh_mode");
			fd_clear = open_wo(opt.epd, "full_refresh");
		}
		bl_max = read_int(opt.bl, "max_brightness");
		bl_orig = read_int(opt.bl, "brightness");
		if (bl_max <= 0 || bl_orig < 0)
			die("%s: no readable max_brightness/brightness", opt.bl);
		else
			fd_bl = open_wo(opt.bl, "brightness");
		if (*opt.regmap && reg_setup())
			fprintf(stderr, "epdprobe: regmap %s unusable; registers not logged\n", opt.regmap);
		open_inputs();
		if (!nin)
			fprintf(stderr, "epdprobe: no touch input found; waittouch will block\n");
		if (!quit && !opt.nodrm)
			drm_setup();
	}
	bl_l0 = (int)lround(bl_max * opt.l0_pct / 100.0);
	emit(now(), "meta", "dry=%d\tcard=%s\tmode=%ux%u@%u\tts_mono=%d\tbl_max=%d\tbl_orig=%d\tl0=%d\t"
			    "poll_hz=%.0f\tregmap=%d\tdry_hz=%.3f\trotated=%d",
	     opt.dry, opt.nodrm ? "-" : opt.card, mode.hdisplay, mode.vdisplay, mode.vrefresh,
	     ts_mono, bl_max, bl_orig, bl_l0, opt.poll_hz, reg_fd >= 0, opt.dry_hz, rotated);
	if (!opt.dry && !opt.nodrm && !quit && !ts_mono)
		fprintf(stderr, "epdprobe: driver does not report CLOCK_MONOTONIC vblank stamps\n");

	if (!quit) {
		if (reg_fd >= 0) {
			reg_thread_run = 1;
			pthread_create(&reg_thread, NULL, reg_loop, NULL);
		}
		bl_set(bl_l0, -1, -2);
		pump(now() + NS, 0);
		run();
	}

	if (reg_thread_run) {
		__atomic_store_n(&reg_thread_run, 0, __ATOMIC_RELAXED);
		pthread_join(reg_thread, NULL);
	}
	if (fd_bl >= 0 && bl_orig >= 0)
		bl_set(bl_orig, -1, -3);
	emit(now(), "exit", "%d", (int)quit);
	fclose(out_log);
	if (dump_f)
		fclose(dump_f);
	if (drm_fd >= 0)
		close(drm_fd);
	if (!opt.dry)
		fprintf(stderr, "epdprobe: %s. Now run: systemctl restart marathon-shell\n",
			quit == 1 ? "interrupted" : quit ? "stopped on error" : "done");
	return quit ? 1 : 0;
}
