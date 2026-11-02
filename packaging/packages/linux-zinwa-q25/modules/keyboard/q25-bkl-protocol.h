/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef Q25_BKL_PROTOCOL_H
#define Q25_BKL_PROTOCOL_H
#ifdef __KERNEL__
#include <linux/errno.h>
#else
#include <errno.h>
#endif
#define Q25_BKL_REG 0x05
#define Q25_BKL_COMMAND 0x85
struct q25_bkl_io {
	void *ctx;
	int (*read)(void *ctx, unsigned int reg);
	int (*write)(void *ctx, unsigned int command, unsigned int value);
};
static inline int q25_bkl_get(struct q25_bkl_io *io)
{
	return io->read(io->ctx, Q25_BKL_REG);
}
static inline int q25_bkl_set(struct q25_bkl_io *io, unsigned int level)
{
	int ret;

	if (level > 255)
		return -EINVAL;
	ret = io->write(io->ctx, Q25_BKL_COMMAND, level);
	if (ret < 0)
		return ret;
	ret = q25_bkl_get(io);
	if (ret < 0)
		return ret;
	return (unsigned int)ret == level ? 0 : -EIO;
}
#endif
