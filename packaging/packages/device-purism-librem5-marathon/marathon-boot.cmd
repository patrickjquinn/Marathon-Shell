# Marathon Librem 5 U-Boot script.
#
# Based on upstream u-boot-librem5's boot.cmd, modified to enable
# Plymouth splash + clean kernel-quiet boot on the DSI panel:
#
#   * console=tty1                  — route kernel printk to the mxsfb
#                                     framebuffer (panel), not just UART
#   * console=ttymxc0,115200        — keep UART for serial debug
#   * splash                        — Plymouth activates the splash
#   * quiet loglevel=3              — suppress noisy kernel init logs
#   * vt.global_cursor_default=0    — hide the blinking VT cursor that
#                                     would otherwise blink behind splash
#
# Upstream pmaports u-boot-librem5 boot.cmd is intentionally minimal
# (serial-debug-first). Marathon owns the user-facing boot experience
# so we override it here.
#
# Defaults if not set in the U-Boot environment.
if itest.s "x" == "x$devtype" ; then
        devtype="mmc"
fi
if itest.s "x" == "x$devnum" ; then
        devnum=0
fi
if itest.s "x" == "x$bootpart" ; then
        bootpart=1
fi

#   * module_blacklist=st_lsm6dsx_i2c,st_lsm6dsx_spi,st_lsm6dsx
#                                   — the lsm9ds1 6-axis accelerometer
#                                     driver hangs in st_lsm6dsx_read_raw on
#                                     this hardware. Anything reading the
#                                     accel sysfs file (Qt's iio-sensor-
#                                     proxy backend probe, iio-sensor-proxy
#                                     itself, ANY userspace sensor client)
#                                     wedges its calling thread in D-state
#                                     forever. Marathon's RotationManager
#                                     hit this and dropped the whole shell
#                                     to ~2 fps. The lazy-construct fix in
#                                     marathon-shell r192 covers the
#                                     ConnectToBackend path; this cmdline
#                                     covers iio-sensor-proxy + every other
#                                     userspace probe. Auto-rotation is
#                                     lost on L5 until the driver is fixed
#                                     upstream — acceptable trade.
#
# DO NOT ADD `quiet` to bootargs. On L5, `quiet` accelerates kernel boot
# enough to race the mmc1 SDIO probe ahead of the SparkLAN/Redpine WiFi+BT
# chip's power-on settling — first CMD52 hits the bus before the chip is
# ready, the SDHCI controller eats CMD/DAT timeouts (IRQ 0x18000), and the
# probe gives up with `mmc1: error -110 whilst initialising SDIO card`.
# brcmfmac/redpine_sdio never auto-load (no SDIO alias to match) and WiFi+BT
# are dead until a cold cycle that may or may not recover. Same symptom on
# pmOS upstream when `quiet` is added; pmOS upstream omits it for the same
# reason. `loglevel=3` already suppresses console output below KERN_ERR, so
# we keep a clean boot without the timing hazard. See ux-overhaul session
# bisect 2026-06-23. Plymouth still engages off `splash` alone.
setenv bootargs "init=/init.sh rw console=tty1 console=ttymxc0,115200 splash loglevel=3 vt.global_cursor_default=0 module_blacklist=st_lsm6dsx_i2c,st_lsm6dsx_spi,st_lsm6dsx PMOS_FORCE_PARTITION_RESIZE"

# Board-rev DTB selection — kept verbatim from upstream so any future
# board revs the kernel knows about will still pick correctly.
# Default to "-r4" if board_rev isn't set; pmaports note 1147248594
# explains that some Evergreen boards report ambiguous board_rev.
dtb_file=imx8mq-librem5-r4.dtb
if itest.s "x3" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r3.dtb
elif itest.s "x2" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
elif itest.s "x1" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
elif itest.s "x0" == "x$board_rev" ; then
        dtb_file=imx8mq-librem5-r2.dtb
fi

echo Loading DTB ${dtb_file}
ext2load $devtype ${devnum}:${bootpart} ${fdt_addr_r} ${dtb_file}
echo Loading Initramfs
ext2load $devtype ${devnum}:${bootpart} ${ramdisk_addr_r} initramfs
# Capture initramfs size BEFORE vmlinuz load — the upstream boot.cmd has a
# bug here: it uses ${filesize} (set by the LAST ext2load) which gets
# overwritten by the vmlinuz load below, so booti gets vmlinuz's size as
# the ramdisk_size, the kernel reads past end of initramfs into garbage,
# and prints "Initramfs unpacking failed: invalid magic at start of
# compressed archive". Functionally a wash (the kernel salvages what it
# can and pmOS initramfs still runs) but ugly and a real boot warning.
setenv initramfs_size ${filesize}
echo Loading Kernel
ext2load $devtype ${devnum}:${bootpart} ${kernel_addr_r} vmlinuz
fdt addr ${fdt_addr_r}
fdt resize
echo Booting Marathon
booti ${kernel_addr_r} ${ramdisk_addr_r}:${initramfs_size} ${fdt_addr_r}
