The patches against the kernel tree, `0001`, `0003` and `0005`–`0011`, are in
`packaging/packages/linux-zinwa-q25`, which builds the Q25 kernel from ellyq's
`mtk_g99-mainline` at `978b8b67` with them and the phone's own configuration.
`0002` stays here: it is not a kernel-tree patch.

The ADC patch (`0001`) targets `drivers/iio/adc/mt6359-auxadc.c` in the Q25
kernel source based on `978b8b672d68e43b08c891132b974255489889aa`.

Its scale omitted the ADC resolution. On MT6358 BATADC, raw code 25383 was
reported with scale 5400 instead of 5400/32768 mV per count. The generic battery
driver's subsequent conversion overflowed. The patch also rejects an absent
channel descriptor's zero denominator. It changes no sampling, charger, voltage
limit, DT or GPU policy.

The rebuilt EFI was tested on the Q25: scale became `0.164794921`, reported
battery voltage was 4.182–4.183 V, and the full GPU session booted successfully.
Kernel configuration, release and all 12,440 exported-symbol CRC records matched
the prior working kernel. This does not supply state of charge or establish
physical calibration.

Tested EFI SHA256:
`e4c19e018b4f473e702af6eebc1aa57c40997ac1c960611ac5637cae92bca149`.
The prior `7d06cd6f…` kernel, `23e3f8d4…` carrier initrd and `f668fc23…` DT remain
available as the working fallback.

The prebuilt `7.0-r1000` kernel package lacks it; `linux-zinwa-q25` applies it.

`0002-q25-private-mt6358-current-car-snapshot.patch` preserves the separate
external diagnostic source and host fault/encoding tests. Its temporary PMIC
child performs no hardware I/O at probe, exposes two root-only latch/release
transactions, and then remains stopped. It is not an autoloaded fuel-gauge
driver and does not report capacity. The Q25 device trial passed with module
SHA256 `8bb3f59bfbd77f2758eb65ba7604fb38d74a522f5cebaf9f0ad80d41628006d1`:
two samples five seconds apart reported 0 and 50087 µA, with zero errors and
`poisoned=0 stopped=1`. No reset, RTC, charger or rail writes occurred. Stock
configuration supplies 1 mΩ/1.01 scaling; physical calibration remains unverified.

`0003-net-wwan-q25-rpc-metadata-validator.patch` is an independent, inactive
RPC metadata helper. Its source commit is
`bad48847ddb61e80ad534151f1177dcdf0033147`. Host ASan/UBSan checks, public ABI
assertions and ARM64 W=1 compilation passed. No Kbuild activation, module
entrypoint, device access, modem firmware load or radio functionality is implied.
See the modem prior-art document for its missing firmware/memory owner.

`0005`–`0007` carry the board DT. `0005` adds the DTS that the
linux-postmarketos-mediatek-g99 recipe copied into the tree (pmaports
`mt6789-zinwa-q25.dts`, sha512 `a242ca0b…`). `0006` brings it to the DT the
Q25 booted from (`f668fc23…`: framebuffer pitch, touch reset, keyboard on
i2c6, no ramoops).
`0007` adds audio, the AP-side sensor buses, CONNSYS, Wi-Fi and BTIF, as in
`edc93beb…`. Compiled against the 978b8b67 `mt6789.dtsi`, the result equals
`edc93beb…` node by node with phandles resolved, except that the BMP390 node
is dropped: both of its addresses NACK on the device. No gpio-backlight.

`0008` hands GPIO84 (panel bias) and GPIO85 (panel reset) from the
always-on regulator to `q25-panel-doze`, which sleeps the panel in Doze. The
result equals the device-tested `8c282e5d…` (edc93beb plus the panel-doze
overlay) except for the BMP390 node.

`0009` fixes the MT6358/MT6366 PMIC interrupt handler's AUD and MISC group
bits (7 and 8 in TOP_INT_STATUS0, as in MediaTek's headers; mainline has 6
and 7). Without it an ACCDET interrupt is read as MISC, never dispatched or
acknowledged, and the PMIC line storms at about 24000/s. The constants feed
only `.top_offset` in `mt6358_irq_handler`; MT6357 and MT6359 have their own
enums. `MFD_MT6397` is built in, so it takes effect with `linux-zinwa-q25`;
on the prebuilt kernel `q25-mt6366-irqfix` (modules/audio) patches the table
at runtime, and it does nothing on a fixed kernel.

`0010` reserves 256 MiB below 4 GiB as a `shared-dma-pool` for CAMSV, whose
32-bit `dma_alloc_coherent()` otherwise stops at 4 MiB, short of the
sensors' full-resolution frames. The camera overlay (`modules/camera`)
names the pool by its fixed phandle, `0x93`. The Q25 boots the same node
added to its current DTB.

`0011` adds the MD1 owner and ECCCI nodes of `modem/dt/q25-modem.dtso`, with
labels in place of its raw phandles. With `0005`–`0011` the DTB equals the one
the Q25 boots (`7ae8313e…`: `edc93beb…` plus the panel-doze and modem
overlays and the camera pool) node by node with phandles resolved, except
for the BMP390 node and the overlays' `__symbols__`. `md1-owner` and
`md_power_o1` keep that DT's phandles (`0x90`, `0x91`), so no other phandle
moves. With the modem nodes `q25-md1-owner` autoloads and `q25-modem` starts
the modem stack at boot, as on the tested phone.
