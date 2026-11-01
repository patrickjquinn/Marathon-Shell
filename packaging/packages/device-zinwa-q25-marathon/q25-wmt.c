// SPDX-License-Identifier: MIT
/*
 * q25-wmt: native stand-in for MediaTek's Android wmt_loader/wmt_launcher on
 * the Zinwa Q25 (MT6789 CONNSYS, SOC2_1X1). No Android HAL or properties.
 * Protocol and patch-header layout follow NikuzoKO/pmos-moto-g06-lagos
 * lagos-wmt.c (MIT, 0d678342) and the joint wmt_drv source.
 *
 *   q25-wmt init
 *       /dev/wmtdetect: CONNSYS_SOC_HW_INIT, GET_SOC_CHIP_ID (must be 0x6789),
 *       SET_CHIP_ID, DO_MODULE_INIT. DO_MODULE_INIT runs the WMT A-die probe,
 *       which powers CONN on and off once. The detected A-die is written to
 *       /run/q25-wmt.adie ("6631", "6635" or "unknown").
 *   q25-wmt launch [-p firmware-dir]
 *       Stay resident on /dev/stpwmt and answer the WMT "srh_rom_patch"
 *       up-call with soc2_2_ram_*_1<flavor>_1_hdr.bin for the detected A-die
 *       (6631 -> d, 6635 -> e). With no detected A-die every request fails.
 *   q25-wmt wifi-on [nvram-file]
 *       Optionally hand the Wi-Fi NVRAM blob to the driver, then write "S"
 *       (station mode) to /dev/wmtWifi.
 *   q25-wmt wifi-off
 *       Write "0" to /dev/wmtWifi.
 */
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stddef.h>
#include <unistd.h>

#define WMT_DETECT_IOC_MAGIC 'w'
#define COMBO_IOCTL_SET_CHIP_ID _IOW(WMT_DETECT_IOC_MAGIC, 1, int)
#define COMBO_IOCTL_GET_SOC_CHIP_ID _IOR(WMT_DETECT_IOC_MAGIC, 3, int)
#define COMBO_IOCTL_DO_MODULE_INIT _IOR(WMT_DETECT_IOC_MAGIC, 4, int)
#define COMBO_IOCTL_GET_ADIE_CHIP_ID _IOR(WMT_DETECT_IOC_MAGIC, 9, int)
#define COMBO_IOCTL_CONNSYS_SOC_HW_INIT _IOR(WMT_DETECT_IOC_MAGIC, 10, int)

#define WMT_IOC_MAGIC 0xa0
#define WMT_IOCTL_SET_STP_MODE _IOW(WMT_IOC_MAGIC, 5, int)
#define WMT_IOCTL_SET_ROM_PATCH_INFO _IOW(WMT_IOC_MAGIC, 31, char *)

/* (UART baud << 8) | (FM mode << 4) | STP mode: BTIF (3), FM common (2) */
#define STP_MODE_BTIF_FM_COMMON 0x23

#define Q25_SOC_CHIP_ID 0x6789
#define ADIE_STATE_FILE "/run/q25-wmt.adie"
#define PATCH_NAME_MAX 256
/* header: build time[16], platform[4], hw ver[2], sw ver[2], info[8] */
#define PATCH_INFO_OFFSET 24
#define WMTDRV_TYPE_MAX 4	/* BT 0, FM 1, GPS 2, WIFI 3, WMT 4 */

struct wmt_rom_patch_info {
	uint32_t type;
	uint8_t address[4];
	char name[PATCH_NAME_MAX];
};

static const char *firmware_directory = "/lib/firmware";

static int open_device(const char *path, int flags)
{
	int fd = -1;

	for (int attempt = 0; attempt < 50; attempt++) {
		fd = open(path, flags);
		if (fd >= 0 || errno != ENOENT)
			break;
		usleep(100000);
	}
	return fd;
}

static int write_adie_state(const char *state)
{
	FILE *f = fopen(ADIE_STATE_FILE, "w");

	if (!f)
		return -1;
	fprintf(f, "%s\n", state);
	return fclose(f);
}

