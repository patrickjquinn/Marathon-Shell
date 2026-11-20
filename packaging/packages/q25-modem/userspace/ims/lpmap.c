// SPDX-License-Identifier: Apache-2.0
// q25-lp-map: where a logical partition of Android's `super` lies, from its
// own metadata (liblp's on-disk format), for a read-only loop mount.
//
//   q25-lp-map /dev/disk/by-partlabel/super vendor_a
//   -> "<offset bytes> <size bytes>" of a partition with one linear extent.
#define _GNU_SOURCE
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define LP_RESERVED 4096
#define GEOMETRY_MAGIC 0x616c4467u
#define HEADER_MAGIC 0x414C5030u
#define SECTOR 512

struct geometry {
	uint32_t magic, struct_size;
	uint8_t checksum[32];
	uint32_t metadata_max_size, metadata_slot_count, logical_block_size;
} __attribute__((packed));

struct table {
	uint32_t offset, num_entries, entry_size;
} __attribute__((packed));

struct header {
	uint32_t magic;
	uint16_t major, minor;
	uint32_t header_size;
	uint8_t header_checksum[32];
	uint32_t tables_size;
	uint8_t tables_checksum[32];
	struct table partitions, extents, groups, block_devices;
} __attribute__((packed));

struct partition {
	char name[36];
	uint32_t attributes, first_extent_index, num_extents, group_index;
} __attribute__((packed));

struct extent {
	uint64_t num_sectors;
	uint32_t target_type;
	uint64_t target_data;
	uint32_t target_source;
} __attribute__((packed));

static int pread_all(int fd, void *buf, size_t len, off_t off)
{
	return pread(fd, buf, len, off) == (ssize_t)len ? 0 : -1;
}

int main(int argc, char **argv)
{
	if (argc != 3) {
		fprintf(stderr, "usage: q25-lp-map <super> <partition>\n");
		return 2;
	}
	int fd = open(argv[1], O_RDONLY | O_CLOEXEC);
	struct geometry g;
	if (fd < 0 || pread_all(fd, &g, sizeof(g), LP_RESERVED) || g.magic != GEOMETRY_MAGIC) {
		fprintf(stderr, "q25-lp-map: %s: no liblp geometry\n", argv[1]);
		return 1;
	}
	// Slot 0's primary metadata follows the reserved area and two geometry copies.
	off_t meta = LP_RESERVED + 2 * 4096;
	struct header h;
	if (pread_all(fd, &h, sizeof(h), meta) || h.magic != HEADER_MAGIC) {
		fprintf(stderr, "q25-lp-map: %s: no liblp metadata header\n", argv[1]);
		return 1;
	}
	off_t tables = meta + h.header_size;
	for (uint32_t i = 0; i < h.partitions.num_entries; i++) {
		struct partition p;
		if (pread_all(fd, &p, sizeof(p), tables + h.partitions.offset + (off_t)i * h.partitions.entry_size))
			return 1;
		if (strncmp(p.name, argv[2], sizeof(p.name)) != 0)
			continue;
		if (p.num_extents != 1) {
			fprintf(stderr, "q25-lp-map: %s has %u extents\n", argv[2], p.num_extents);
			return 1;
		}
		struct extent e;
		if (pread_all(fd, &e, sizeof(e), tables + h.extents.offset + (off_t)p.first_extent_index * h.extents.entry_size) ||
		    e.target_type != 0 /* linear */)
			return 1;
		printf("%llu %llu\n", (unsigned long long)e.target_data * SECTOR,
		       (unsigned long long)e.num_sectors * SECTOR);
		return 0;
	}
	fprintf(stderr, "q25-lp-map: no partition %s\n", argv[2]);
	return 1;
}
