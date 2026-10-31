The ADC patch targets `drivers/iio/adc/mt6359-auxadc.c` in the Q25 kernel source
based on `978b8b672d68e43b08c891132b974255489889aa`.

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

This patch records the tested bring-up change. It is not yet applied by the
canonical kernel APK recipe; the existing `7.0-r1000` package must not be assumed
to contain it.

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
linux-postmarketos-mediatek-g99 recipe copies into the tree (pmaports
`mt6789-zinwa-q25.dts`, sha512 `a242ca0b…`); a recipe applying this series
must stop copying its own. `0006` brings it to the DT the Q25 booted from
(`f668fc23…`: framebuffer pitch, touch reset, keyboard on i2c6, no ramoops).
`0007` adds audio, the AP-side sensor buses, CONNSYS, Wi-Fi and BTIF, as in
`edc93beb…`. Compiled against the 978b8b67 `mt6789.dtsi`, the result equals
`edc93beb…` node by node with phandles resolved, except that the BMP390 node
is dropped: both of its addresses NACK on the device. No gpio-backlight.

`0008` hands GPIO84 (panel bias) and GPIO85 (panel reset) from the
always-on regulator to `q25-panel-doze`, which sleeps the panel in Doze. The
result equals the device-tested `8c282e5d…` (edc93beb plus the panel-doze
overlay) except for the BMP390 node. The board DTS carries no modem nodes:
with them, `q25-md1-owner` would autoload and `q25-md1-off.service` would
skip, leaving MD1 powered.