static int detect_init(void)
{
	int fd = open_device("/dev/wmtdetect", O_RDWR);
	int chip_id, adie, ret;

	if (fd < 0) {
		perror("open /dev/wmtdetect");
		return 1;
	}
	unlink(ADIE_STATE_FILE);

	/* Registers the consys platform driver; probe must succeed first. */
	if (ioctl(fd, COMBO_IOCTL_CONNSYS_SOC_HW_INIT, 0) < 0 && errno != EEXIST) {
		perror("COMBO_IOCTL_CONNSYS_SOC_HW_INIT");
		goto fail;
	}
	chip_id = ioctl(fd, COMBO_IOCTL_GET_SOC_CHIP_ID, 0);
	if (chip_id != Q25_SOC_CHIP_ID) {
		fprintf(stderr, "unexpected connsys SoC chip id 0x%x (want 0x%x)\n",
			chip_id, Q25_SOC_CHIP_ID);
		goto fail;
	}
	printf("connsys chip id 0x%04x\n", chip_id);

	if (ioctl(fd, COMBO_IOCTL_SET_CHIP_ID, chip_id) < 0) {
		perror("COMBO_IOCTL_SET_CHIP_ID");
		goto fail;
	}
	ret = ioctl(fd, COMBO_IOCTL_DO_MODULE_INIT, chip_id);
	if (ret < 0) {
		perror("COMBO_IOCTL_DO_MODULE_INIT");
		goto fail;
	}

	/* Detection ran inside DO_MODULE_INIT; a cached id does not re-probe. */
	adie = ioctl(fd, COMBO_IOCTL_GET_ADIE_CHIP_ID, 0);
	close(fd);
	if (adie == 0x6631 || adie == 0x6635) {
		char text[8];

		snprintf(text, sizeof(text), "%x", adie);
		printf("A-die 0x%x\n", adie);
		write_adie_state(text);
		return 0;
	}
	fprintf(stderr, "A-die not identified (%d)\n", adie);
	write_adie_state("unknown");
	return 3;
fail:
	close(fd);
	return 1;
}

static char adie_flavor(void)
{
	char text[16] = { 0 };
	FILE *f = fopen(ADIE_STATE_FILE, "r");

	if (!f)
		return 0;
	if (!fgets(text, sizeof(text), f))
		text[0] = 0;
	fclose(f);
	if (!strncmp(text, "6631", 4))
		return 'd';
	if (!strncmp(text, "6635", 4))
		return 'e';
	return 0;
}

static int read_patch_info(const char *name, uint8_t info[8])
{
	char path[PATH_MAX];
	FILE *f;
	int ok;

	snprintf(path, sizeof(path), "%s/%s", firmware_directory, name);
	f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr, "open %s: %s\n", path, strerror(errno));
		return -1;
	}
	ok = fseek(f, PATCH_INFO_OFFSET, SEEK_SET) == 0 && fread(info, 1, 8, f) == 8;
	fclose(f);
	return ok ? 0 : -1;
}

/* soc2_2_ram_<kind>_1<flavor>_1_hdr.bin for kind mcu, wifi, bt */
static int answer_rom_patch_search(int wmt_fd)
{
	static const char *const kinds[] = { "mcu", "wifi", "bt" };
	char flavor = adie_flavor();
	int sent = 0;

	if (!flavor) {
		fprintf(stderr, "no detected A-die: refusing to pick a firmware flavour\n");
		return -1;
	}
	for (size_t i = 0; i < sizeof(kinds) / sizeof(kinds[0]); i++) {
		struct wmt_rom_patch_info rom = { 0 };
		uint8_t info[8];

		snprintf(rom.name, sizeof(rom.name), "soc2_2_ram_%s_1%c_1_hdr.bin",
			 kinds[i], flavor);
		if (read_patch_info(rom.name, info))
			return -1;
		rom.type = info[7];
		if (rom.type > WMTDRV_TYPE_MAX) {
			fprintf(stderr, "%s: bad type %u\n", rom.name, rom.type);
			return -1;
		}
		rom.address[0] = 0x00;
		rom.address[1] = info[1];
		rom.address[2] = info[2];
		rom.address[3] = info[3];
		printf("rom patch type %u: %s address %02x%02x%02x%02x\n", rom.type, rom.name,
		       rom.address[0], rom.address[1], rom.address[2], rom.address[3]);
		if (ioctl(wmt_fd, WMT_IOCTL_SET_ROM_PATCH_INFO, &rom) < 0) {
			perror("WMT_IOCTL_SET_ROM_PATCH_INFO");
			return -1;
		}
		sent++;
	}
	return sent == 3 ? 0 : -1;
}

