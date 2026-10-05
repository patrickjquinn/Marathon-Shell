# Marathon PinePhone U-Boot script.
#
# Upstream device-pine64-pinephone's uboot-script.cmd with only the
# kernel arguments changed, so Plymouth shows the Marathon splash on the
# panel instead of a text console:
#
#   * console=tty1               (was tty0) kernel output on the panel VT
#   * splash                     Plymouth takes the display
#   * vt.global_cursor_default=0 no VT cursor blinking behind the splash
#
# Compiled to /boot/boot.scr by mkosi.finalize, replacing the stock one.

gpio set 98
gpio set 114

if test ${mmc_bootdev} -eq 0 ; then
	echo "Booting from SD";
	setenv bootdev 0;
else
	echo "Booting from eMMC";
	setenv bootdev 2;
fi;

setenv bootargs init=/init.sh rw console=tty1 console=ttyS0,115200 earlycon=uart,mmio32,0x01c28000 panic=10 consoleblank=0 splash loglevel=1 vt.global_cursor_default=0 PMOS_FORCE_PARTITION_RESIZE pmos_boot=/dev/mmcblk${bootdev}p1 pmos_root=/dev/mmcblk${bootdev}p2

printenv

echo Detecting psci idle state
fdt addr ${fdtcontroladdr}
fdt get name pscifdt /cpus/idle-states /
if test $? -eq 0; then
	echo PSCI idle state enabled;
	setenv iscpscienabled 1;
else
	echo PSCI idle state disabled;
fi

echo Loading DTB
load mmc ${mmc_bootdev}:1 ${fdt_addr_r} ${fdtfile}
fdt addr ${fdt_addr_r}
fdt resize 2048

if printenv ram_freq; then
	echo Adding FTD RAM clock
	fdt mknode / memory
	fdt set /memory ram_freq ${ram_freq}
fi

if test ${iscpscienabled} -eq 1; then
	echo Applying PSCI DTBO;
	load mmc ${mmc_bootdev}:1 ${fdtoverlay_addr_r} sun50i-a64-psci.dtbo
	fdt apply ${fdtoverlay_addr_r}
fi

echo Loading Initramfs
load mmc ${mmc_bootdev}:1 ${ramdisk_addr_r} initramfs
setenv ramdisk_size ${filesize}

echo Loading Kernel
load mmc ${mmc_bootdev}:1 ${kernel_addr_r} vmlinuz

gpio set 115


echo Loading user script
setenv user_scriptaddr 0x50f00000
load mmc ${mmc_bootdev}:1 ${user_scriptaddr} user.scr
if test $? -eq 0; then source ${user_scriptaddr}; else echo No user script found; fi

echo Booting kernel
gpio set 116
gpio clear 98
booti ${kernel_addr_r} ${ramdisk_addr_r}:${ramdisk_size} ${fdt_addr_r}