/* systemd Type=notify: tell it the patch server is listening */
static void notify_ready(void)
{
	const char *path = getenv("NOTIFY_SOCKET");
	struct sockaddr_un addr = { .sun_family = AF_UNIX };
	size_t len;
	int fd;

	if (!path || (path[0] != '/' && path[0] != '@'))
		return;
	len = strlen(path);
	if (len >= sizeof(addr.sun_path))
		return;
	memcpy(addr.sun_path, path, len);
	if (addr.sun_path[0] == '@')
		addr.sun_path[0] = '\0';
	fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0)
		return;
	sendto(fd, "READY=1", 7, 0, (struct sockaddr *)&addr,
	       offsetof(struct sockaddr_un, sun_path) + len);
	close(fd);
}

static int launch(void)
{
	int wmt_fd = open_device("/dev/stpwmt", O_RDWR | O_NOCTTY);

	if (wmt_fd < 0) {
		perror("open /dev/stpwmt");
		return 1;
	}
	setvbuf(stdout, NULL, _IOLBF, 0);

	if (ioctl(wmt_fd, WMT_IOCTL_SET_STP_MODE, STP_MODE_BTIF_FM_COMMON) < 0) {
		perror("WMT_IOCTL_SET_STP_MODE");
		return 1;
	}
	printf("waiting for WMT requests (firmware %s, A-die flavour %c)\n",
	       firmware_directory, adie_flavor() ? adie_flavor() : '?');
	notify_ready();

	for (;;) {
		struct pollfd p = { .fd = wmt_fd, .events = POLLIN };
		char command[PATCH_NAME_MAX] = { 0 };
		const char *response;
		ssize_t length;
		int result = 0;

		if (poll(&p, 1, -1) < 0) {
			if (errno == EINTR)
				continue;
			perror("poll /dev/stpwmt");
			return 1;
		}
		if (!(p.revents & POLLIN))
			continue;
		length = read(wmt_fd, command, sizeof(command) - 1);
		if (length <= 0)
			continue;
		printf("request: %s\n", command);

		if (!strcmp(command, "srh_rom_patch"))
			result = answer_rom_patch_search(wmt_fd);
		else if (!strcmp(command, "srh_patch"))
			/* Q25 ships no soc2_2_patch_* ROM patch files. */
			result = -1;

		response = result ? "fail" : "ok";
		if (write(wmt_fd, response, strlen(response)) < 0)
			perror("write /dev/stpwmt");
	}
}

static int wifi_write(const char *data, size_t length)
{
	int fd = open_device("/dev/wmtWifi", O_WRONLY);
	ssize_t written;

	if (fd < 0) {
		perror("open /dev/wmtWifi");
		return 1;
	}
	written = write(fd, data, length);
	if (written != (ssize_t)length) {
		perror("write /dev/wmtWifi");
		close(fd);
		return 1;
	}
	close(fd);
	return 0;
}

static int wifi_on(const char *nvram_path)
{
	static const char prefix[] = "WR-BUF:NVRAM";
	static char buffer[sizeof(prefix) - 1 + 8192];

	if (nvram_path) {
		FILE *f = fopen(nvram_path, "rb");
		size_t n;

		if (!f) {
			fprintf(stderr, "open %s: %s\n", nvram_path, strerror(errno));
			return 1;
		}
		memcpy(buffer, prefix, sizeof(prefix) - 1);
		n = fread(buffer + sizeof(prefix) - 1, 1, sizeof(buffer) - (sizeof(prefix) - 1), f);
		fclose(f);
		if (n == 0) {
			fprintf(stderr, "%s is empty\n", nvram_path);
			return 1;
		}
		/* Must arrive while Wi-Fi is still off, in one write. */
		if (wifi_write(buffer, sizeof(prefix) - 1 + n))
			return 1;
	}
	return wifi_write("S", 1);
}

int main(int argc, char **argv)
{
	if (argc >= 2 && !strcmp(argv[1], "init"))
		return detect_init();
	if (argc >= 2 && !strcmp(argv[1], "launch")) {
		int option;

		optind = 2;
		while ((option = getopt(argc, argv, "p:")) != -1) {
			if (option != 'p')
				return 2;
			firmware_directory = optarg;
		}
		return launch();
	}
	if (argc >= 2 && !strcmp(argv[1], "wifi-on"))
		return wifi_on(argc >= 3 ? argv[2] : NULL);
	if (argc >= 2 && !strcmp(argv[1], "wifi-off"))
		return wifi_write("0", 1);

	fprintf(stderr, "usage: %s init | launch [-p firmware-dir] | wifi-on [nvram-file] | wifi-off\n",
		argv[0]);
	return 2;
}
